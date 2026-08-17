// Worker support helpers resolve desired/remote paths and confirm provider results.
package metadata

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

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
		// Resolve through Remote edges first; a never-synced child under a
		// synced directory still has RemoteParentID set but an empty RemoteName,
		// in which case fall back to the Desired path so deletes target the
		// only location the provider could know.
		if strings.TrimSpace(record.RemoteName) != "" {
			remotePath, remoteErr := s.remotePathLocked(record.RemoteParentID, record.RemoteName)
			if remoteErr == nil {
				record.RemoteName = remotePath
				return record, nil
			}
			if !errors.Is(remoteErr, ErrNotFound) {
				return Inode{}, remoteErr
			}
		}
		if desired, pathErr := s.Path(inode); pathErr == nil {
			record.RemoteName = desired
		}
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

func (s *Service) pendingWrite(inode, generation uint64) (Inode, ContentRef, error) {
	var record Inode
	var ref ContentRef
	err := s.store.view(func(tx boltTxT) error {
		value, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		record = value
		if generation == 0 {
			generation = record.ContentGeneration
		}
		if generation == 0 {
			return fmt.Errorf("metadata: inode %d has no staged content", inode)
		}
		raw := tx.Bucket([]byte(bucketContentRefs)).Get(contentRefKey(inode, generation))
		if raw == nil {
			return fmt.Errorf("metadata: inode %d staged content for generation %d is missing", inode, generation)
		}
		return decodeJSON(raw, &ref)
	})
	return record, ref, err
}

func (s *Service) confirmRemote(
	ctx context.Context,
	backend Backend,
	op Op,
	parent uint64,
	name string,
	isFile bool,
) error {
	if backend == nil {
		return fmt.Errorf("metadata: missing backend for remote confirmation")
	}
	inode := op.InodeID
	if _, err := s.remoteTarget(inode); err != nil {
		return err
	}
	// The desired path is authoritative for confirmation: RemoteName reflects
	// the previous remote location, which may be stale after a local rename.
	target, pathErr := s.Path(inode)
	if pathErr != nil {
		target = name
	}
	info, headErr := backend.HeadObject(ctx, s.store.namespace.Bucket, RemoteKey(target))
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
	// A provider change that happened under a previously confirmed object is a
	// conflict, not a successful update, unless this operation is the write that
	// introduced the object (no prior remote identity).
	expected := strings.TrimSpace(op.ExpectedRemoteFingerprint)
	if expected != "" && expected != fingerprint {
		return fmt.Errorf("%w: expected=%s actual=%s", errConflict, expected, fingerprint)
	}
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
	// Remove only the exact generation; newer pending data for the same inode
	// retains its own chunk references.
	return s.releaseContent(inode, &generation, false)
}

func (s *Service) deleteInodeRecord(inode uint64) error {
	return s.releaseContent(inode, nil, true)
}

func markInodeConflict(tx boltTxT, inode uint64) error {
	record, err := getInode(tx, inode)
	if err != nil {
		return err
	}
	record.State = StateConflict
	return putInode(tx, record)
}

func getOp(tx boltTx, seq uint64) (Op, error) {

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

// Status summarizes namespace health for bridge diagnostics.
type Status struct {
	Namespace          string `json:"namespace"`
	SchemaVersion      uint64 `json:"schemaVersion"`
	InodeCount         int    `json:"inodeCount"`
	MaterializedCount  int    `json:"materializedCount"`
	PendingOps         int    `json:"pendingOps"`
	PendingContent     int    `json:"pendingContent"`
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
		status.PendingContent = tx.Bucket([]byte(bucketContentRefs)).Stats().KeyN
		_ = tx.Bucket([]byte(bucketInodes)).ForEach(func(_, value []byte) error {
			var record Inode
			if decodeJSON(value, &record) == nil && record.State == StateConflict {
				status.ConflictInodes++
			}
			return nil
		})
		_ = tx.Bucket([]byte(bucketJournal)).ForEach(func(_, value []byte) error {
			var op Op
			if decodeJSON(value, &op) != nil {
				return nil
			}
			switch op.State {
			case OpStatePending, OpStateRunning:
				// Running entries have left ready_ops while the provider call is
				// in flight, but still make a non-forced reset unsafe.
				status.PendingOps++
			case OpStateFailed:
				status.FailedOps++
			}
			if op.AppliedAtUnixNano > status.LastVerifiedUnixNs {
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

// Reset rebuilds namespace metadata after checking pending operations.
func (s *Service) Reset(force bool) (ResetResult, error) {
	status := s.Status()
	if result, blocked := resetBlocked(status, force); blocked {
		return result, nil
	}
	// Recheck under the operation barrier so a writer or worker cannot create
	// a journal entry after the initial guard and before the rebuild.
	s.operationMu.Lock()
	defer s.operationMu.Unlock()
	status = s.Status()
	if result, blocked := resetBlocked(status, force); blocked {
		return result, nil
	}
	if err := s.store.rebuild(); err != nil {
		return ResetResult{}, err
	}
	if err := s.SweepChunkStore(); err != nil {
		return ResetResult{}, err
	}
	return ResetResult{Reset: true}, nil
}

func resetBlocked(status Status, force bool) (ResetResult, bool) {
	if force || (status.PendingOps == 0 && status.FailedOps == 0 && status.PendingContent == 0) {
		return ResetResult{}, false
	}
	pending := status.PendingOps + status.FailedOps
	if status.PendingContent > pending {
		pending = status.PendingContent
	}
	return ResetResult{Pending: pending, Required: true}, true
}

// Close releases the backing database.
func (s *Service) Close() error { return s.store.Close() }
