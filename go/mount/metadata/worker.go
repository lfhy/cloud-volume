// Worker scheduling claims due journal operations and enforces their ordering.
package metadata

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"
)

const (
	workerRetryBase = 15 * time.Second
	workerRetryMax  = 2 * time.Minute
	workerPoll      = 250 * time.Millisecond
)

// Provider HEAD/list confirmation must not leave a journal operation in
// verifying forever when an endpoint accepts the upload but stops answering.
var workerVerificationTimeout = 45 * time.Second

// Worker executes pending journal operations against one backend.
type Worker struct {
	service   *Service
	mu        sync.Mutex
	executeMu sync.Mutex
	wake      chan struct{}
	stop      chan struct{}
	done      chan struct{}
	running   map[uint64]struct{}
	cancels   map[uint64]context.CancelFunc
}

// NewWorker starts one drain goroutine for a metadata service.
func NewWorker(service *Service) *Worker {
	w := &Worker{
		service: service,
		wake:    make(chan struct{}, 1),
		stop:    make(chan struct{}),
		done:    make(chan struct{}),
		running: map[uint64]struct{}{},
		cancels: map[uint64]context.CancelFunc{},
	}
	if err := w.recoverDurableStates(); err != nil {
		log.Printf("[metadata/worker] recover journal states: %v", err)
	}
	service.setWorker(w)
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
		pending, failed, running, due, next := w.snapshotWork()
		if pending == 0 && failed == 0 {
			return nil
		}
		if failed > 0 {
			return fmt.Errorf("metadata worker: %d failed operations", failed)
		}
		if running > 0 {
			// Another complete pass owns the provider call. Do not block on its
			// pass mutex here: Drain must continue polling its own context while
			// a background request is in flight.
			w.sleepUntil(minTime(time.Now().Add(workerPoll), deadline))
			continue
		}
		if !due && !next.IsZero() && next.After(time.Now()) && time.Now().Before(deadline) {
			w.sleepUntil(minTime(next, deadline))
			continue
		}
		before := pending
		if !w.tryRunDueOnceWithOptions(ctx, true) {
			// A background pass acquired the gate after the snapshot above. Keep
			// Drain cancelable rather than blocking behind its provider call.
			w.sleepUntil(minTime(time.Now().Add(workerPoll), deadline))
			continue
		}
		pending, failed, running, _, _ = w.snapshotWork()
		if failed > 0 {
			return fmt.Errorf("metadata worker: %d failed operations", failed)
		}
		if pending == 0 {
			return nil
		}
		// Stop when a pass made no progress; otherwise a repeatedly deferred
		// retry would turn Drain into a busy loop until its deadline.
		if pending >= before && running == 0 {
			// A due child can still be blocked behind a parent retry whose own
			// persisted deadline is in the future. After the forced pass proves
			// nothing is currently claimable, wait for that parent instead of
			// reporting a false drain timeout.
			_, _, _, due, next = w.snapshotWork()
			if due {
				// A prerequisite can become due between the forced claim pass and
				// this resnapshot. Give it a short turn before declaring the
				// dependent queue permanently stalled.
				w.sleepUntil(minTime(time.Now().Add(workerPoll), deadline))
				continue
			}
			if !next.IsZero() && next.After(time.Now()) && time.Now().Before(deadline) {
				w.sleepUntil(minTime(next, deadline))
				continue
			}
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

func (w *Worker) snapshotWork() (pending int, failed int, running int, due bool, next time.Time) {
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
			case OpStatePending, OpStateReconciling, OpStateVerifying, OpStateCancelRequested:
				pending++
				if op.NextAttemptUnixNano > now {
					nextTime := time.Unix(0, op.NextAttemptUnixNano)
					if next.IsZero() || nextTime.Before(next) {
						next = nextTime
					}
				} else {
					due = true
				}
			}
			return nil
		})
		return nil
	})
	return pending, failed, running, due, next
}

func (w *Worker) runDueOnce(ctx context.Context) {
	w.runDueOnceWithOptions(ctx, false)
}

// runDueOnceIgnoringRemoteQuiet is reserved for explicit drain. It preserves
// every persisted retry deadline and dependency, skipping only the transient
// namespace quiet barrier that would otherwise delay application shutdown.
func (w *Worker) runDueOnceIgnoringRemoteQuiet(ctx context.Context) {
	w.runDueOnceWithOptions(ctx, true)
}

func (w *Worker) runDueOnceWithOptions(ctx context.Context, ignoreRemoteQuiet bool) {
	// Drain can run while the background loop wakes. Serialize complete passes,
	// not just claims, so independent replacement delete/move events retain
	// their journal order at the provider.
	w.executeMu.Lock()
	defer w.executeMu.Unlock()
	w.runDueOnceLocked(ctx, ignoreRemoteQuiet)
}

// tryRunDueOnceWithOptions lets Drain preserve context responsiveness when a
// background pass acquires the execution gate between its state scan and claim.
func (w *Worker) tryRunDueOnceWithOptions(ctx context.Context, ignoreRemoteQuiet bool) bool {
	if !w.executeMu.TryLock() {
		return false
	}
	defer w.executeMu.Unlock()
	w.runDueOnceLocked(ctx, ignoreRemoteQuiet)
	return true
}

