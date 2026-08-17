// Writeback rename barriers preserve Explorer mutation order without disabling upload concurrency.
// Persisted mutation records make every queued remote move restart-safe and
// state-reconciled: the reconciler retries from observed provider state, not
// from an in-memory closure.
package mount

import (
	"context"
	"fmt"
	"log"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const writebackBarrierPollInterval = 50 * time.Millisecond

type writebackBarrier struct {
	generation uint64
	finished   bool
}

type writebackSourceRebase struct {
	generation uint64
	oldRoot    string
	newRoot    string
	isDir      bool
}

type queuedWritebackRename struct {
	barrier    *writebackBarrier
	dirBarrier *dirSyncBarrier
	record     mutationRecord
	oldVirtual string
	newVirtual string
	oldLocal   string
	newLocal   string
	isDir      bool
	run        func() error
}

// enqueueMutation captures a remote move as a persisted mutation record and
// fences uploads plus directory creates around it. The reconciler owns all
// retries; the run closure is retained only so legacy synchronous callers
// keep their original behavior.
func (q *writebackQueue) enqueueMutation(
	record mutationRecord,
	oldLocal,
	newLocal string,
	run func() error,
	dirBarrier *dirSyncBarrier,
) error {
	if q == nil || run == nil {
		return fmt.Errorf("writeback rename queue is unavailable")
	}

	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return fmt.Errorf("writeback queue is closed")
	}
	barrier := &writebackBarrier{generation: q.generation}
	q.generation++
	q.barriers = append(q.barriers, barrier)
	rebase := writebackSourceRebase{
		generation: barrier.generation,
		oldRoot:    filepath.Clean(oldLocal),
		newRoot:    filepath.Clean(newLocal),
		isDir:      record.IsDirectory,
	}
	q.sourceRebases = append(q.sourceRebases, rebase)
	q.rebasePendingSourcesLocked(rebase)
	record.Scope = q.scope
	record.UploadGeneration = barrier.generation
	record.UpdatedAtUnixNs = time.Now().UnixNano()
	if err := q.mutations.Upsert(record); err != nil {
		q.mu.Unlock()
		return fmt.Errorf("persist rename mutation: %w", err)
	}
	queue := q.renameQueue
	stop := q.stop
	q.mu.Unlock()

	op := &queuedWritebackRename{
		barrier:    barrier,
		dirBarrier: dirBarrier,
		record:     record,
		oldVirtual: record.OldVirtualPath,
		newVirtual: record.NewVirtualPath,
		oldLocal:   oldLocal,
		newLocal:   newLocal,
		isDir:      record.IsDirectory,
		run:        run,
	}
	log.Printf(
		"[mount/writeback] rename-queued bucket=%q old=%q new=%q generation=%d id=%s",
		q.bucketName(),
		op.oldVirtual,
		op.newVirtual,
		barrier.generation,
		record.ID,
	)
	select {
	case queue <- op:
		return nil
	case <-stop:
		q.finishRenameBarrier(op, fmt.Errorf("writeback queue stopped before rename"))
		return fmt.Errorf("writeback queue stopped before rename")
	}
}

func (q *writebackQueue) dispatchRenames() {
	defer q.renameWG.Done()
	for {
		select {
		case <-q.stop:
			return
		case op := <-q.renameQueue:
			if op != nil {
				q.executeQueuedRename(op)
			}
		}
	}
}

