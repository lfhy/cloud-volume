// Bulk task sync advances every pending journal operation without bypassing dependencies.
package metadata

// TriggerPendingTasks skips the durable quiet period for every pending task in
// this namespace. It intentionally makes retrying work due now, but dependency
// predicates remain enforced by the worker, so a child operation cannot run
// before its parent has completed.
func (s *Service) TriggerPendingTasks() (int, error) {
	s.operationMu.RLock()
	s.remoteQuietMu.Lock()
	triggeredGroups := make(map[string]struct{})
	err := s.store.update(func(tx boltTxT) error {
		journal := tx.Bucket([]byte(bucketJournal))
		pending := make([]Op, 0)
		if err := journal.ForEach(func(_, raw []byte) error {
			var op Op
			if err := decodeJSON(raw, &op); err != nil {
				return err
			}
			if op.State == OpStatePending {
				pending = append(pending, op)
			}
			return nil
		}); err != nil {
			return err
		}
		now := nowUnix()
		for _, op := range pending {
			previous := op
			op.NextAttemptUnixNano = now
			op.SkipQuiet = true
			if err := putOp(tx, op, previous); err != nil {
				return err
			}
			triggeredGroups[taskGroupKey(op)] = struct{}{}
		}
		return nil
	})
	s.remoteQuietMu.Unlock()
	s.operationMu.RUnlock()
	if err != nil {
		return 0, err
	}
	if len(triggeredGroups) == 0 {
		return 0, nil
	}
	// A bulk schedule change is visible in next-attempt details and must wake
	// both the push path and the worker even though the op state stays pending.
	s.NotifyTaskChanged()
	if worker := s.taskWorker(); worker != nil {
		worker.Wake()
	}
	return len(triggeredGroups), nil
}
