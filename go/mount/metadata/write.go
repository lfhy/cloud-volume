// Write APIs mutate only the Desired tree plus journal; remote execution is owned by the worker.
package metadata

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// WriteOptions carries caller intent for one desired-tree mutation.
type WriteOptions struct {
	Origin     string
	TaskID     string
	LocalPath  string
	Size       int64
	MTime      string
	ForceRetry bool
}

// CreateDirectory records a desired mkdir and returns its inode.
func (s *Service) CreateDirectory(parent uint64, name string, opts WriteOptions) (uint64, error) {
	if s.readOnly {
		return 0, ErrReadOnly
	}
	name = strings.TrimSpace(name)
	if name == "" || strings.Contains(name, "/") {
		return 0, fmt.Errorf("metadata: directory name is required")
	}
	nameKey := MakeNameKey(name)
	var inode uint64
	err := s.store.update(func(tx boltTxT) error {
		parentRecord, err := getInode(tx, parent)
		if err != nil {
			return err
		}
		if parentRecord.Kind != KindDirectory {
			return fmt.Errorf("metadata: parent %d is not a directory", parent)
		}
		if existing, err := getDirent(tx, parent, nameKey); err == nil {
			child, childErr := getInode(tx, existing.ChildID)
			if childErr != nil {
				return childErr
			}
			if child.Kind == KindDirectory && child.State != StateTombstone {
				inode = child.ID
				return nil
			}
			return ErrCollision
		} else if !errors.Is(err, ErrNotFound) {
			return err
		}
		inode, err = allocateInode(tx)
		if err != nil {
			return err
		}
		if err := putInode(tx, Inode{
			ID: inode, Kind: KindDirectory, DesiredParentID: parent, DesiredName: name,
			State: StatePending, LocalRevision: 1,
		}); err != nil {
			return err
		}
		if err := putDirent(tx, parent, Dirent{ChildID: inode, DisplayName: name, NameKey: nameKey}); err != nil {
			return err
		}
		parentRecord.LocalRevision++
		if err := putInode(tx, parentRecord); err != nil {
			return err
		}
		return appendOp(tx, Op{
			Type: OpMkdir, InodeID: inode, NewParent: parent, NewName: name,
			State: OpStatePending, Origin: origin(opts), CreatedAtUnixNano: nowUnix(),
			NextAttemptUnixNano: time.Now().Add(s.quiet).UnixNano(),
		})
	})
	return inode, err
}

// StageWrite copies source bytes into durable pending content for one inode.
func (s *Service) StageWrite(inode, generation uint64, source io.Reader, size int64) (ContentRef, error) {
	dir := filepath.Join(s.store.namespace.Root, "pending-content", fmt.Sprintf("%d", inode), fmt.Sprintf("%d", generation))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return ContentRef{}, err
	}
	target := filepath.Join(dir, "content")
	file, err := os.Create(target)
	if err != nil {
		return ContentRef{}, err
	}
	written, copyErr := io.Copy(file, source)
	closeErr := file.Close()
	if copyErr != nil {
		_ = os.Remove(target)
		return ContentRef{}, copyErr
	}
	if closeErr != nil {
		_ = os.Remove(target)
		return ContentRef{}, closeErr
	}
	if err := syncFileAndParent(target); err != nil {
		return ContentRef{}, err
	}
	if size < 0 {
		size = written
	}
	ref := ContentRef{Inode: inode, Generation: generation, LocalPath: target, Size: size}
	err = s.store.update(func(tx boltTxT) error {
		data, err := encodeJSON(ref)
		if err != nil {
			return err
		}
		return tx.Bucket([]byte(bucketContentRefs)).Put(contentRefKey(inode, generation), data)
	})
	return ref, err
}

// StageWriteForName allocates (if needed) and returns the target inode before
// copying durable pending content. Call Write after staging to journal the op.
func (s *Service) StageWriteForName(parent uint64, name string, generation uint64, source io.Reader, size int64) (uint64, ContentRef, error) {
	if s.readOnly {
		return 0, ContentRef{}, ErrReadOnly
	}
	inode, err := s.ensureWriteInode(parent, name)
	if err != nil {
		return 0, ContentRef{}, err
	}
	ref, err := s.StageWrite(inode, generation, source, size)
	return inode, ref, err
}

