// Task controls mutate durable journal state without guessing provider outcomes.
package metadata

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
)

// Task control errors distinguish an absent task from a task that is unsafe to
// mutate because it has started provider work or has dependent local intent.
var (
	ErrTaskNotCancelable  = fmt.Errorf("metadata: task is not safely cancelable")
	ErrTaskNotRetryable   = fmt.Errorf("metadata: task is not retryable")
	ErrTaskNotTriggerable = fmt.Errorf("metadata: task is not triggerable")
)

// CancelTask rolls back an entirely pending task. An in-flight operation is
// instead marked reconciling and its provider context is canceled; that state
// deliberately remains visible until a future reconciliation can prove the
// remote outcome.
func (s *Service) CancelTask(taskID string) (Task, error) {
	s.operationMu.RLock()
	var reconcile []uint64
	var removedHashes []string
	s.chunkMu.Lock()
	err := s.store.update(func(tx boltTxT) error {
		ops, err := s.taskOpsForControl(tx, taskID)
		if err != nil {
			return err
		}
		allPending, hasRunning := true, false
		for _, op := range ops {
			allPending = allPending && op.State == OpStatePending
			hasRunning = hasRunning || op.State == OpStateRunning || op.State == OpStateVerifying
		}
		if hasRunning {
			now := nowUnix()
			for _, op := range ops {
				if op.State != OpStateRunning && op.State != OpStateVerifying {
					return ErrTaskNotCancelable
				}
				previous := op
				op.State = OpStateCancelRequested
				op.CancelRequested = true
				op.CancelRequestedAtUnixNano = now
				op.ReconcileAtUnixNano = now
				if err := putOp(tx, op, previous); err != nil {
					return err
				}
				reconcile = append(reconcile, op.Seq)
			}
			return nil
		}
		if !allPending {
			return ErrTaskNotCancelable
		}
		removed, err := s.rollbackPendingTask(tx, ops)
		if err != nil {
			return err
		}
		removedHashes = append(removedHashes, removed...)
		now := nowUnix()
		for _, op := range ops {
			previous := op
			op.State = OpStateCanceled
			op.CanceledAtUnixNano = now
			op.CancelRequested = false
			op.LastError = ""
			if err := putOp(tx, op, previous); err != nil {
				return err
			}
		}
		return nil
	})
	if err == nil {
		s.removeChunkFiles(removedHashes)
		s.syncChunkProtectionBestEffortLocked()
	}
	s.chunkMu.Unlock()
	s.operationMu.RUnlock()
	if err != nil {
		return Task{}, err
	}
	// User-initiated control mutations must notify push subscribers even when
	// the worker has not picked the change up yet.
	s.NotifyTaskChanged()
	if worker := s.taskWorker(); worker != nil {
		for _, seq := range reconcile {
			worker.cancelOperation(seq)
		}
	}
	return s.GetTask(taskID)
}

// RetryTask makes a failed task eligible for the next worker pass.
func (s *Service) RetryTask(taskID string) (Task, error) {
	s.operationMu.RLock()
	s.remoteQuietMu.Lock()
	err := s.store.update(func(tx boltTxT) error {
		ops, err := s.taskOpsForControl(tx, taskID)
		if err != nil {
			return err
		}
		for _, op := range ops {
			if op.State != OpStateFailed {
				return ErrTaskNotRetryable
			}
		}
		for _, op := range ops {
			previous := op
			op.State = OpStatePending
			op.Retry = 0
			op.LastError = ""
			op.NextAttemptUnixNano = nowUnix()
			op.SkipQuiet = true
			if err := putOp(tx, op, previous); err != nil {
				return err
			}
		}
		return nil
	})
	s.remoteQuietMu.Unlock()
	s.operationMu.RUnlock()
	if err != nil {
		return Task{}, err
	}
	// A re-armed task is immediately visible; notify push subscribers.
	s.NotifyTaskChanged()
	if worker := s.taskWorker(); worker != nil {
		worker.Wake()
	}
	return s.GetTask(taskID)
}