// executeQueuedRename drains prior uploads and directory creates, then runs
// the captured rename once through the legacy closure (which preserves the
// rebased-create destination guarantee and the local-only-source shortcut).
// Every retry after that — and every restored record — is state-driven: the
// reconciler converges from observed provider state until verified.
func (q *writebackQueue) executeQueuedRename(op *queuedWritebackRename) {
	if err := q.drainThroughGeneration(op.barrier.generation); err != nil {
		q.finishRenameBarrier(op, err)
		return
	}
	access := q.currentAccess()
	if access != nil && access.dirSync != nil {
		if err := access.dirSync.wait(context.Background(), op.dirBarrier); err != nil {
			q.finishRenameBarrier(op, err)
			return
		}
	}
	if access == nil {
		q.finishRenameBarrier(op, fmt.Errorf("missing writeback access"))
		return
	}

	if op.run != nil {
		if err := op.run(); err == nil {
			if completeErr := q.mutations.Complete(op.record.ID); completeErr != nil {
				log.Printf(
					"[mount/writeback] mutation-complete-error bucket=%q id=%s error=%v",
					q.bucketName(),
					op.record.ID,
					completeErr,
				)
			}
			q.setMutationError("")
			q.finishRenameBarrier(op, nil)
			return
		} else {
			record := op.record
			record.RetryCount++
			record.NextAttemptUnixNs = time.Now().Add(mutationRetryDelay(record)).UnixNano()
			record.LastError = err.Error()
			record.UpdatedAtUnixNs = time.Now().UnixNano()
			if persistErr := q.mutations.Upsert(record); persistErr != nil {
				log.Printf(
					"[mount/writeback] mutation-persist-error bucket=%q id=%s error=%v",
					q.bucketName(),
					record.ID,
					persistErr,
				)
			}
			op.record = record
			q.setMutationError(err.Error())
			log.Printf(
				"[mount/writeback] rename-retry bucket=%q old=%q new=%q attempt=%d error=%v",
				q.bucketName(),
				op.oldVirtual,
				op.newVirtual,
				record.RetryCount,
				err,
			)
		}
	}

	for {
		retry, err := q.reconcileQueuedRename(access, op)
		if err == nil {
			q.finishRenameBarrier(op, nil)
			return
		}
		if !retry {
			q.finishRenameBarrier(op, err)
			return
		}
		delay := mutationRetryDelay(op.record)
		log.Printf(
			"[mount/writeback] rename-retry bucket=%q old=%q new=%q attempt=%d error=%v",
			q.bucketName(),
			op.oldVirtual,
			op.newVirtual,
			op.record.RetryCount,
			err,
		)
		select {
		case <-q.stop:
			q.finishRenameBarrier(op, err)
			return
		case <-time.After(delay):
		}
	}
}

// reconcileQueuedRename performs one state-driven attempt. It returns
// (retryable, error): retryable true keeps the barrier closed and schedules
// another pass; retryable false ends the rename as failed.
func (q *writebackQueue) reconcileQueuedRename(
	access *bucketAccess,
	op *queuedWritebackRename,
) (bool, error) {
	access.writebackMu.Lock()
	defer access.writebackMu.Unlock()
	access.mutationMu.Lock()
	defer access.mutationMu.Unlock()
	record := op.record
	ctx, cancel := context.WithTimeout(context.Background(), access.requestTimeout)
	defer cancel()
	err := access.reconcileRemoteMove(ctx, record)
	if err == nil {
		if access.deletes != nil {
			access.deletes.rebase(record.OldVirtualPath, record.NewVirtualPath, record.IsDirectory)
		}
		if err := access.applyMutationSuccess(record); err != nil {
			err = fmt.Errorf("apply local rename state: %w", err)
		} else {
			if completeErr := q.mutations.Complete(record.ID); completeErr != nil {
				// The move is verified remotely; only bookkeeping failed. The
				// next reconcile pass sees source-absent/destination-present and
				// completes without repeating the provider mutation.
				log.Printf(
					"[mount/writeback] mutation-complete-error bucket=%q id=%s error=%v",
					q.bucketName(),
					record.ID,
					completeErr,
				)
			}
			q.setMutationError("")
			return false, nil
		}
	}
	record.RetryCount++
	record.NextAttemptUnixNs = time.Now().Add(mutationRetryDelay(record)).UnixNano()
	record.LastError = err.Error()
	record.UpdatedAtUnixNs = time.Now().UnixNano()
	if persistErr := q.mutations.Upsert(record); persistErr != nil {
		log.Printf(
			"[mount/writeback] mutation-persist-error bucket=%q id=%s error=%v",
			q.bucketName(),
			record.ID,
			persistErr,
		)
	}
	op.record = record
	q.setMutationError(err.Error())
	return true, err
}

// pendingMutations lists live mutation records (diagnostic/test surface).
func (q *writebackQueue) pendingMutations() []mutationRecord {
	if q == nil || q.mutations == nil {
		return nil
	}
	live, err := q.mutations.Restore()
	if err != nil {
		return nil
	}
	records := make([]mutationRecord, 0, len(live))
	ids := make([]string, 0, len(live))
	for id := range live {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		records = append(records, live[id])
	}
	return records
}

