package metadata

import "fmt"

// physicalTaskID scopes short-lived provider snapshots to one namespace. The
// monitor is process-global, while journal sequences restart at one per DB.
func physicalTaskID(namespace string, seq uint64) string {
	return fmt.Sprintf("metadata-op-%s-%d", namespace, seq)
}
