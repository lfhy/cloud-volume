// Move execution persists immutable provider targets before changing remote state.
package metadata

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	s3ops "remote-storage/go/s3"
	storageops "remote-storage/go/storage"
)

func (w *Worker) executeMove(ctx context.Context, op Op, backend Backend) error {
	record, err := w.service.remoteTarget(op.InodeID)
	if err != nil {
		return err
	}
	op, err = w.snapshotMove(op, record)
	if err != nil {
		return err
	}
	if op.MoveApplied {
		return w.finishMoveConfirmation(ctx, backend, op, record.Kind)
	}
	if record.RemoteParentID == 0 {
		return w.executeLocalOnlyMove(ctx, backend, op, record)
	}
	if op.MoveSource == op.MoveTarget {
		return w.finishMoveConfirmation(ctx, backend, op, record.Kind)
	}
	taskID := physicalTaskID(w.service.store.namespace.ID, op.Seq)
	s3ops.SetTransferProfile(taskID, w.service.store.namespace.Config.ProfileID)
	if err := backend.MoveObject(
		ctx, w.service.store.namespace.Bucket, op.MoveSource, op.MoveTarget,
		record.Kind == KindDirectory, taskID,
	); err != nil {
		// Provider MOVE implementations do not consistently wrap missing-source
		// replies in os.ErrNotExist. Probe both edges after every failure.
		applied, reconcileErr := w.reconcileMissingMoveSource(ctx, backend, op, record)
		if reconcileErr != nil {
			return reconcileErr
		}
		if applied {
			return w.finishMoveConfirmation(ctx, backend, op, record.Kind)
		}
		return err
	}
	if err := w.markMoveApplied(op.Seq); err != nil {
		return err
	}
	return w.finishMoveConfirmation(ctx, backend, op, record.Kind)
}

func (w *Worker) executeLocalOnlyMove(ctx context.Context, backend Backend, op Op, record Inode) error {
	if record.Kind == KindDirectory {
		if err := backend.CreateDirectory(
			ctx, w.service.store.namespace.Bucket, parentPrefix(op.MoveTarget), filepath.Base(op.MoveTarget),
		); err != nil && !strings.Contains(strings.ToLower(err.Error()), "exists") {
			return err
		}
	} else {
		_, ref, err := w.service.pendingWrite(op.InodeID, op.ContentGeneration)
		if err != nil {
			return err
		}
		localPath, err := w.service.spliceChunks(ref.Chunks, fmt.Sprintf("%d", op.Seq))
		if err != nil {
			return err
		}
		defer os.Remove(localPath)
		taskID := physicalTaskID(w.service.store.namespace.ID, op.Seq)
		s3ops.SetTransferProfile(taskID, w.service.store.namespace.Config.ProfileID)
		if err := backend.UploadFile(
			ctx, w.service.store.namespace.Bucket, op.MoveTarget, localPath, taskID,
		); err != nil {
			return err
		}
	}
	if err := w.markMoveApplied(op.Seq); err != nil {
		return err
	}
	return w.finishMoveConfirmation(ctx, backend, op, record.Kind)
}

// snapshotMove makes the provider source and target durable before the first
// side effect. Later Desired renames must not redirect a confirmation retry.
func (w *Worker) snapshotMove(op Op, record Inode) (Op, error) {
	if op.MoveTarget != "" && op.MoveParent != 0 && op.MoveName != "" {
		return op, nil
	}
	parent, name := op.NewParent, op.NewName
	if parent == 0 || strings.TrimSpace(name) == "" {
		parent, name = record.DesiredParentID, record.DesiredName
	}
	target, err := w.service.remotePathLocked(parent, name)
	if err != nil {
		return Op{}, err
	}
	source := op.MoveSource
	if source == "" && record.RemoteParentID != 0 {
		source = record.RemoteName
	}
	var snapshot Op
	err = w.service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, op.Seq, func(current *Op) {
			if current.State != OpStateRunning {
				return
			}
			if current.MoveTarget == "" || current.MoveParent == 0 || current.MoveName == "" {
				current.MoveSource = source
				current.MoveTarget = target
				current.MoveParent = parent
				current.MoveName = name
			}
			snapshot = *current
		})
	})
	if err != nil {
		return Op{}, err
	}
	if snapshot.State != OpStateRunning {
		return Op{}, fmt.Errorf("metadata: move op %d is no longer running", op.Seq)
	}
	return snapshot, nil
}