// mutationLastError surfaces the most recent durable mutation failure so
// mountSession.status() can report it without an in-memory callback.
func (q *writebackQueue) mutationLastError() string {
	if q == nil {
		return ""
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	return q.mutationErr
}

func (q *writebackQueue) setMutationError(message string) {
	q.mu.Lock()
	q.mutationErr = message
	q.mu.Unlock()
}

func (q *writebackQueue) drainThroughGeneration(generation uint64) error {
	for {
		ready, pending, running, err := q.prepareBarrierPass(generation)
		if err != nil {
			return err
		}
		for _, entry := range ready {
			select {
			case q.queue <- entry:
			case <-q.stop:
				return fmt.Errorf("writeback queue stopped while draining rename barrier")
			}
		}
		if pending == 0 && running == 0 {
			return nil
		}
		select {
		case <-q.stop:
			return fmt.Errorf("writeback queue stopped while waiting for rename barrier")
		case <-time.After(writebackBarrierPollInterval):
		}
	}
}

func (q *writebackQueue) prepareBarrierPass(
	generation uint64,
) ([]*pendingWriteback, int, int, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.closed {
		return nil, 0, 0, fmt.Errorf("writeback queue is closed")
	}

	ready := []*pendingWriteback{}
	pending := 0
	running := 0
	for _, entry := range q.entries {
		if entry == nil || entry.generation > generation {
			continue
		}
		pending++
		if entry.queued {
			continue
		}
		if entry.timer != nil {
			entry.timer.Stop()
			entry.timer = nil
		}
		entry.queued = true
		entry.dueAt = time.Now()
		q.persistEntryLocked(entry)
		ready = append(ready, entry)
	}
	for _, entry := range q.running {
		if entry != nil && entry.generation <= generation {
			running++
		}
	}
	return ready, pending, running, nil
}

func (q *writebackQueue) generationBlockedLocked(generation uint64) bool {
	for _, barrier := range q.barriers {
		if barrier != nil && !barrier.finished && generation > barrier.generation {
			return true
		}
	}
	return false
}

func (q *writebackQueue) rebasePendingSourcesLocked(rebase writebackSourceRebase) {
	for _, entry := range q.entries {
		if entry == nil || entry.generation > rebase.generation {
			continue
		}
		if next, ok := rebaseWritebackSource(entry.localPath, rebase); ok {
			entry.localPath = next
			q.persistEntryLocked(entry)
		}
	}
}

func (q *writebackQueue) resolveEntryLocalPath(entry *pendingWriteback) string {
	q.mu.Lock()
	defer q.mu.Unlock()
	if entry == nil {
		return ""
	}

	current := entry.localPath
	for _, rebase := range q.sourceRebases {
		if entry.generation > rebase.generation {
			continue
		}
		if next, ok := rebaseWritebackSource(current, rebase); ok {
			current = next
		}
	}
	if current != entry.localPath {
		entry.localPath = current
		q.persistEntryLocked(entry)
	}
	return current
}

func rebaseWritebackSource(
	localPath string,
	rebase writebackSourceRebase,
) (string, bool) {
	if strings.TrimSpace(localPath) == "" || rebase.oldRoot == "." || rebase.newRoot == "." {
		return localPath, false
	}
	relative, err := filepath.Rel(rebase.oldRoot, filepath.Clean(localPath))
	if err != nil {
		return localPath, false
	}
	if relative == "." {
		return rebase.newRoot, true
	}
	if !rebase.isDir || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return localPath, false
	}
	return filepath.Join(rebase.newRoot, relative), true
}

func (q *writebackQueue) finishRenameBarrier(op *queuedWritebackRename, err error) {
	q.mu.Lock()
	if op != nil && op.barrier != nil {
		op.barrier.finished = true
		generation := op.barrier.generation
		keptRebases := q.sourceRebases[:0]
		for _, rebase := range q.sourceRebases {
			if rebase.generation != generation {
				keptRebases = append(keptRebases, rebase)
			}
		}
		q.sourceRebases = keptRebases
		for len(q.barriers) > 0 && q.barriers[0].finished {
			q.barriers = q.barriers[1:]
		}
	}
	q.mu.Unlock()

	if op != nil {
		log.Printf(
			"[mount/writeback] rename-finished bucket=%q old=%q new=%q error=%v",
			q.bucketName(),
			op.oldVirtual,
			op.newVirtual,
			err,
		)
	}
}
