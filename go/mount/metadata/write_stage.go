// Staged writes reserve inode content safely before their journal entry exists.
package metadata

import (
	"errors"
	"fmt"
	"io"
	"strings"
)

type stagedWriteReservation struct {
	inode              uint64
	parent             uint64
	name               string
	ref                ContentRef
	created            bool
	reservedGeneration uint64
	previousGeneration uint64
}

// StageWrite copies source bytes into durable pending content for one inode.
func (s *Service) StageWrite(inode, generation uint64, source io.Reader, size int64) (ContentRef, error) {
	s.operationMu.RLock()
	defer s.operationMu.RUnlock()
	return s.stagePendingContent(inode, generation, source, size, false)
}

// StageWriteForName allocates (if needed) and returns the target inode before
// copying durable pending content. Call Write after staging to journal the op.
func (s *Service) StageWriteForName(parent uint64, name string, generation uint64, source io.Reader, size int64) (uint64, ContentRef, error) {
	reservation, err := s.stageWriteForName(parent, name, generation, source, size)
	if err != nil {
		return 0, ContentRef{}, err
	}
	return reservation.inode, reservation.ref, nil
}

func (s *Service) stageWriteForName(
	parent uint64, name string, generation uint64, source io.Reader, size int64,
) (stagedWriteReservation, error) {
	s.operationMu.RLock()
	defer s.operationMu.RUnlock()
	if s.isReadOnly() {
		return stagedWriteReservation{}, ErrReadOnly
	}
	inode, created, err := s.ensureWriteInode(parent, name)
	if err != nil {
		return stagedWriteReservation{}, err
	}
	reservation := stagedWriteReservation{inode: inode, parent: parent, name: name, created: created}
	if generation == 0 {
		generation, reservation.previousGeneration, err = s.reserveContentGeneration(inode)
		if err != nil {
			cleanupErr := s.rollbackStagedWrite(reservation)
			return stagedWriteReservation{}, combineStageErrors(err, cleanupErr)
		}
		reservation.reservedGeneration = generation
	}
	ref, err := s.stagePendingContent(inode, generation, source, size, true)
	if err != nil {
		cleanupErr := s.rollbackStagedWrite(reservation)
		return stagedWriteReservation{}, combineStageErrors(err, cleanupErr)
	}
	reservation.ref = ref
	return reservation, nil
}

func combineStageErrors(primary, cleanup error) error {
	if cleanup == nil {
		return primary
	}
	return fmt.Errorf("%w; staged-write cleanup: %w", primary, cleanup)
}

// rollbackStagedWrite releases a ref that never reached the journal and
// removes a newly allocated inode when no concurrent operation claimed it.
func (s *Service) rollbackStagedWrite(reservation stagedWriteReservation) error {
	var releaseErr error
	if reservation.ref.Generation != 0 {
		generation := reservation.ref.Generation
		releaseErr = s.releaseContent(reservation.inode, &generation, false)
	}
	restoreErr := s.store.update(func(tx boltTxT) error {
		record, err := getInode(tx, reservation.inode)
		if err != nil {
			return nil
		}
		if reservation.reservedGeneration != 0 && record.ContentGeneration == reservation.reservedGeneration {
			record.ContentGeneration = reservation.previousGeneration
			if err := putInode(tx, record); err != nil {
				return err
			}
		}
		if !reservation.created || inodeHasJournalOp(tx, reservation.inode) {
			return nil
		}
		if record, err = getInode(tx, reservation.inode); err != nil || record.State != StatePending || record.RemoteParentID != 0 {
			return nil
		}
		if tx.Bucket([]byte(bucketContentRefs)).Get(contentRefKey(reservation.inode, reservation.ref.Generation)) != nil {
			return nil
		}
		if dirent, err := getDirent(tx, reservation.parent, MakeNameKey(reservation.name)); err == nil && dirent.ChildID == reservation.inode {
			if err := deleteDirent(tx, reservation.parent, MakeNameKey(reservation.name)); err != nil {
				return err
			}
			parent, err := getInode(tx, reservation.parent)
			if err != nil {
				return err
			}
			parent.LocalRevision++
			if err := putInode(tx, parent); err != nil {
				return err
			}
		}
		return tx.Bucket([]byte(bucketInodes)).Delete(encodeUint64(reservation.inode))
	})
	return errors.Join(releaseErr, restoreErr)
}

func inodeHasJournalOp(tx boltTxT, inode uint64) bool {
	found := false
	_ = tx.Bucket([]byte(bucketInodeOps)).ForEach(func(key, _ []byte) error {
		if decodeUint64(key[:8]) == inode {
			found = true
		}
		return nil
	})
	return found
}

// reserveContentGeneration gives rapid path-level writes distinct ContentRef
// keys before their immutable chunks are staged outside a journal transaction.
func (s *Service) reserveContentGeneration(inode uint64) (uint64, uint64, error) {
	var generation, previous uint64
	err := s.store.update(func(tx boltTxT) error {
		record, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		previous = record.ContentGeneration
		generation = previous + 1
		record.ContentGeneration = generation
		return putInode(tx, record)
	})
	return generation, previous, err
}

func (s *Service) ensureWriteInode(parent uint64, name string) (uint64, bool, error) {
	name = strings.TrimSpace(name)
	if name == "" || strings.Contains(name, "/") {
		return 0, false, fmt.Errorf("metadata: file name is required")
	}
	nameKey := MakeNameKey(name)
	var inode uint64
	created := false
	err := s.store.update(func(tx boltTxT) error {
		parentRecord, err := getInode(tx, parent)
		if err != nil {
			return err
		}
		if parentRecord.Kind != KindDirectory {
			return fmt.Errorf("metadata: parent %d is not a directory", parent)
		}
		existing, direntErr := getDirent(tx, parent, nameKey)
		if direntErr == nil {
			inode = existing.ChildID
			return nil
		}
		if !errors.Is(direntErr, ErrNotFound) {
			return direntErr
		}
		inode, err = allocateInode(tx)
		if err != nil {
			return err
		}
		record := Inode{ID: inode, Kind: KindFile, DesiredParentID: parent, DesiredName: name, State: StatePending, LocalRevision: 1}
		if err := putInode(tx, record); err != nil {
			return err
		}
		if err := putDirent(tx, parent, Dirent{ChildID: inode, DisplayName: name, NameKey: nameKey}); err != nil {
			return err
		}
		parentRecord.LocalRevision++
		if err := putInode(tx, parentRecord); err != nil {
			return err
		}
		created = true
		return nil
	})
	return inode, created, err
}
