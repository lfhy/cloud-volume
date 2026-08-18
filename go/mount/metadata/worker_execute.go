// Worker execution applies journal snapshots to the provider and confirms them.
package metadata

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	s3ops "remote-storage/go/s3"
)

func (w *Worker) execute(ctx context.Context, op Op) {
	opCtx, done, _ := w.beginOperation(ctx, op.Seq)
	defer done()
	if opStateNeedsReconciliation(op.State) {
		w.reconcile(opCtx, op)
		w.releaseInode(op.InodeID)
		return
	}
	if !w.operationMayExecute(op.Seq) {
		_ = w.markReconciliationIfCanceled(op.Seq)
		w.releaseInode(op.InodeID)
		return
	}
	err := w.executeOp(opCtx, op)
	updateErr := w.service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, op.Seq, func(current *Op) {
			if current.State == OpStateCancelRequested || current.State == OpStateReconciling {
				current.State = OpStateReconciling
				current.LastError = "cancel requested; remote outcome requires reconciliation"
				if current.ReconcileAtUnixNano == 0 {
					current.ReconcileAtUnixNano = time.Now().UnixNano()
				}
				return
			}
			if current.State != OpStateRunning && current.State != OpStateVerifying {
				return
			}
			switch {
			case err == nil:
				current.State = OpStateApplied
				current.AppliedAtUnixNano = time.Now().UnixNano()
				current.LastError = ""
			case errors.Is(err, errConflict):
				current.State = OpStateFailed
				current.LastError = err.Error()
				_ = markInodeConflict(tx, op.InodeID)
			default:
				current.Retry++
				current.State = OpStatePending
				current.LastError = err.Error()
				current.NextAttemptUnixNano = time.Now().Add(retryDelay(current.Retry)).UnixNano()
			}
		})
	})
	w.releaseInode(op.InodeID)
	if updateErr != nil {
		log.Printf("[metadata/worker] op=%d state update error=%v", op.Seq, updateErr)
	}
	if err != nil && !errors.Is(err, errConflict) {
		log.Printf("[metadata/worker] op=%d type=%d retry pending error=%v", op.Seq, op.Type, err)
	}
}

func (w *Worker) markReconciliationIfCanceled(seq uint64) error {
	return w.service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, seq, func(current *Op) {
			if current.State == OpStateCancelRequested {
				current.State = OpStateReconciling
				if current.ReconcileAtUnixNano == 0 {
					current.ReconcileAtUnixNano = time.Now().UnixNano()
				}
			}
		})
	})
}

// operationMayExecute closes the claim-to-context race: a cancel request that
// arrives before provider I/O leaves the durable record reconciling and stops
// this worker from starting a side effect without a cancellable context.
func (w *Worker) operationMayExecute(seq uint64) bool {
	mayExecute := false
	_ = w.service.store.view(func(tx boltTxT) error {
		op, err := getOp(tx, seq)
		mayExecute = err == nil && op.State == OpStateRunning
		return nil
	})
	return mayExecute
}

