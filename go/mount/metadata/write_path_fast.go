package metadata

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"
)

// writePathInodeLocked is the mount/page fast path. Chunk files are made
// durable and protected first; one bbolt transaction then owns the inode,
// ContentRef, chunk links, and journal operation together.
func (s *Service) writePathInodeLocked(
	ctx context.Context,
	parent uint64,
	name string,
	source io.Reader,
	declaredSize int64,
	opts WriteOptions,
) (uint64, ContentRef, error) {
	s.operationMu.RLock()
	defer s.operationMu.RUnlock()
	if s.isReadOnly() {
		return 0, ContentRef{}, ErrReadOnly
	}
	name = strings.TrimSpace(name)
	if name == "" || strings.Contains(name, "/") {
		return 0, ContentRef{}, fmt.Errorf("metadata: file name is required")
	}
	if err := contextError(ctx); err != nil {
		return 0, ContentRef{}, err
	}
	// Path callers hold pathWriteMu, but low-level inode mutations do not. Pin
	// the resolved target so staging cannot later write into a moved directory.
	var expectedParentRevision uint64
	var expectedInode uint64
	if err := s.store.view(func(tx boltTxT) error {
		parentRecord, err := getInode(tx, parent)
		if err != nil {
			return err
		}
		if parentRecord.Kind != KindDirectory {
			return fmt.Errorf("metadata: parent %d is not a directory", parent)
		}
		expectedParentRevision = parentRecord.LocalRevision
		dirent, err := getDirent(tx, parent, MakeNameKey(name))
		if errors.Is(err, ErrNotFound) {
			return nil
		}
		if err != nil {
			return err
		}
		expectedInode = dirent.ChildID
		return nil
	}); err != nil {
		return 0, ContentRef{}, err
	}

	s.chunkMu.Lock()
	defer s.chunkMu.Unlock()
	hashes, sizes, written, err := s.stageChunksLocked(source)
	if err != nil {
		_ = s.syncChunkProtectionLocked()
		return 0, ContentRef{}, err
	}
	if declaredSize >= 0 && declaredSize != written {
		_ = s.syncChunkProtectionLocked()
		return 0, ContentRef{}, fmt.Errorf(
			"metadata: staged size mismatch: declared=%d actual=%d", declaredSize, written,
		)
	}
	if err := contextError(ctx); err != nil {
		_ = s.syncChunkProtectionLocked()
		return 0, ContentRef{}, err
	}

	// Do not hold the quiet barrier while hashing or syncing bytes. The worker
	// is excluded from this final journal commit, where the deadline is set.
	mutation := s.beginRemoteMutation()
	committed := false
	var inode uint64
	var ref ContentRef
	err = s.store.update(func(tx boltTxT) error {
		parentRecord, err := getInode(tx, parent)
		if err != nil {
			return err
		}
		if parentRecord.Kind != KindDirectory {
			return fmt.Errorf("metadata: parent %d is not a directory", parent)
		}
		if parentRecord.LocalRevision != expectedParentRevision {
			return ErrStaleCursor
		}
		nameKey := MakeNameKey(name)
		dirent, direntErr := getDirent(tx, parent, nameKey)
		if direntErr == nil {
			inode = dirent.ChildID
			if inode != expectedInode {
				return ErrStaleCursor
			}
		} else if errors.Is(direntErr, ErrNotFound) {
			if expectedInode != 0 {
				return ErrStaleCursor
			}
			inode, err = allocateInode(tx)
			if err != nil {
				return err
			}
			if err := putInode(tx, Inode{
				ID: inode, Kind: KindFile, DesiredParentID: parent, DesiredName: name,
				State: StatePending, LocalRevision: 1,
			}); err != nil {
				return err
			}
			if err := putDirent(tx, parent, Dirent{
				ChildID: inode, DisplayName: name, NameKey: nameKey,
			}); err != nil {
				return err
			}
		} else {
			return direntErr
		}

		record, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		if record.Kind == KindDirectory {
			return ErrCollision
		}
		// Existing databases predating RemoteMTime can still recover a canceled
		// overwrite from their last visible, confirmed timestamp.
		if record.RemoteMTime == "" && record.State == StateSynced && record.RemoteParentID != 0 {
			record.RemoteMTime = record.MTime
		}
		generation := record.ContentGeneration + 1
		if generation == 0 {
			return fmt.Errorf("metadata: content generation overflow for inode %d", inode)
		}
		ref = ContentRef{Inode: inode, Generation: generation, Chunks: hashes, Size: written}
		record.Kind = KindFile
		record.DesiredParentID, record.DesiredName = parent, name
		record.Size, record.MTime = written, opts.MTime
		record.ContentGeneration = generation
		record.LocalRevision++
		record.State = StatePending
		if err := putInode(tx, record); err != nil {
			return err
		}
		parentRecord.LocalRevision++
		if err := putInode(tx, parentRecord); err != nil {
			return err
		}

		knownSizes := make(map[string]int64, len(hashes))
		for index, hash := range hashes {
			knownSizes[hash] = sizes[index]
		}
		if _, err := applyChunkDeltas(tx, chunkDeltas(nil, hashes), knownSizes); err != nil {
			return err
		}
		data, err := encodeJSON(ref)
		if err != nil {
			return err
		}
		if err := tx.Bucket([]byte(bucketContentRefs)).Put(contentRefKey(inode, generation), data); err != nil {
			return err
		}
		if err := appendOp(tx, Op{
			Type: OpWrite, InodeID: inode, ContentGeneration: generation,
			NewParent: parent, NewName: name, TaskGroupID: strings.TrimSpace(opts.TaskID),
			ExpectedRemoteFingerprint: expectedFingerprint(record), State: OpStatePending,
			Origin: origin(opts), CreatedAtUnixNano: nowUnix(),
			NextAttemptUnixNano: mutation.nextAttempt(),
		}); err != nil {
			return err
		}
		committed = true
		return nil
	})
	mutation.finish(err == nil && committed)
	if err != nil {
		// No bbolt reference was committed, so the prospective manifest can be
		// rebuilt from the live chunk table. Orphan files remain sweepable.
		_ = s.syncChunkProtectionLocked()
		return 0, ContentRef{}, err
	}
	s.finishChunkProtectionWindowLocked()
	return inode, ref, nil
}
