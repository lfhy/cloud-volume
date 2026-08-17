// The remote worker drains journal operations after the local quiet period.
package metadata

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	s3ops "remote-storage/go/s3"
)

const (
	workerRetryBase = 15 * time.Second
	workerRetryMax  = 2 * time.Minute
	workerPoll      = 250 * time.Millisecond
)

// Worker executes pending journal operations against one backend.
type Worker struct {
	service *Service
	mu      sync.Mutex
	wake    chan struct{}
	stop    chan struct{}
	done    chan struct{}
	running map[uint64]struct{}
}

// NewWorker starts one drain goroutine for a metadata service.
func NewWorker(service *Service) *Worker {
	w := &Worker{
		service: service,
		wake:    make(chan struct{}, 1),
		stop:    make(chan struct{}),
		done:    make(chan struct{}),
		running: map[uint64]struct{}{},
	}
	go w.run()
	return w
}

// Wake asks the worker to inspect due operations immediately.
func (w *Worker) Wake() {
	select {
	case w.wake <- struct{}{}:
	default:
	}
}

// Stop terminates the loop and waits for the current operation to return.
func (w *Worker) Stop() {
	close(w.stop)
	<-w.done
}

// Drain blocks until no due operations remain, the timeout expires, or a
// permanent failure is encountered. Pending future operations are retained.
func (w *Worker) Drain(ctx context.Context) error {
	deadline := time.Now().Add(30 * time.Second)
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		pending, failed, running, next := w.snapshotWork()
		if pending == 0 && failed == 0 {
			return nil
		}
		if failed > 0 {
			return fmt.Errorf("metadata worker: %d failed operations", failed)
		}
		if running == 0 && !next.IsZero() && next.After(time.Now()) && time.Now().Before(deadline) {
			w.sleepUntil(minTime(next, deadline))
			continue
		}
		before := pending
		w.runDueOnce(ctx)
		pending, failed, running, _ = w.snapshotWork()
		if failed > 0 {
			return fmt.Errorf("metadata worker: %d failed operations", failed)
		}
		if pending == 0 {
			return nil
		}
		// Stop when a pass made no progress; otherwise a repeatedly deferred
		// retry would turn Drain into a busy loop until its deadline.
		if pending >= before && running == 0 {
			return context.DeadlineExceeded
		}
		if time.Now().After(deadline) {
			return context.DeadlineExceeded
		}
		if running > 0 {
			w.sleepUntil(minTime(time.Now().Add(workerPoll), deadline))
			continue
		}
	}
}

func (w *Worker) run() {
	defer close(w.done)
	for {
		select {
		case <-w.stop:
			return
		case <-w.wake:
			w.runDueOnce(context.Background())
		case <-time.After(workerPoll):
			w.runDueOnce(context.Background())
		}
	}
}

func (w *Worker) sleepUntil(when time.Time) {
	delay := time.Until(when)
	if delay <= 0 {
		return
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-w.stop:
	case <-timer.C:
	}
}

func (w *Worker) snapshotWork() (pending int, failed int, running int, next time.Time) {
	_ = w.service.store.view(func(tx boltTxT) error {
		now := time.Now().UnixNano()
		journal := tx.Bucket([]byte(bucketJournal))
		_ = journal.ForEach(func(_, value []byte) error {
			var op Op
			if decodeJSON(value, &op) != nil {
				return nil
			}
			switch op.State {
			case OpStateFailed:
				failed++
			case OpStateRunning:
				pending++
				running++
			case OpStatePending:
				pending++
				if op.NextAttemptUnixNano > now {
					nextTime := time.Unix(0, op.NextAttemptUnixNano)
					if next.IsZero() || nextTime.Before(next) {
						next = nextTime
					}
				}
			}
			return nil
		})
		return nil
	})
	return pending, failed, running, next
}

func (w *Worker) runDueOnce(ctx context.Context) {
	w.service.operationMu.RLock()
	defer w.service.operationMu.RUnlock()
	ops := w.claimDue()
	for _, op := range ops {
		w.execute(ctx, op)
	}
}