func (s *Service) ensureWriteInode(parent uint64, name string) (uint64, error) {
	name = strings.TrimSpace(name)
	if name == "" || strings.Contains(name, "/") {
		return 0, fmt.Errorf("metadata: file name is required")
	}
	nameKey := MakeNameKey(name)
	var inode uint64
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
		return putInode(tx, parentRecord)
	})
	return inode, err
}

// Write records desired file content for an existing or new inode.
func (s *Service) Write(parent uint64, name string, ref ContentRef, opts WriteOptions) (uint64, error) {

	if s.readOnly {
		return 0, ErrReadOnly
	}
	name = strings.TrimSpace(name)
	if name == "" || strings.Contains(name, "/") {
		return 0, fmt.Errorf("metadata: file name is required")
	}
	nameKey := MakeNameKey(name)
	var inode uint64
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
		} else if errors.Is(direntErr, ErrNotFound) {
			inode, err = allocateInode(tx)
			if err != nil {
				return err
			}
			if err := putInode(tx, Inode{ID: inode, Kind: KindFile, DesiredParentID: parent, DesiredName: name, State: StatePending, LocalRevision: 1, ContentGeneration: ref.Generation}); err != nil {
				return err
			}
			if err := putDirent(tx, parent, Dirent{ChildID: inode, DisplayName: name, NameKey: nameKey}); err != nil {
				return err
			}
			parentRecord.LocalRevision++
			if err := putInode(tx, parentRecord); err != nil {
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
		record.Kind = KindFile
		record.DesiredParentID, record.DesiredName = parent, name
		record.Size, record.MTime = ref.Size, opts.MTime
		record.ContentGeneration = ref.Generation
		record.LocalRevision++
		record.State = StatePending
		if err := putInode(tx, record); err != nil {
			return err
		}
		return appendOp(tx, Op{
			Type: OpWrite, InodeID: inode, NewParent: parent, NewName: name,
			ExpectedRemoteFingerprint: expectedFingerprint(record), State: OpStatePending,
			Origin: origin(opts), CreatedAtUnixNano: nowUnix(),
			NextAttemptUnixNano: time.Now().Add(s.quiet).UnixNano(),
		})
	})
	return inode, err
}

// Rename moves one inode to a new parent/name and never rewrites descendants.
func (s *Service) Rename(inode, newParent uint64, newName string, opts WriteOptions) error {
	if s.readOnly {
		return ErrReadOnly
	}
	newName = strings.TrimSpace(newName)
	if newName == "" || strings.Contains(newName, "/") {
		return fmt.Errorf("metadata: target name is required")
	}
	nameKey := MakeNameKey(newName)
	return s.store.update(func(tx boltTxT) error {
		record, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		if record.State == StateTombstone {
			return ErrNotFound
		}
		parent, err := getInode(tx, newParent)
		if err != nil {
			return err
		}
		if parent.Kind != KindDirectory {
			return fmt.Errorf("metadata: target parent %d is not a directory", newParent)
		}
		if newParent != record.DesiredParentID || nameKey != MakeNameKey(record.DesiredName) {
			if err := ensureNotDescendant(tx, inode, newParent); err != nil {
				return err
			}
		}
		if target, err := getDirent(tx, newParent, nameKey); err == nil {
			if target.ChildID == inode {
				return nil
			}
			targetRecord, err := getInode(tx, target.ChildID)
			if err != nil {
				return err
			}
			if targetRecord.Kind == KindDirectory {
				return ErrCollision
			}
			if err := markTombstone(tx, target.ChildID); err != nil {
				return err
			}
			if err := deleteDirent(tx, newParent, nameKey); err != nil {
				return err
			}
			if err := appendReplacedDelete(tx, targetRecord, opts); err != nil {
				return err
			}
		} else if !errors.Is(err, ErrNotFound) {
			return err
		}
		oldNameKey := MakeNameKey(record.DesiredName)
		if err := deleteDirent(tx, record.DesiredParentID, oldNameKey); err != nil {
			return err
		}
		if oldParentRecord, err := getInode(tx, record.DesiredParentID); err == nil {
			oldParentRecord.LocalRevision++
			if err := putInode(tx, oldParentRecord); err != nil {
				return err
			}
		} else {
			return err
		}
		parent.LocalRevision++
		if err := putInode(tx, parent); err != nil {
			return err
		}
		record.DesiredParentID, record.DesiredName = newParent, newName
		record.LocalRevision++
		if record.State == StateSynced {
			record.State = StatePending
		}
		if err := putInode(tx, record); err != nil {
			return err
		}
		if err := putDirent(tx, newParent, Dirent{ChildID: inode, DisplayName: newName, NameKey: nameKey}); err != nil {
			return err
		}
		return appendOp(tx, Op{
			Type: OpRename, InodeID: inode, OldParent: oldParent(record), NewParent: newParent,
			OldName: record.RemoteName, NewName: newName, State: OpStatePending,
			Origin: origin(opts), CreatedAtUnixNano: nowUnix(),
			NextAttemptUnixNano: time.Now().Add(s.quiet).UnixNano(),
		})
	})
}

