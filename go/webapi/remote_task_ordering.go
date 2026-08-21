// Shared task ordering for the Web projection: unsettled tasks always sort
// before history, newest first, so page one contains every visible active
// operation regardless of how much terminal history has accumulated.
package webapi

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
)

// webActiveTaskStates are wire states that still need work or attention.
func webActiveTaskStates() map[string]bool {
	return map[string]bool{
		"pending": true, "waiting": true, "blocked": true, "retry_wait": true,
		"running": true, "verifying": true, "cancel_requested": true,
		"reconciling": true, "failed": true, "conflict": true,
	}
}

type webTaskSortable struct {
	Active    bool
	CreatedAt string
	UpdatedAt string
	ID        string
}

func webTaskSortableFrom(item map[string]any) webTaskSortable {
	stringify := func(value any) string {
		if text, ok := value.(string); ok {
			return text
		}
		return ""
	}
	return webTaskSortable{
		Active:    webActiveTaskStates()[stringify(item["status"])],
		CreatedAt: stringify(item["createdAt"]),
		UpdatedAt: stringify(item["updatedAt"]),
		ID:        stringify(item["id"]),
	}
}

func webTaskTimestamp(item webTaskSortable) string {
	if item.UpdatedAt != "" {
		return item.UpdatedAt
	}
	return item.CreatedAt
}

// webRemoteTaskPageSlice orders active tasks first, then applies offset
// pagination with the same contract as the desktop bridge.
func webRemoteTaskPageSlice(items []any, cursor string, limit int) ([]any, string) {
	sort.SliceStable(items, func(i, j int) bool {
		left := webTaskSortableFrom(items[i].(map[string]any))
		right := webTaskSortableFrom(items[j].(map[string]any))
		if left.Active != right.Active {
			return left.Active
		}
		leftStamp := webTaskTimestamp(left)
		rightStamp := webTaskTimestamp(right)
		if leftStamp != rightStamp {
			return leftStamp > rightStamp
		}
		return left.ID > right.ID
	})
	start := webTaskCursorOffset(cursor)
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

// webTaskCursorOffset parses the opaque numeric offset cursor.
func webTaskCursorOffset(cursor string) int {
	value, err := strconv.Atoi(strings.TrimSpace(cursor))
	if err != nil || value < 0 {
		return 0
	}
	return value
}
