package s3

import "strings"

// ForgetTerminalTransfers removes selected, or all scoped, terminal runtime
// snapshots. Durable metadata history is owned by the metadata service.
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
		} else if !isTerminalTransferStatus(task.snapshot.Status) {
			continue
		}
		if profileID != "" && task.snapshot.ProfileID != profileID {
			continue
		}
		if bucket != "" && task.snapshot.Bucket != bucket {
			continue
		}
		if !isTerminalTransferStatus(task.snapshot.Status) {
			continue
		}
		delete(globalTransferMonitor.tasks, id)
		delete(globalTransferMonitor.pendingCancels, id)
		removed++
	}
	return removed
}

func isTerminalTransferStatus(status string) bool {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "done", "completed", "failed", "canceled", "cancelled":
		return true
	default:
		return false
	}
}