// Delete marks an inode tombstoned and schedules provider deletion.
func (s *Service) Delete(inode uint64, opts WriteOptions) error {
	if s.readOnly {
		return ErrReadOnly
	}
	return s.store.update(func(tx boltTxT) error {
		record, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		if record.State == StateTombstone {
			return nil
		}
		if err := deleteDirent(tx, record.DesiredParentID, MakeNameKey(record.DesiredName)); err != nil {
			return err
		}
		if parentRecord, err := getInode(tx, record.DesiredParentID); err == nil {
			parentRecord.LocalRevision++
			if err := putInode(tx, parentRecord); err != nil {
				return err
			}
		} else {
			return err
		}
		if err := markTombstone(tx, inode); err != nil {
			return err
		}
		return appendOp(tx, Op{
			Type: OpDelete, InodeID: inode, OldParent: record.RemoteParentID,
			OldName: record.RemoteName, State: OpStatePending, Origin: origin(opts),
			CreatedAtUnixNano: nowUnix(), NextAttemptUnixNano: time.Now().Add(s.quiet).UnixNano(),
		})
	})
}

func markTombstone(tx boltTxT, inode uint64) error {
	record, err := getInode(tx, inode)
	if err != nil {
		return err
	}
	if record.State == StateTombstone {
		return nil
	}
	record.State = StateTombstone
	record.LocalRevision++
	return putInode(tx, record)
}

func ensureNotDescendant(tx boltTxT, inode, candidate uint64) error {
	for depth, current := 0, candidate; depth < 1024; depth++ {
		if current == inode {
			return ErrCycle
		}
		if current == rootInode {
			return nil
		}
		record, err := getInode(tx, current)
		if err != nil {
			return err
		}
		current = record.DesiredParentID
	}
	return ErrCycle
}

func appendOp(tx boltTxT, op Op) error {
	journal := tx.Bucket([]byte(bucketJournal))
	cursor := journal.Cursor()
	seq := uint64(1)
	if key, _ := cursor.Last(); key != nil {
		seq = decodeUint64(key) + 1
	}
	op.Seq = seq
	return putOp(tx, op, Op{})
}

func appendReplacedDelete(tx boltTxT, victim Inode, opts WriteOptions) error {
	if victim.RemoteParentID == 0 && victim.RemoteName == "" {
		// The replaced inode never reached the provider, so no remote delete is
		// needed; its tombstone already hides it from desired listings.
		return nil
	}
	return appendOp(tx, Op{
		Type: OpDelete, InodeID: victim.ID, OldParent: victim.RemoteParentID,
		OldName: victim.RemoteName, State: OpStatePending, Origin: origin(opts),
		CreatedAtUnixNano: nowUnix(), NextAttemptUnixNano: nowUnix(),
	})
}

func origin(opts WriteOptions) string {
	if strings.TrimSpace(opts.Origin) != "" {
		return strings.TrimSpace(opts.Origin)
	}
	return "local"
}

func expectedFingerprint(record Inode) string {
	if record.RemoteParentID == 0 {
		return ""
	}
	return record.RemoteFingerprint
}

func oldParent(record Inode) uint64 { return record.RemoteParentID }

func nowUnix() int64 { return time.Now().UnixNano() }

func syncFileAndParent(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	syncErr := file.Sync()
	closeErr := file.Close()
	if syncErr != nil {
		return syncErr
	}
	if closeErr != nil {
		return closeErr
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	syncErr = dir.Sync()
	closeErr = dir.Close()
	if syncErr != nil {
		return syncErr
	}
	return closeErr
}

func contentRefKey(inode, generation uint64) []byte {
	return inodeOpKey(inode, generation)
}
