// Cancellation and verification reconciliation probes provider state before
// changing durable local intent; it never blindly replays a side effect.
package metadata

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
)

func (w *Worker) reconcile(ctx context.Context, op Op) {
	var err error
	if op.CancelRequested || op.State == OpStateCancelRequested || op.State == OpStateReconciling {
		err = w.reconcileCanceled(ctx, op)
	} else {
		err = w.reconcileVerification(ctx, op)
	}
	if err == nil {
		return
	}
	_ = w.service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, op.Seq, func(current *Op) {
			if !opStateNeedsReconciliation(current.State) {
				return
			}
			if errors.Is(err, errConflict) {
				current.State = OpStateFailed
				current.LastError = err.Error()
				_ = markInodeConflict(tx, current.InodeID)
				return
			}
			current.Retry++
			current.NextAttemptUnixNano = time.Now().Add(retryDelay(current.Retry)).UnixNano()
			if current.CancelRequested || current.State == OpStateCancelRequested || current.State == OpStateReconciling {
				current.State = OpStateReconciling
			} else {
				current.State = OpStateVerifying
			}
			current.LastError = err.Error()
		})
	})
}

func (w *Worker) reconcileVerification(ctx context.Context, op Op) error {
	s := w.service
	backend := s.backendSnapshot()
	verifyCtx, cancel := verificationContext(ctx)
	defer cancel()
	var err error
	switch op.Type {
	case OpMkdir:
		err = s.confirmRemote(verifyCtx, backend, op, op.NewParent, op.NewName, false)
	case OpWrite:
		_, ref, refErr := s.pendingWrite(op.InodeID, op.ContentGeneration)
		if refErr != nil {
			return refErr
		}
		_, parent, name, targetErr := s.writeRemoteTarget(op)
		if targetErr != nil {
			return targetErr
		}
		err = s.confirmRemote(verifyCtx, backend, op, parent, name, true)
		if err == nil {
			err = s.retireContent(op.InodeID, ref.Generation)
		}
	case OpRename:
		if op.MoveTarget == "" || op.MoveParent == 0 || op.MoveName == "" {
			return fmt.Errorf("metadata: move op %d lacks a frozen reconciliation target", op.Seq)
		}
		record, recordErr := s.remoteTarget(op.InodeID)
		if recordErr != nil {
			return recordErr
		}
		err = w.finishMoveConfirmation(verifyCtx, backend, op, record.Kind)
	case OpDelete:
		err = w.reconcileDeleteVerification(verifyCtx, op)
	default:
		return fmt.Errorf("metadata: unknown reconciliation op %d", op.Type)
	}
	if err != nil {
		return err
	}
	return s.store.update(func(tx boltTxT) error {
		return replaceOp(tx, op.Seq, func(current *Op) {
			if current.State == OpStateVerifying {
				current.State = OpStateApplied
				current.AppliedAtUnixNano = time.Now().UnixNano()
				current.LastError = ""
			}
		})
	})
}

func (w *Worker) reconcileDeleteVerification(ctx context.Context, op Op) error {
	record, err := w.service.remoteTarget(op.InodeID)
	if err != nil {
		return err
	}
	if record.RemoteParentID != 0 {
		_, headErr := w.service.backendSnapshot().HeadObject(
			ctx, w.service.store.namespace.Bucket, RemoteKey(record.RemoteName),
		)
		if headErr == nil {
			return fmt.Errorf("%w: delete target still exists", errConflict)
		}
		if !errors.Is(headErr, os.ErrNotExist) {
			return headErr
		}
	}
	descendants, err := w.service.collectSubtreeInodes(op.InodeID)
	if err != nil {
		return err
	}
	if err := w.service.deleteInodeRecord(op.InodeID); err != nil {
		return err
	}
	return w.service.purgeInodeRecords(descendants)
}