// TriggerTask bypasses the quiet/retry delay but never bypasses dependencies.
func (s *Service) TriggerTask(taskID string) (Task, error) {
	s.operationMu.RLock()
	s.remoteQuietMu.Lock()
	err := s.store.update(func(tx boltTxT) error {
		ops, err := s.taskOpsForControl(tx, taskID)
		if err != nil {
			return err
		}
		for _, op := range ops {
			if op.State != OpStatePending {
				return ErrTaskNotTriggerable
			}
		}
		for _, op := range ops {
			previous := op
			op.NextAttemptUnixNano = nowUnix()
			op.SkipQuiet = true
			if err := putOp(tx, op, previous); err != nil {
				return err
			}
		}
		return nil
	})
	s.remoteQuietMu.Unlock()
	s.operationMu.RUnlock()
	if err != nil {
		return Task{}, err
	}
	// Manual trigger changes the next attempt visibly; notify push clients.
	s.NotifyTaskChanged()
	if worker := s.taskWorker(); worker != nil {
		worker.Wake()
	}
	return s.GetTask(taskID)
}

func (s *Service) taskOpsForControl(tx boltTxT, taskID string) ([]Op, error) {
	seq, group, segmented, err := taskSequence(s.NamespaceID(), taskID)
	if err != nil {
		return nil, err
	}
	var first Op
	if seq != 0 {
		first, err = getOp(tx, seq)
		if err != nil && group == "" {
			return nil, err
		}
		if err == nil && group != "" && first.TaskGroupID != group {
			first = Op{}
		}
	}
	if first.Seq == 0 {
		var found bool
		if err := tx.Bucket([]byte(bucketJournal)).ForEach(func(_, raw []byte) error {
			var op Op
			if err := decodeJSON(raw, &op); err != nil {
				return err
			}
			if !found && op.TaskGroupID == group {
				first, found = op, true
			}
			return nil
		}); err != nil {
			return nil, err
		}
		if !found {
			return nil, ErrNotFound
		}
		seq = first.Seq
	}
	ops := []Op{first}
	if segmented {
		return taskSegmentOps(tx, first, group)
	}
	if group != "" && first.TaskGroupID == group {
		var grouped []Op
		if err := tx.Bucket([]byte(bucketJournal)).ForEach(func(_, raw []byte) error {
			var op Op
			if err := decodeJSON(raw, &op); err != nil {
				return err
			}
			if op.TaskGroupID == group {
				grouped = append(grouped, op)
			}
			return nil
		}); err != nil {
			return nil, err
		}
		if len(grouped) > 0 {
			sort.Slice(grouped, func(i, j int) bool { return grouped[i].Seq < grouped[j].Seq })
			return grouped, nil
		}
	}
	if first.Type != OpMkdir || first.State != OpStatePending {
		return ops, nil
	}
	journal := tx.Bucket([]byte(bucketJournal))
	for next := seq + 1; ; next++ {
		raw := journal.Get(encodeUint64(next))
		if raw == nil {
			break
		}
		var op Op
		if err := decodeJSON(raw, &op); err != nil {
			return nil, err
		}
		if op.InodeID != first.InodeID || op.Type != OpRename || op.State != OpStatePending {
			break
		}
		ops = append(ops, op)
	}
	return ops, nil
}

func taskSequence(namespace, taskID string) (uint64, string, bool, error) {
	parsedNamespace, group, ok := taskIDGroup(taskID)
	if !ok || parsedNamespace != namespace {
		return 0, "", false, ErrNotFound
	}
	if segment := taskIDSegment(taskID); segment != 0 {
		return segment, group, true, nil
	}
	// Resolve a group-qualified ID to its first journal sequence. Numeric
	// suffixes from the previous format remain accepted for already-open UIs.
	if strings.HasPrefix(group, "journal-") {
		if seq, err := strconv.ParseUint(strings.TrimPrefix(group, "journal-"), 10, 64); err == nil && seq != 0 {
			return seq, group, false, nil
		}
	}
	return 0, group, false, nil
}

func taskSegmentOps(tx boltTxT, first Op, group string) ([]Op, error) {
	if group == "" || first.TaskGroupID != group {
		return []Op{first}, nil
	}
	matched := []Op{first}
	err := tx.Bucket([]byte(bucketJournal)).ForEach(func(_, raw []byte) error {
		var op Op
		if err := decodeJSON(raw, &op); err != nil {
			return err
		}
		if op.Seq == first.Seq || op.TaskGroupID != group || op.State != first.State || !canFoldTaskOps(first, op) {
			return nil
		}
		matched = append(matched, op)
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(matched, func(i, j int) bool { return matched[i].Seq < matched[j].Seq })
	return matched, nil
}
