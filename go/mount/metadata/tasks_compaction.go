// Task-history compaction plans safe journal deletion without quadratic scans.
package metadata

import (
	"fmt"
	"time"
)

// ClearTaskHistory removes terminal journal entries older than before within
// this namespace. It reports distinct task groups (matching the UI-selected
// path) rather than raw journal ops.
func (s *Service) ClearTaskHistory(before time.Time) (int, error) {
	s.operationMu.RLock()
	clearedGroups := make(map[string]struct{})
	err := s.store.update(func(tx boltTxT) error {
		remove, err := compactTaskHistory(tx, before)
		if err != nil {
			return err
		}
		for _, op := range remove {
			if err := deleteTaskHistoryOp(tx, op); err != nil {
				return err
			}
			clearedGroups[taskGroupKey(op)] = struct{}{}
		}
		return nil
	})
	s.operationMu.RUnlock()
	if err == nil && len(clearedGroups) > 0 {
		s.NotifyTaskChanged()
	}
	return len(clearedGroups), err
}

// compactTaskHistory walks the sequence-ordered journal backwards. Every
// later unsettled operation contributes the inode/parent identities that keep
// an older terminal operation visible. This is equivalent to checking each
// candidate against a complete later-journal scan, but stays linear in the
// number of journal records.
func compactTaskHistory(tx boltTxT, before time.Time) ([]Op, error) {
	journal := tx.Bucket([]byte(bucketJournal))
	refs := tx.Bucket([]byte(bucketContentRefs))
	protected := make(map[uint64]struct{})
	remove := make([]Op, 0)
	cursor := journal.Cursor()
	for key, raw := cursor.Last(); key != nil; key, raw = cursor.Prev() {
		var op Op
		if err := decodeJSON(raw, &op); err != nil {
			return nil, err
		}
		if opStateUnsettled(op.State) {
			protected[op.InodeID] = struct{}{}
			protected[op.OldParent] = struct{}{}
			protected[op.NewParent] = struct{}{}
			continue
		}
		at, terminal := taskTerminalAt(op)
		if !terminal || (!before.IsZero() && !at.Before(before)) {
			continue
		}
		if op.Type == OpWrite && refs.Get(contentRefKey(op.InodeID, op.ContentGeneration)) != nil {
			continue
		}
		if _, retained := protected[op.InodeID]; retained {
			continue
		}
		remove = append(remove, op)
	}
	return remove, nil
}

// canCompactTaskOp retains the precise, selected-row guard. The explicit path
// normally touches only a few records, while full cleanup uses compactTaskHistory.
func canCompactTaskOp(tx boltTxT, candidate Op) bool {
	if candidate.Type == OpWrite {
		if tx.Bucket([]byte(bucketContentRefs)).Get(contentRefKey(candidate.InodeID, candidate.ContentGeneration)) != nil {
			return false
		}
	}
	return tx.Bucket([]byte(bucketJournal)).ForEach(func(_, raw []byte) error {
		var later Op
		if decodeJSON(raw, &later) != nil || later.Seq <= candidate.Seq || !opStateUnsettled(later.State) {
			return nil
		}
		if later.InodeID == candidate.InodeID || later.OldParent == candidate.InodeID || later.NewParent == candidate.InodeID {
			return errKeepTaskHistory
		}
		return nil
	}) == nil
}

func taskTerminalAt(op Op) (time.Time, bool) {
	switch op.State {
	case OpStateApplied:
		return time.Unix(0, op.AppliedAtUnixNano), true
	case OpStateCanceled:
		return time.Unix(0, op.CanceledAtUnixNano), true
	default:
		return time.Time{}, false
	}
}

var errKeepTaskHistory = fmt.Errorf("metadata: retain task history")