func (w *Worker) reconcileCanceled(ctx context.Context, op Op) error {
	s := w.service
	backend := s.backendSnapshot()
	record, err := s.remoteTarget(op.InodeID)
	if err != nil && !errors.Is(err, ErrNotFound) {
		return err
	}
	target, source, isDirectory, err := w.cancelTargets(op, record)
	if err != nil {
		return err
	}
	present, err := remoteObjectPresent(ctx, backend, s.store.namespace.Bucket, target, isDirectory)
	if err != nil {
		return err
	}
	if present {
		switch op.Type {
		case OpMkdir:
			err = backend.DeleteObject(ctx, s.store.namespace.Bucket, target, true, physicalTaskID(s.NamespaceID(), op.Seq))
		case OpRename:
			if strings.TrimSpace(source) == "" {
				return fmt.Errorf("%w: canceled move has no source target", errConflict)
			}
			err = backend.MoveObject(ctx, s.store.namespace.Bucket, target, source, isDirectory, physicalTaskID(s.NamespaceID(), op.Seq))
		case OpWrite:
			// Deleting an overwritten remote file would destroy data. It is only
			// safe to compensate a write that had no confirmed remote predecessor.
			if record.RemoteParentID != 0 || strings.TrimSpace(op.ExpectedRemoteFingerprint) != "" {
				return fmt.Errorf("%w: canceled write may have overwritten remote content", errConflict)
			}
			err = backend.DeleteObject(ctx, s.store.namespace.Bucket, target, false, physicalTaskID(s.NamespaceID(), op.Seq))
		case OpDelete:
			// The object is still present, so provider deletion never took effect.
			err = nil
		default:
			return fmt.Errorf("metadata: unknown canceled op %d", op.Type)
		}
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	} else {
		switch op.Type {
		case OpDelete:
			return fmt.Errorf("%w: canceled delete target is already absent", errConflict)
		case OpRename:
			if strings.TrimSpace(source) == "" {
				return fmt.Errorf("%w: canceled move has no source target", errConflict)
			}
			sourcePresent, sourceErr := remoteObjectPresent(ctx, backend, s.store.namespace.Bucket, source, isDirectory)
			if sourceErr != nil {
				return sourceErr
			}
			if !sourcePresent {
				return fmt.Errorf("%w: canceled move has neither frozen edge", errConflict)
			}
		case OpWrite:
			if record.RemoteParentID != 0 {
				return fmt.Errorf("%w: canceled write target is absent", errConflict)
			}
		}
	}
	return w.finalizeCanceled(op.Seq)
}

func (w *Worker) cancelTargets(op Op, record Inode) (target, source string, isDirectory bool, err error) {
	isDirectory = record.Kind == KindDirectory
	switch op.Type {
	case OpMkdir:
		target, err = w.service.remotePathLocked(op.NewParent, op.NewName)
	case OpWrite:
		target, _, _, err = w.service.writeRemoteTarget(op)
	case OpRename:
		target, source = op.MoveTarget, op.MoveSource
		if target == "" {
			target, err = w.service.remotePathLocked(op.NewParent, op.NewName)
		}
	case OpDelete:
		target = record.RemoteName
		if target == "" {
			target, err = w.service.Path(op.InodeID)
		}
	default:
		err = fmt.Errorf("metadata: unknown canceled op %d", op.Type)
	}
	return target, source, isDirectory, err
}

func remoteObjectPresent(ctx context.Context, backend Backend, bucket, target string, directory bool) (bool, error) {
	if strings.TrimSpace(target) == "" {
		return false, nil
	}
	_, err := backend.HeadObject(ctx, bucket, RemoteKey(target))
	if err == nil {
		return true, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return false, err
	}
	if !directory {
		return false, nil
	}
	prefix := strings.Trim(strings.TrimSpace(target), "/")
	if prefix != "" {
		prefix += "/"
	}
	page, listErr := backend.ListObjectsPage(ctx, bucket, prefix, "", 1)
	if listErr != nil {
		return false, listErr
	}
	return len(page.Items) > 0, nil
}

func (w *Worker) finalizeCanceled(seq uint64) error {
	s := w.service
	s.chunkMu.Lock()
	var removed []string
	err := s.store.update(func(tx boltTxT) error {
		op, err := getOp(tx, seq)
		if err != nil {
			return err
		}
		if !opStateNeedsReconciliation(op.State) {
			return nil
		}
		removed, err = s.rollbackPendingTask(tx, []Op{op})
		if err != nil {
			return err
		}
		previous := op
		op.State = OpStateCanceled
		op.CanceledAtUnixNano = time.Now().UnixNano()
		op.CancelRequested = false
		op.LastError = ""
		return putOp(tx, op, previous)
	})
	if err == nil {
		s.removeChunkFiles(removed)
		s.syncChunkProtectionBestEffortLocked()
	}
	s.chunkMu.Unlock()
	return err
}