func (w *Worker) runDueOnceLocked(ctx context.Context, ignoreRemoteQuiet bool) {
	w.service.operationMu.RLock()
	defer w.service.operationMu.RUnlock()
	ops := w.claimDueWithOptions(ignoreRemoteQuiet)
	for _, op := range ops {
		w.execute(ctx, op)
	}
}

func (w *Worker) claimDue() []Op {
	return w.claimDueWithOptions(false)
}

func (w *Worker) claimDueWithOptions(ignoreRemoteQuiet bool) []Op {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.service.remoteQuietMu.Lock()
	defer w.service.remoteQuietMu.Unlock()
	var claimed []Op
	_ = w.service.store.update(func(tx boltTxT) error {
		now := time.Now().UnixNano()
		quietUntil := w.service.remoteQuietUntilNano
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
			// Running is transient in-process state; a process restart returns
			// the operation to pending before a provider mutation is retried.
			if op.State == OpStateRunning {
				previous := op
				op.State = OpStatePending
				op.NextAttemptUnixNano = now
				if err := putOp(tx, op, previous); err != nil {
					return err
				}
				continue
			}
			if opStateNeedsReconciliation(op.State) {
				if blocked, _ := w.blocked(tx, op); blocked {
					continue
				}
				w.running[op.InodeID] = struct{}{}
				claimed = append(claimed, op)
				break
			}
			if op.State != OpStatePending {
				continue
			}
			if !ignoreRemoteQuiet && !op.SkipQuiet && quietUntil > now {
				continue
			}
			if blocked, _ := w.blocked(tx, op); blocked {
				continue
			}
			w.running[op.InodeID] = struct{}{}
			previous := op
			op.State = OpStateRunning
			op.SkipQuiet = false
			if err := putOp(tx, op, previous); err != nil {
				return err
			}
			claimed = append(claimed, op)
			// Worker execution is sequential. Claiming just one entry prevents a
			// later queued provider call from overtaking a new local mutation that
			// arrives while an earlier operation is executing.
			break
		}
		return nil
	})
	return claimed
}

// recoverDurableStates repairs transient scheduling state after a process
// restart. Provider side effects are never replayed from verifying/cancel
// states; those entries are queued for probe-based reconciliation instead.
func (w *Worker) recoverDurableStates() error {
	return w.service.store.update(func(tx boltTxT) error {
		journal := tx.Bucket([]byte(bucketJournal))
		var ops []Op
		if err := journal.ForEach(func(_, value []byte) error {
			var op Op
			if err := decodeJSON(value, &op); err != nil {
				return err
			}
			ops = append(ops, op)
			return nil
		}); err != nil {
			return err
		}
		now := time.Now().UnixNano()
		for _, op := range ops {
			previous := op
			switch op.State {
			case OpStateRunning:
				op.State = OpStatePending
				op.NextAttemptUnixNano = now
			case OpStateVerifying, OpStateCancelRequested, OpStateReconciling:
				if op.NextAttemptUnixNano == 0 {
					op.NextAttemptUnixNano = now
				}
			default:
				continue
			}
			if err := putOp(tx, op, previous); err != nil {
				return err
			}
		}
		return nil
	})
}

// blocked reports whether one op must wait on an earlier unfinished journal
// operation. A directory rename/delete also waits for its earlier descendant
// work, keeping that work on the old remote subtree until the move runs.
func (w *Worker) blocked(tx boltTxT, op Op) (bool, string) {
	if pendingOpForInode(tx, op.InodeID, op.Seq) {
		return true, "earlier operation on inode pending"
	}
	record, err := getInode(tx, op.InodeID)
	if err != nil {
		return false, ""
	}
	if record.Kind == KindDirectory && (op.Type == OpRename || op.Type == OpDelete) {
		if _, pending := pendingDescendantOp(tx, op.InodeID, op.Seq); pending {
			return true, "earlier descendant operation pending"
		}
	}
	if op.Type == OpRename || op.Type == OpDelete {
		return false, ""
	}
	for _, ancestor := range []uint64{record.DesiredParentID} {
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
		if decodeJSON(raw, &prior) != nil || prior.InodeID != inode {
			return nil
		}
		if opStateUnsettled(prior.State) {
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

// beginOperation binds one provider request to a cancellable operation context.
func (w *Worker) beginOperation(parent context.Context, seq uint64) (context.Context, func(), bool) {
	if parent == nil {
		parent = context.Background()
	}
	w.mu.Lock()
	if w.cancels == nil {
		w.cancels = map[uint64]context.CancelFunc{}
	}
	ctx, cancel := context.WithCancel(parent)
	w.cancels[seq] = cancel
	w.mu.Unlock()
	return ctx, func() {
		w.mu.Lock()
		delete(w.cancels, seq)
		w.mu.Unlock()
		cancel()
	}, true
}

// cancelOperation interrupts an in-flight provider operation when it has
// reached the worker. A missing context means it has not begun provider I/O.
func (w *Worker) cancelOperation(seq uint64) {
	w.mu.Lock()
	cancel := w.cancels[seq]
	w.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func verificationContext(parent context.Context) (context.Context, context.CancelFunc) {
	if parent == nil {
		parent = context.Background()
	}
	return context.WithTimeout(parent, workerVerificationTimeout)
}

func minTime(left, right time.Time) time.Time {
	if left.Before(right) {
		return left
	}
	return right
}