func (w *Worker) claimDue() []Op {
	w.mu.Lock()
	defer w.mu.Unlock()
	var claimed []Op
	_ = w.service.store.update(func(tx boltTxT) error {
		now := time.Now().UnixNano()
		journal := tx.Bucket([]byte(bucketJournal))
		ready := tx.Bucket([]byte(bucketReadyOps))
		cursor := ready.Cursor()
		for key, _ := cursor.First(); key != nil; key, _ = cursor.Next() {
			opState := OpState(key[0])
			attempt := int64(decodeUint64(key[1:9]))
			if opState == OpStateFailed || attempt > now {
				continue
			}
			var op Op
			if err := decodeJSON(journal.Get(key[9:]), &op); err != nil {
				continue
			}
			if _, busy := w.running[op.InodeID]; busy {
				continue
			}
			// Dependency ordering: a write/mkdir must wait for an unfinished
			// parent mkdir/rename, and any op must wait for a pending delete of
			// its own inode recorded earlier in the journal. Running is a
			// transient in-process state; a process restart recovers ops that
			// crashed mid-execution back into the pending queue.
			if op.State == OpStateRunning {
				previous := op
				op.State = OpStatePending
				op.NextAttemptUnixNano = now
				if err := putOp(tx, op, previous); err != nil {
					return err
				}
				continue
			}
			if blocked, _ := w.blocked(tx, op); blocked {
				continue
			}
			w.running[op.InodeID] = struct{}{}
			previous := op
			op.State = OpStateRunning
			if err := putOp(tx, op, previous); err != nil {
				return err
			}
			claimed = append(claimed, op)
		}
		return nil
	})
	return claimed
}

// blocked reports whether one op must wait on an earlier unfinished journal
// operation. Failed operations do not block later work, but every pending or
// running operation on the same inode remains an ordering barrier.
func (w *Worker) blocked(tx boltTxT, op Op) (bool, string) {
	if pendingOpForInode(tx, op.InodeID, op.Seq) {
		return true, "earlier operation on inode pending"
	}
	if op.Type == OpRename || op.Type == OpDelete {
		return false, ""
	}
	parent, err := getInode(tx, op.InodeID)
	if err != nil {
		return false, ""
	}
	for _, ancestor := range []uint64{parent.DesiredParentID} {
		if ancestor == rootInode || ancestor == 0 {
			continue
		}
		if pendingOpForInode(tx, ancestor, op.Seq) {
			return true, "parent mkdir/rename pending"
		}
	}
	return false, ""
}

func pendingOpForInode(tx boltTxT, inode, beforeSeq uint64) bool {
	found := false
	_ = tx.Bucket([]byte(bucketInodeOps)).ForEach(func(key, _ []byte) error {
		seq := decodeUint64(key[8:])
		if seq >= beforeSeq {
			return nil
		}
		raw := tx.Bucket([]byte(bucketJournal)).Get(encodeUint64(seq))
		if raw == nil {
			return nil
		}
		var prior Op
		if decodeJSON(raw, &prior) != nil {
			return nil
		}
		if prior.InodeID != inode {
			return nil
		}
		if prior.State == OpStatePending || prior.State == OpStateRunning {
			found = true
		}
		return nil
	})
	return found
}

func (w *Worker) releaseInode(inode uint64) {
	w.mu.Lock()
	delete(w.running, inode)
	w.mu.Unlock()
	w.Wake()
}

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
		record, ref, err := s.pendingWrite(op.InodeID, op.ContentGeneration)
		if err != nil {
			return err
		}
		target := s.desiredRemoteTarget(record)
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
		if err := s.confirmRemote(ctx, backend, op, record.DesiredParentID, record.DesiredName, true); err != nil {
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
			// Wait for queued descendant ops first: purging their staged
			// content would orphan them into endless retries.
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
		// Directory deletes must purge descendants too; otherwise their inode
		// records and staged content leak forever while Status().InodeCount
		// drifts upward.
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
		// Local-only object: materialize at the desired path directly.
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

func minTime(left, right time.Time) time.Time {
	if left.Before(right) {
		return left
	}
	return right
}
