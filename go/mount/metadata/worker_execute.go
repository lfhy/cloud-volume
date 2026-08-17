// Worker execution applies journal snapshots to the provider and confirms them.
package metadata

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	s3ops "remote-storage/go/s3"
)

func (w *Worker) execute(ctx context.Context, op Op) {
	err := w.executeOp(ctx, op)
	updateErr := w.service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, op.Seq, func(current *Op) {
			if current.State != OpStateRunning {
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
		return s.confirmRemote(ctx, backend, op, parentID, name, false)
	case OpWrite:
		_, ref, err := s.pendingWrite(op.InodeID, op.ContentGeneration)
		if err != nil {
			return err
		}
		target, parentID, name, err := s.writeRemoteTarget(op)
		if err != nil {
			return err
		}
		if err := s.verifyExpectedRemote(ctx, backend, op, target); err != nil {
			return err
		}
		taskID := fmt.Sprintf("metadata-op-%d", op.Seq)
		localPath, err := s.spliceChunks(ref.Chunks, fmt.Sprintf("%d", op.Seq))
		if err != nil {
			return err
		}
		defer os.Remove(localPath)
		s3ops.QueueTransfer(taskID, "upload", s.store.namespace.Bucket, target, localPath, ref.Size)
		s3ops.SetTransferStatusDetail(taskID, "sync_wait")
		if err := backend.UploadFile(ctx, s.store.namespace.Bucket, target, localPath, taskID); err != nil {
			s3ops.FinishQueuedTransfer(taskID, err)
			return err
		}
		if err := s.confirmRemote(ctx, backend, op, parentID, name, true); err != nil {
			s3ops.FinishQueuedTransfer(taskID, err)
			return err
		}
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
			if err := backend.DeleteObject(ctx, s.store.namespace.Bucket, record.RemoteName, record.Kind == KindDirectory, fmt.Sprintf("metadata-op-%d", op.Seq)); err != nil && !errors.Is(err, os.ErrNotExist) {
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

func (w *Worker) executeMove(ctx context.Context, op Op, backend Backend) error {
	record, err := w.service.remoteTarget(op.InodeID)
	if err != nil {
		return err
	}
	if record.RemoteParentID == 0 {
		// A local-only rename materializes the final Desired location directly.
		desiredPath, err := w.service.Path(op.InodeID)
		if err != nil {
			return err
		}
		if record.Kind == KindDirectory {
			if err := backend.CreateDirectory(ctx, w.service.store.namespace.Bucket, parentPrefix(desiredPath), filepath.Base(desiredPath)); err != nil {
				return err
			}
			return w.service.confirmRemote(ctx, backend, op, record.DesiredParentID, record.DesiredName, false)
		}
		_, ref, refErr := w.service.pendingWrite(op.InodeID, op.ContentGeneration)
		if refErr != nil {
			return refErr
		}
		taskID := fmt.Sprintf("metadata-op-%d", op.Seq)
		localPath, err := w.service.spliceChunks(ref.Chunks, fmt.Sprintf("%d", op.Seq))
		if err != nil {
			return err
		}
		defer os.Remove(localPath)
		if err := backend.UploadFile(ctx, w.service.store.namespace.Bucket, desiredPath, localPath, taskID); err != nil {
			return err
		}
		if err := w.service.confirmRemote(ctx, backend, op, record.DesiredParentID, record.DesiredName, true); err != nil {
			return err
		}
		return w.service.retireContent(op.InodeID, ref.Generation)
	}
	source := record.RemoteName
	target, err := w.service.desiredPath(op.InodeID)
	if err != nil {
		return err
	}
	if source == target {
		return w.service.confirmRemote(ctx, backend, op, record.DesiredParentID, record.DesiredName, record.Kind == KindDirectory)
	}
	taskID := fmt.Sprintf("metadata-op-%d", op.Seq)
	if err := backend.MoveObject(ctx, w.service.store.namespace.Bucket, source, target, record.Kind == KindDirectory, taskID); err != nil {
		return err
	}
	return w.service.confirmRemote(ctx, backend, op, record.DesiredParentID, record.DesiredName, record.Kind == KindDirectory)
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