func (w *Worker) finishMoveConfirmation(ctx context.Context, backend Backend, op Op, kind Kind) error {
	verifyCtx, cancel := verificationContext(ctx)
	defer cancel()
	if err := w.confirmMoveTarget(verifyCtx, backend, op, kind); err != nil {
		return err
	}
	if op.MoveSource != "" || kind == KindDirectory || op.ContentGeneration == 0 {
		return nil
	}
	return w.service.retireContent(op.InodeID, op.ContentGeneration)
}

// confirmMoveTarget verifies a move more strictly than mkdir confirmation:
// an absent directory marker is accepted only when the target subtree exists.
func (w *Worker) confirmMoveTarget(ctx context.Context, backend Backend, op Op, kind Kind) error {
	info, err := backend.HeadObject(ctx, w.service.store.namespace.Bucket, RemoteKey(op.MoveTarget))
	if err == nil {
		return w.service.commitConfirmation(
			op.InodeID, op.Seq, op.MoveParent, op.MoveName, Fingerprint(info), info.LastModified,
		)
	}
	if !errors.Is(err, os.ErrNotExist) || kind != KindDirectory {
		return err
	}
	exists, listErr := w.directoryTargetExists(ctx, backend, op.MoveTarget)
	if listErr != nil {
		return listErr
	}
	if !exists {
		return fmt.Errorf("%w: moved directory target %q is missing", errConflict, op.MoveTarget)
	}
	return w.service.commitConfirmation(op.InodeID, op.Seq, op.MoveParent, op.MoveName, "", "")
}

func (w *Worker) directoryTargetExists(ctx context.Context, backend Backend, target string) (bool, error) {
	prefix := strings.Trim(strings.TrimSpace(target), "/")
	if prefix != "" {
		prefix += "/"
	}
	page, err := backend.ListObjectsPage(ctx, w.service.store.namespace.Bucket, prefix, "", 1)
	if err != nil {
		return false, err
	}
	if len(page.Items) != 0 {
		return true, nil
	}
	_, exists, err := w.directoryTargetMarker(ctx, backend, target)
	return exists, err
}

func (w *Worker) directoryTargetMarker(
	ctx context.Context, backend Backend, target string,
) (storageops.ObjectInfo, bool, error) {
	parent := parentPrefix(target)
	items, err := listProviderChildrenImpl(
		ctx, backend, w.service.store.namespace.Bucket, rootInode,
		func(uint64) (string, error) { return parent, nil },
	)
	if err != nil {
		return storageops.ObjectInfo{}, false, err
	}
	wanted := filepath.Base(strings.Trim(strings.TrimSpace(target), "/"))
	for _, item := range items {
		name, isDir, err := splitListedChild(parent, item.Key)
		if err == nil && isDir && name == wanted {
			return item, true, nil
		}
	}
	return storageops.ObjectInfo{}, false, nil
}

// markMoveApplied records the remote side-effect before confirmation can fail.
func (w *Worker) markMoveApplied(seq uint64) error {
	return w.service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, seq, func(current *Op) {
			if current.State == OpStateRunning {
				current.MoveApplied = true
			}
		})
	})
}

// reconcileMissingMoveSource covers a crash after a provider accepted a move
// but before moveApplied reached bbolt. It only accepts a matching target.
func (w *Worker) reconcileMissingMoveSource(
	ctx context.Context, backend Backend, op Op, record Inode,
) (bool, error) {
	if _, err := backend.HeadObject(ctx, w.service.store.namespace.Bucket, RemoteKey(op.MoveSource)); err == nil {
		return false, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	info, err := backend.HeadObject(ctx, w.service.store.namespace.Bucket, RemoteKey(op.MoveTarget))
	if err == nil {
		expected := strings.TrimSpace(record.RemoteFingerprint)
		if expected == "" || Fingerprint(info) != expected {
			return false, fmt.Errorf(
				"%w: move source %q is missing and target %q fingerprint differs",
				errConflict, op.MoveSource, op.MoveTarget,
			)
		}
		if err := w.markMoveApplied(op.Seq); err != nil {
			return false, err
		}
		return true, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if record.Kind != KindDirectory {
		return false, nil
	}
	marker, exists, markerErr := w.directoryTargetMarker(ctx, backend, op.MoveTarget)
	if markerErr != nil || !exists {
		return false, nil
	}
	expected := strings.TrimSpace(record.RemoteFingerprint)
	if expected == "" || Fingerprint(marker) != expected {
		return false, fmt.Errorf(
			"%w: move source %q is missing and target %q marker fingerprint differs",
			errConflict, op.MoveSource, op.MoveTarget,
		)
	}
	if err := w.markMoveApplied(op.Seq); err != nil {
		return false, err
	}
	return true, nil
}
