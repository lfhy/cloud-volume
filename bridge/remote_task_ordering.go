// Shared task ordering for desktop bridge and Web: unsettled tasks always sort
// before history, newest first, so the first page contains every visible
// active operation regardless of how much terminal history has accumulated.
package main

import (
	"fmt"
	"sort"
)

// activeTaskStates are the wire states that still need work or attention.
func activeTaskStates() map[string]bool {
	return map[string]bool{
		"pending": true, "waiting": true, "blocked": true, "retry_wait": true,
		"running": true, "verifying": true, "cancel_requested": true,
		"reconciling": true, "failed": true, "conflict": true,
	}
}

// taskWireSortable extracts the ordering keys one task wire map carries.
type taskWireSortable struct {
	Active    bool
	CreatedAt string
	UpdatedAt string
	ID        string
}

func taskWireSortableFrom(item map[string]any) taskWireSortable {
	stringify := func(value any) string {
		if text, ok := value.(string); ok {
			return text
		}
		return ""
	}
	status := stringify(item["status"])
	// Runtime snapshots report pending/running directly; metadata projections
	// use the same status strings through setWireState.
	return taskWireSortable{
		Active:    activeTaskStates()[status],
		CreatedAt: stringify(item["createdAt"]),
		UpdatedAt: stringify(item["updatedAt"]),
		ID:        stringify(item["id"]),
	}
}

// sortRemoteTaskItems orders active tasks first (newest first), then history
// (newest first), with the ID as the final tiebreaker for stable pagination.
func sortRemoteTaskItems(items []any) {
	sort.SliceStable(items, func(i, j int) bool {
		left := taskWireSortableFrom(items[i].(map[string]any))
		right := taskWireSortableFrom(items[j].(map[string]any))
		if left.Active != right.Active {
			return left.Active
		}
		leftStamp := taskTimestamp(left)
		rightStamp := taskTimestamp(right)
		if leftStamp != rightStamp {
			return leftStamp > rightStamp
		}
		return left.ID > right.ID
	})
}

func taskTimestamp(item taskWireSortable) string {
	if item.UpdatedAt != "" {
		return item.UpdatedAt
	}
	return item.CreatedAt
}

// remoteTaskPageSlice applies shared ordering then offset pagination.
func remoteTaskPageSlice(items []any, cursor string, limit int) ([]any, string) {
	sortRemoteTaskItems(items)
	start := taskCursorOffset(cursor)
	if start > len(items) {
		start = len(items)
	}
	items = items[start:]
	if limit <= 0 {
		limit = 100
	}
	nextCursor := ""
	if len(items) > limit {
		items = items[:limit]
		nextCursor = fmt.Sprintf("%d", start+limit)
	}
	return items, nextCursor
}
