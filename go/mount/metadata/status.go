// Worker support helpers resolve desired/remote paths and confirm provider results.
package metadata

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path"
	"strings"
	"time"

	storageops "remote-storage/go/storage"
)

func (s *Service) desiredDirTarget(inode uint64) (string, uint64, string, error) {
	var record Inode
	err := s.store.view(func(tx boltTxT) error {
		value, err := getInode(tx, inode)
		record = value
		return err
	})
	if err != nil {
		return "", 0, "", err
	}
	if record.Kind != KindDirectory {
		return "", 0, "", fmt.Errorf("metadata: inode %d is not a directory", inode)
	}
	desired, err := s.Path(inode)
	if err != nil {
		return "", 0, "", err
	}
	return desired, record.DesiredParentID, record.DesiredName, nil
}

func (s *Service) desiredPath(inode uint64) (string, error) {
	return s.Path(inode)
}

func (s *Service) remoteTarget(inode uint64) (Inode, error) {
	var record Inode
	err := s.store.view(func(tx boltTxT) error {
		value, err := getInode(tx, inode)
		record = value
		return err
	})
	if err != nil {
		return Inode{}, err
	}
	if record.RemoteParentID != 0 {
		remotePath, err := s.remotePathLocked(record.RemoteParentID, record.RemoteName)
		if err != nil {
			return Inode{}, err
		}
		record.RemoteName = remotePath
	}
	return record, nil
}

func (s *Service) remotePathLocked(parent uint64, name string) (string, error) {
	if parent == rootInode {
		return name, nil
	}
	var resolved string
	err := s.store.view(func(tx boltTxT) error {
		segments := []string{name}
		current := parent
		visited := map[uint64]bool{current: true}
		for depth := 0; depth < 1024; depth++ {
			record, err := getInode(tx, current)
			if err != nil {
				return err
			}
			if record.ID == rootInode {
				reverse(segments)
				resolved = JoinPath(segments)
				return nil
			}
			if visited[record.RemoteParentID] {
				return ErrCycle
			}
			visited[record.RemoteParentID] = true
			segments = append(segments, record.RemoteName)
			current = record.RemoteParentID
		}
		return ErrCycle
	})
	return resolved, err
}

func (s *Service) desiredRemoteTarget(record Inode) string {
	value, err := s.Path(record.ID)
	if err != nil {
		return record.DesiredName
	}
	return value
}

func (s *Service) pendingWrite(inode uint64) (Inode, ContentRef, error) {
	var record Inode
	var ref ContentRef
	err := s.store.view(func(tx boltTxT) error {
		value, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		record = value
		raw := tx.Bucket([]byte(bucketContentRefs)).Get(contentRefKey(inode, record.ContentGeneration))
		if raw == nil {
			if record.RemoteFingerprint == "" {
				return fmt.Errorf("metadata: inode %d has no staged content", inode)
			}
			return nil
		}
		return decodeJSON(raw, &ref)
	})
	return record, ref, err
}

func (s *Service) confirmRemote(ctx context.Context, inode, parent uint64, name string, isFile bool) error {
	record, err := s.remoteTarget(inode)
	if err != nil {
		return err
	}
	target := record.RemoteName
	if record.RemoteParentID != 0 && target == record.DesiredName {
		if desired, pathErr := s.Path(inode); pathErr == nil {
			target = desired
		}
	}
	info, headErr := s.backend.HeadObject(ctx, s.store.namespace.Bucket, RemoteKey(target))
	if headErr != nil {
		if errors.Is(headErr, os.ErrNotExist) && !isFile {
			// Providers without explicit directory markers may legitimately
			// report missing markers once children exist.
			return s.commitConfirmation(inode, parent, name, "")
		}
		return headErr
	}
	fingerprint := Fingerprint(storageops.ObjectInfo{
		Size: info.Size, LastModified: info.LastModified, ETag: info.ETag,
	})
	return s.commitConfirmation(inode, parent, name, fingerprint)
}

func (s *Service) commitConfirmation(inode, parent uint64, name, fingerprint string) error {
	return s.store.update(func(tx boltTxT) error {
		record, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		record.RemoteParentID, record.RemoteName = parent, name
		if fingerprint != "" {
			record.RemoteFingerprint = fingerprint
		}
		if record.State != StateTombstone {
			record.State = StateSynced
		}
		return putInode(tx, record)
	})
}

