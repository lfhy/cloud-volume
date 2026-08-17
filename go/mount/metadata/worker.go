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
		pending, failed, next := w.snapshotWork()
		if pending == 0 && failed == 0 {
			return nil
		}
		if !next.IsZero() && next.After(time.Now()) && time.Now().Before(deadline) {
			w.sleepUntil(minTime(next, deadline))
			continue
		}
		w.runDueOnce(ctx)
		if pending, failed, _ = w.snapshotWork(); pending > 0 && failed == 0 {
			continue
		}
		if failed > 0 {
			return fmt.Errorf("metadata worker: %d failed operations", failed)
		}
		if time.Now().After(deadline) {
			return context.DeadlineExceeded
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

func (w *Worker) snapshotWork() (pending int, failed int, next time.Time) {
	_ = w.service.store.view(func(tx boltTxT) error {
		now := time.Now().UnixNano()
		ready := tx.Bucket([]byte(bucketReadyOps))
		_ = ready.ForEach(func(key, _ []byte) error {
			opState := OpState(key[0])
			attempt := int64(decodeUint64(key[1:9]))
			if opState == OpStateFailed {
				failed++
				return nil
			}
			if attempt > now {
				nextTime := time.Unix(0, attempt)
				if next.IsZero() || nextTime.Before(next) {
					next = nextTime
				}
			}
			pending++
			return nil
		})
		return nil
	})
	return pending, failed, next
}

func (w *Worker) runDueOnce(ctx context.Context) {
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
			if err := decodeJSON(journal.Get(key[17:]), &op); err != nil {
				continue
			}
			if _, busy := w.running[op.InodeID]; busy {
				continue
			}
			w.running[op.InodeID] = struct{}{}
			op.State = OpStateRunning
			_ = putOp(tx, op)
			claimed = append(claimed, op)
		}
		return nil
	})
	return claimed
}

func (w *Worker) releaseInode(inode uint64) {
	w.mu.Lock()
	delete(w.running, inode)
	w.mu.Unlock()
	w.Wake()
}

func (w *Worker) execute(ctx context.Context, op Op) {
	err := w.executeOp(ctx, op)
	_ = w.service.store.update(func(tx boltTxT) error {
		current, getErr := getOp(tx, op.Seq)
		if getErr != nil {
			return nil
		}
		if current.State == OpStateRunning || errors.Is(err, errConflict) {
			if err != nil {
				current.LastError = err.Error()
			}
			if errors.Is(err, errConflict) {
				current.State = OpStateFailed
				_ = markInodeConflict(tx, op.InodeID)
			} else {
				current.Retry++
				current.State = OpStatePending
				current.NextAttemptUnixNano = time.Now().Add(retryDelay(current.Retry)).UnixNano()
				_ = putOp(tx, current)
			}
			if current.State == OpStateFailed {
				_ = putOp(tx, current)
			}
			return nil
		}
		if err != nil {
			current.LastError = err.Error()
			current.Retry++
			current.State = OpStatePending
			current.NextAttemptUnixNano = time.Now().Add(retryDelay(current.Retry)).UnixNano()
			return putOp(tx, current)
		}
		current.State = OpStateApplied
		current.AppliedAtUnixNano = time.Now().UnixNano()
		current.LastError = ""
		return putOp(tx, current)
	})
	w.releaseInode(op.InodeID)
	if err != nil && !errors.Is(err, errConflict) {
		log.Printf("[metadata/worker] op=%d type=%d retry pending error=%v", op.Seq, op.Type, err)
	}
}

func (w *Worker) executeOp(ctx context.Context, op Op) error {
	s := w.service
	switch op.Type {
	case OpMkdir:
		path, parentID, name, err := s.desiredDirTarget(op.InodeID)
		if err != nil {
			return err
		}
		if err := s.backend.CreateDirectory(ctx, s.store.namespace.Bucket, filepath.ToSlash(filepath.Dir(path+"/")), name); err != nil && !strings.Contains(strings.ToLower(err.Error()), "exists") {
			return err
		}
		return s.confirmRemote(ctx, op.InodeID, parentID, name, false)
	case OpWrite:
		record, ref, err := s.pendingWrite(op.InodeID)
		if err != nil {
			return err
		}
		target := s.desiredRemoteTarget(record)
		taskID := fmt.Sprintf("metadata-op-%d", op.Seq)
		s3ops.QueueTransfer(taskID, "upload", s.store.namespace.Bucket, target, ref.LocalPath, ref.Size)
		s3ops.SetTransferStatusDetail(taskID, "sync_wait")
		if err := s.backend.UploadFile(ctx, s.store.namespace.Bucket, target, ref.LocalPath, taskID); err != nil {
			s3ops.FinishQueuedTransfer(taskID, err)
			return err
		}
		if err := s.confirmRemote(ctx, op.InodeID, record.DesiredParentID, record.DesiredName, true); err != nil {
			s3ops.FinishQueuedTransfer(taskID, err)
			return err
		}
		s3ops.FinishQueuedTransfer(taskID, nil)
		return s.retireContent(op.InodeID, ref.Generation)
	case OpRename:
		return w.executeMove(ctx, op)
	case OpDelete:
		record, err := s.remoteTarget(op.InodeID)
		if err != nil {
			return err
		}
		if record.RemoteParentID == 0 {
			_ = s.deleteInodeRecord(op.InodeID)
			return nil
		}
		if err := s.backend.DeleteObject(ctx, s.store.namespace.Bucket, record.RemoteName, record.Kind == KindDirectory, fmt.Sprintf("metadata-op-%d", op.Seq)); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		return s.deleteInodeRecord(op.InodeID)
	default:
		return fmt.Errorf("metadata worker: unknown op type %d", op.Type)
	}
}

func (w *Worker) executeMove(ctx context.Context, op Op) error {
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
			if err := w.service.backend.CreateDirectory(ctx, w.service.store.namespace.Bucket, filepath.ToSlash(filepath.Dir(desiredPath+"/")), filepath.Base(desiredPath)); err != nil {
				return err
			}
			return w.service.confirmRemote(ctx, op.InodeID, record.DesiredParentID, record.DesiredName, false)
		}
		_, ref, refErr := w.service.pendingWrite(op.InodeID)
		if refErr != nil {
			return refErr
		}
		taskID := fmt.Sprintf("metadata-op-%d", op.Seq)
		if err := w.service.backend.UploadFile(ctx, w.service.store.namespace.Bucket, desiredPath, ref.LocalPath, taskID); err != nil {
			return err
		}
		if err := w.service.confirmRemote(ctx, op.InodeID, record.DesiredParentID, record.DesiredName, true); err != nil {
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
		return w.service.confirmRemote(ctx, op.InodeID, record.DesiredParentID, record.DesiredName, record.Kind == KindDirectory)
	}
	taskID := fmt.Sprintf("metadata-op-%d", op.Seq)
	if err := w.service.backend.MoveObject(ctx, w.service.store.namespace.Bucket, source, target, record.Kind == KindDirectory, taskID); err != nil {
		return err
	}
	return w.service.confirmRemote(ctx, op.InodeID, record.DesiredParentID, record.DesiredName, record.Kind == KindDirectory)
}

var errConflict = errors.New("metadata: remote fingerprint conflict")

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
