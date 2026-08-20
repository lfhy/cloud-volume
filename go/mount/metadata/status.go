// Worker support helpers resolve desired/remote paths and confirm provider results.
package metadata

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

	storageops "remote-storage/go/storage"
)

// mkdirRemoteTarget preserves a pending directory's current local name while
// resolving its parent through confirmed Remote edges. A later ancestor move
// must not redirect an earlier child mkdir into a remote directory that the
// move is still waiting to create.
func (s *Service) mkdirRemoteTarget(inode uint64) (string, uint64, string, error) {
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
	if record.DesiredParentID == 0 || strings.TrimSpace(record.DesiredName) == "" {
		return "", 0, "", fmt.Errorf("metadata: directory inode %d has no desired target", inode)
	}
	target, err := s.remotePathLocked(record.DesiredParentID, record.DesiredName)
	if err != nil {
		return "", 0, "", err
	}
	return target, record.DesiredParentID, record.DesiredName, nil
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

// writeRemoteTarget resolves a write against the remote parent edge captured
// in its journal payload. A later Desired rename must not redirect an earlier
// upload and leave the old remote source behind.
func (s *Service) writeRemoteTarget(op Op) (string, uint64, string, error) {
	parent, name := op.NewParent, op.NewName
	if parent == 0 || strings.TrimSpace(name) == "" {
		record, err := s.remoteTarget(op.InodeID)
		if err != nil {
			return "", 0, "", err
		}
		parent, name = record.RemoteParentID, record.RemoteName
	}
	if parent == 0 || strings.TrimSpace(name) == "" {
		return "", 0, "", fmt.Errorf("metadata: write op %d has no remote target", op.Seq)
	}
	target, err := s.remotePathLocked(parent, name)
	return target, parent, name, err
}

// verifyExpectedRemote checks a write precondition before mutation. Comparing
// the expected fingerprint after our own upload would mistake that upload for
// an external conflict whenever its ETag naturally changes.
func (s *Service) verifyExpectedRemote(ctx context.Context, backend Backend, op Op, target string) error {
	expected := strings.TrimSpace(op.ExpectedRemoteFingerprint)
	if expected == "" {
		return nil
	}
	info, err := backend.HeadObject(ctx, s.store.namespace.Bucket, RemoteKey(target))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("%w: expected=%s actual=missing", errConflict, expected)
		}
		return err
	}
	actual := Fingerprint(storageops.ObjectInfo{Size: info.Size, LastModified: info.LastModified, ETag: info.ETag})
	if expected != actual {
		return fmt.Errorf("%w: expected=%s actual=%s", errConflict, expected, actual)
	}
	return nil
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
	target, err := s.remotePathLocked(parent, name)
	if err != nil {
		return err
	}
	info, headErr := backend.HeadObject(ctx, s.store.namespace.Bucket, RemoteKey(target))
	if headErr != nil {
		if errors.Is(headErr, os.ErrNotExist) && !isFile {
			// Providers without explicit directory markers may legitimately
			// report missing markers once children exist.
			return s.commitConfirmation(inode, op.Seq, parent, name, "", "")
		}
		return headErr
	}
	fingerprint := Fingerprint(storageops.ObjectInfo{
		Size: info.Size, LastModified: info.LastModified, ETag: info.ETag,
	})
	return s.commitConfirmation(inode, op.Seq, parent, name, fingerprint, info.LastModified)
}

// commitConfirmation atomically records the provider-confirmed edge and metadata.
func (s *Service) commitConfirmation(inode, confirmedSeq, parent uint64, name, fingerprint, lastModified string) error {
	return s.store.update(func(tx boltTxT) error {
		record, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		record.RemoteParentID, record.RemoteName = parent, name
		if fingerprint != "" {
			record.RemoteFingerprint = fingerprint
		}
		if strings.TrimSpace(lastModified) != "" {
			record.RemoteMTime = lastModified
			if !hasLaterUnsettledWrite(tx, inode, confirmedSeq) {
				record.MTime = lastModified
			}
		}
		// A write can confirm its old Remote edge while a later rename/delete is
		// still pending. Keep that Desired intent visible so a refresh cannot
		// revive the remote source and orphan the stable inode.
		if record.State != StateTombstone && record.State != StateConflict && !hasLaterPendingOp(tx, inode, confirmedSeq) {
			record.State = StateSynced
		}
		return putInode(tx, record)
	})
}

func hasLaterPendingOp(tx boltTxT, inode, confirmedSeq uint64) bool {
	index := tx.Bucket([]byte(bucketInodeOps))
	journal := tx.Bucket([]byte(bucketJournal))
	prefix := encodeUint64(inode)
	cursor := index.Cursor()
	for key, _ := cursor.Seek(prefix); key != nil && bytes.HasPrefix(key, prefix); key, _ = cursor.Next() {
		seq := decodeUint64(key[8:])
		if seq <= confirmedSeq {
			continue
		}
		var op Op
		if decodeJSON(journal.Get(encodeUint64(seq)), &op) != nil {
			continue
		}
		if op.State == OpStatePending || op.State == OpStateRunning || op.State == OpStateReconciling || op.State == OpStateVerifying || op.State == OpStateCancelRequested {
			return true
		}
	}
	return false
}

// hasLaterUnsettledWrite preserves the local mtime for a newer generation
// until that exact write has either confirmed or been explicitly canceled.
func hasLaterUnsettledWrite(tx boltTxT, inode, confirmedSeq uint64) bool {
	index := tx.Bucket([]byte(bucketInodeOps))
	journal := tx.Bucket([]byte(bucketJournal))
	prefix := encodeUint64(inode)
	cursor := index.Cursor()
	for key, _ := cursor.Seek(prefix); key != nil && bytes.HasPrefix(key, prefix); key, _ = cursor.Next() {
		seq := decodeUint64(key[8:])
		if seq <= confirmedSeq {
			continue
		}
		var op Op
		if decodeJSON(journal.Get(encodeUint64(seq)), &op) != nil {
			continue
		}
		if op.Type == OpWrite && opStateUnsettled(op.State) {
			return true
		}
	}
	return false
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
		_ = tx.Bucket([]byte(bucketInodes)).ForEach(func(_, value []byte) error {
			status.InodeCount++
			var record Inode
			if decodeJSON(value, &record) == nil && record.State == StateConflict {
				status.ConflictInodes++
			}
			return nil
		})
		_ = tx.Bucket([]byte(bucketListingState)).ForEach(func(_, _ []byte) error {
			status.MaterializedCount++
			return nil
		})
		_ = tx.Bucket([]byte(bucketContentRefs)).ForEach(func(_, _ []byte) error {
			status.PendingContent++
			return nil
		})
		_ = tx.Bucket([]byte(bucketJournal)).ForEach(func(_, value []byte) error {
			var op Op
			if decodeJSON(value, &op) != nil {
				return nil
			}
			switch op.State {
			case OpStatePending, OpStateRunning, OpStateReconciling, OpStateVerifying, OpStateCancelRequested:
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
	s.clearRemoteQuietDeadline()
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