func (s *Service) retireContent(inode, generation uint64) error {
	err := s.store.update(func(tx boltTxT) error {
		return tx.Bucket([]byte(bucketContentRefs)).Delete(contentRefKey(inode, generation))
	})
	if err != nil {
		return err
	}
	_ = os.RemoveAll(path.Dir(contentRefDirPath(s, inode, generation)))
	return nil
}

func (s *Service) deleteInodeRecord(inode uint64) error {
	return s.store.update(func(tx boltTxT) error {
		if err := tx.Bucket([]byte(bucketInodes)).Delete(encodeUint64(inode)); err != nil {
			return err
		}
		return tx.Bucket([]byte(bucketContentRefs)).Delete(encodeUint64(inode))
	})
}

func markInodeConflict(tx boltTxT, inode uint64) error {
	record, err := getInode(tx, inode)
	if err != nil {
		return err
	}
	record.State = StateConflict
	return putInode(tx, record)
}

func getOp(tx boltTxT, seq uint64) (Op, error) {
	raw := tx.Bucket([]byte(bucketJournal)).Get(encodeUint64(seq))
	if raw == nil {
		return Op{}, ErrNotFound
	}
	var op Op
	if err := decodeJSON(raw, &op); err != nil {
		return Op{}, err
	}
	return op, nil
}

func contentRefDirPath(s *Service, inode, generation uint64) string {
	return strings.Join([]string{
		s.store.namespace.Root, "pending-content", fmt.Sprintf("%d", inode), fmt.Sprintf("%d", generation), "content",
	}, string(os.PathSeparator))
}

// Status summarizes namespace health for bridge diagnostics.
type Status struct {
	Namespace          string `json:"namespace"`
	SchemaVersion      uint64 `json:"schemaVersion"`
	InodeCount         int    `json:"inodeCount"`
	MaterializedCount  int    `json:"materializedCount"`
	PendingOps         int    `json:"pendingOps"`
	FailedOps          int    `json:"failedOps"`
	ConflictInodes     int    `json:"conflictInodes"`
	LastVerifiedUnixNs int64  `json:"lastVerifiedUnixNs"`
	StaleCursorCount   int64  `json:"staleCursorCount"`
	RebuildCount       int64  `json:"rebuildCount"`
}

// Status computes current diagnostics for one namespace.
func (s *Service) Status() Status {
	status := Status{Namespace: s.store.namespace.ID, SchemaVersion: SchemaVersion}
	_ = s.store.view(func(tx boltTxT) error {
		status.InodeCount = tx.Bucket([]byte(bucketInodes)).Stats().KeyN
		status.MaterializedCount = tx.Bucket([]byte(bucketListingState)).Stats().KeyN
		_ = tx.Bucket([]byte(bucketReadyOps)).ForEach(func(key, _ []byte) error {
			if OpState(key[0]) == OpStateFailed {
				status.FailedOps++
			} else {
				status.PendingOps++
			}
			return nil
		})
		_ = tx.Bucket([]byte(bucketInodes)).ForEach(func(_, value []byte) error {
			var record Inode
			if decodeJSON(value, &record) == nil && record.State == StateConflict {
				status.ConflictInodes++
			}
			return nil
		})
		_ = tx.Bucket([]byte(bucketJournal)).ForEach(func(_, value []byte) error {
			var op Op
			if decodeJSON(value, &op) == nil && op.AppliedAtUnixNano > status.LastVerifiedUnixNs {
				status.LastVerifiedUnixNs = op.AppliedAtUnixNano
			}
			return nil
		})
		return nil
	})
	return status
}

// ResetResult reports whether a namespace was rebuilt or blocked by pending data.
type ResetResult struct {
	Reset    bool `json:"reset"`
	Pending  int  `json:"pending"`
	Required bool `json:"forceRequired"`
}

// Reset deletes the namespace database after checking pending operations.
func (s *Service) Reset(force bool) (ResetResult, error) {
	status := s.Status()
	if status.PendingOps > 0 || status.FailedOps > 0 {
		if !force {
			return ResetResult{Pending: status.PendingOps + status.FailedOps, Required: true}, nil
		}
	}
	if err := s.store.Close(); err != nil {
		return ResetResult{}, err
	}
	root := s.store.namespace.Root
	_ = os.RemoveAll(root)
	store, err := OpenStore(s.store.namespace)
	if err != nil {
		return ResetResult{}, err
	}
	s.store = store
	return ResetResult{Reset: true}, nil
}

// Close releases the backing database.
func (s *Service) Close() error { return s.store.Close() }

var _ = time.Now
