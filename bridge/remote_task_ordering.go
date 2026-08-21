// Shared task ordering for desktop bridge and Web: unsettled tasks always sort
// before history, newest first, so the first page contains every visible
// active operation regardless of how much terminal history has accumulated.
package main

import (
	"fmt"
	"sort"
	"time"
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
	Timestamp time.Time
	ID        string
}

func taskWireString(item map[string]any, key string) string {
	if text, ok := item[key].(string); ok {
		return text
	}
	return ""
}

// taskParseTime parses RFC3339Nano/RFC3339; a zero time sorts oldest so rows
// with missing stamps cannot leapfrog real activity.
func taskParseTime(value string) time.Time {
	if value == "" {
		return time.Time{}
	}
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339} {
		if parsed, err := time.Parse(layout, value); err == nil {
			return parsed
		}
	}
	return time.Time{}
}

func taskWireSortableFrom(item map[string]any) taskWireSortable {
	updated := taskWireString(item, "updatedAt")
	if updated == "" {
		updated = taskWireString(item, "createdAt")
	}
	return taskWireSortable{
		Active:    activeTaskStates()[taskWireString(item, "status")],
		Timestamp: taskParseTime(updated),
		ID:        taskWireString(item, "id"),
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
		if !left.Timestamp.Equal(right.Timestamp) {
			return left.Timestamp.After(right.Timestamp)
		}
		return left.ID > right.ID
	})
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
