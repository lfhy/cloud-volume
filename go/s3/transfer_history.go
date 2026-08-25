package s3

import "strings"

// ForgetTerminalTransfers removes selected, or all scoped, completed/canceled
// runtime history. Failed transfers remain visible in the retry queue just as
// failed metadata tasks do; they are not clear-history records.
func ForgetTerminalTransfers(ids []string, profileID, bucket string) int {
	selected := make(map[string]struct{}, len(ids))
	for _, rawID := range ids {
		id := strings.TrimPrefix(strings.TrimSpace(rawID), "transfer:")
		if id != "" {
			selected[id] = struct{}{}
		}
	}
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	removed := 0
	for id, task := range globalTransferMonitor.tasks {
		if len(selected) > 0 {
			if _, ok := selected[id]; !ok {
				continue
			}
		} else if !isClearableHistoryTransferStatus(task.snapshot.Status) {
			continue
		}
		if profileID != "" && task.snapshot.ProfileID != profileID {
			continue
		}
		if bucket != "" && task.snapshot.Bucket != bucket {
			continue
		}
		if !isClearableHistoryTransferStatus(task.snapshot.Status) {
			continue
		}
		delete(globalTransferMonitor.tasks, id)
		delete(globalTransferMonitor.pendingCancels, id)
		removed++
	}
	return removed
}

func isClearableHistoryTransferStatus(status string) bool {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "done", "completed", "canceled", "cancelled":
		return true
	default:
		return false
	}
}
