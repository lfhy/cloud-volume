package metadata

import (
	"errors"
	"fmt"
	"strings"
)

// ClearTaskHistoryIDs explicitly removes selected terminal tasks while keeping
// unsettled work and tasks that still protect a later dependency intact.
func (s *Service) ClearTaskHistoryIDs(taskIDs []string) (int, error) {
	s.operationMu.RLock()
	defer s.operationMu.RUnlock()
	// Report distinct task groups, not raw ops: one visible task can fold
	// several journal ops (mkdir+rename chains, grouped writes), and the UI
	// toasts this number against the number of rows the user selected.
	removedGroups := make(map[string]struct{})
	err := s.store.update(func(tx boltTxT) error {
		remove := make(map[uint64]Op)
		for _, rawID := range taskIDs {
			taskID := strings.TrimSpace(rawID)
			if taskID == "" {
				continue
			}
			ops, err := s.taskOpsForControl(tx, taskID)
			if errors.Is(err, ErrNotFound) {
				continue
			}
			if err != nil {
				return err
			}
			for _, op := range ops {
				_, terminal := taskTerminalAt(op)
				if terminal && canCompactTaskOp(tx, op) {
					remove[op.Seq] = op
				}
			}
		}
		for _, op := range remove {
			if err := deleteTaskHistoryOp(tx, op); err != nil {
				return err
			}
			if op.TaskGroupID != "" {
				removedGroups[op.TaskGroupID] = struct{}{}
			} else {
				// Legacy ops without a group id count per op.
				removedGroups[fmt.Sprintf("seq-%d", op.Seq)] = struct{}{}
			}
		}
		return nil
	})
	if err == nil && len(removedGroups) > 0 {
		s.NotifyTaskChanged()
	}
	return len(removedGroups), err
}

func deleteTaskHistoryOp(tx boltTxT, op Op) error {
	if err := tx.Bucket([]byte(bucketJournal)).Delete(encodeUint64(op.Seq)); err != nil {
		return err
	}
	if err := tx.Bucket([]byte(bucketReadyOps)).Delete(readyKey(op)); err != nil {
		return err
	}
	if err := tx.Bucket([]byte(bucketInodeOps)).Delete(inodeOpKey(op.InodeID, op.Seq)); err != nil {
		return err
	}
	return removeTaskOpIndex(tx, op)
}
