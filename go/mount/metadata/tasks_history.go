package metadata

import (
	"errors"
	"strings"
)

// ClearTaskHistoryIDs explicitly removes selected terminal tasks while keeping
// unsettled work and tasks that still protect a later dependency intact.
func (s *Service) ClearTaskHistoryIDs(taskIDs []string) (int, error) {
	s.operationMu.RLock()
	defer s.operationMu.RUnlock()
	removedCount := 0
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
		}
		removedCount = len(remove)
		return nil
	})
	return removedCount, err
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