func (w *Worker) executeOp(ctx context.Context, op Op) error {
	s := w.service
	backend := s.backendSnapshot()
	switch op.Type {
	case OpMkdir:
		path, parentID, name, err := s.desiredDirTarget(op.InodeID)
		if err != nil {
			return err
		}
		if err := backend.CreateDirectory(ctx, s.store.namespace.Bucket, parentPrefix(path), name); err != nil && !strings.Contains(strings.ToLower(err.Error()), "exists") {
			return err
		}
		if err := w.markVerifying(op.Seq); err != nil {
			return err
		}
		verifyCtx, cancel := verificationContext(ctx)
		defer cancel()
		return s.confirmRemote(verifyCtx, backend, op, parentID, name, false)
	case OpWrite:
		_, ref, err := s.pendingWrite(op.InodeID, op.ContentGeneration)
		if err != nil {
			return err
		}
		target, parentID, name, err := s.writeRemoteTarget(op)
		if err != nil {
			return err
		}
		verifyCtx, cancelVerify := verificationContext(ctx)
		if err := s.verifyExpectedRemote(verifyCtx, backend, op, target); err != nil {
			cancelVerify()
			return err
		}
		cancelVerify()
		taskID := physicalTaskID(s.store.namespace.ID, op.Seq)
		localPath, err := s.spliceChunks(ref.Chunks, fmt.Sprintf("%d", op.Seq))
		if err != nil {
			return err
		}
		defer os.Remove(localPath)
		s3ops.QueueTransfer(taskID, "upload", s.store.namespace.Bucket, target, localPath, ref.Size)
		s3ops.SetTransferProfile(taskID, s.store.namespace.Config.ProfileID)
		s3ops.SetTransferStatusDetail(taskID, "sync_wait")
		if err := backend.UploadFile(ctx, s.store.namespace.Bucket, target, localPath, taskID); err != nil {
			s3ops.FinishQueuedTransfer(taskID, err)
			return err
		}
		if err := w.markVerifying(op.Seq); err != nil {
			s3ops.FinishQueuedTransfer(taskID, err)
			return err
		}
		verifyCtx, cancel := verificationContext(ctx)
		if err := s.confirmRemote(verifyCtx, backend, op, parentID, name, true); err != nil {
			cancel()
			s3ops.FinishQueuedTransfer(taskID, err)
			return err
		}
		cancel()
		s3ops.FinishQueuedTransfer(taskID, nil)
		return s.retireContent(op.InodeID, ref.Generation)
	case OpRename:
		return w.executeMove(ctx, op, backend)
	case OpDelete:
		record, err := s.remoteTarget(op.InodeID)
		if err != nil {
			return err
		}
		if record.Kind == KindDirectory {
			// A claimed delete can race an earlier descendant that was claimed by
			// another pass, so recheck before purging any staged content.
			var blocked bool
			_ = s.store.view(func(tx boltTxT) error {
				_, blocked = pendingDescendantOp(tx, op.InodeID, op.Seq)
				return nil
			})
			if blocked {
				return fmt.Errorf("metadata worker: delete op %d waiting for pending descendant op", op.Seq)
			}
		}
		if record.RemoteParentID != 0 {
			deleteObject := backend.DeleteObject
			if op.HardDelete {
				deleteObject = backend.DeleteObjectHard
			}
			taskID := physicalTaskID(s.store.namespace.ID, op.Seq)
			s3ops.SetTransferProfile(taskID, s.store.namespace.Config.ProfileID)
			if err := deleteObject(ctx, s.store.namespace.Bucket, record.RemoteName, record.Kind == KindDirectory, taskID); err != nil && !errors.Is(err, os.ErrNotExist) {
				return err
			}
		}
		descendants, err := s.collectSubtreeInodes(op.InodeID)
		if err != nil {
			return err
		}
		if err := s.deleteInodeRecord(op.InodeID); err != nil {
			return err
		}
		return s.purgeInodeRecords(descendants)
	default:
		return fmt.Errorf("metadata worker: unknown op type %d", op.Type)
	}
}

func (w *Worker) markVerifying(seq uint64) error {
	return w.service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, seq, func(current *Op) {
			if current.State == OpStateRunning {
				current.State = OpStateVerifying
			}
		})
	})
}

var errConflict = errors.New("metadata: remote fingerprint conflict")

// parentPrefix returns the slash-separated parent prefix for a provider key.
func parentPrefix(value string) string {
	trimmed := strings.Trim(strings.TrimSpace(value), "/")
	if trimmed == "" {
		return ""
	}
	if index := strings.LastIndex(trimmed, "/"); index >= 0 {
		return trimmed[:index]
	}
	return ""
}

func retryDelay(retry int) time.Duration {
	if retry <= 1 {
		return workerRetryBase
	}
	delay := workerRetryBase
	for index := 1; index < retry; index++ {
		delay *= 2
		if delay >= workerRetryMax {
			return workerRetryMax
		}
	}
	return delay
}
