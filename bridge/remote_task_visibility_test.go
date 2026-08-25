// Visibility tests pin the queue-count contract used by active-only polling.
package main

import (
	"fmt"
	"testing"

	s3ops "remote-storage/go/s3"
)

func TestActiveResponseKeepsFullHistoryCountsAndAllActiveRows(t *testing.T) {
	items := make([]any, 0, 301)
	for index := 0; index < 200; index++ {
		items = append(items, map[string]any{
			"id": fmt.Sprintf("history-%03d", index), "status": "done",
		})
	}
	for index := 0; index < 101; index++ {
		items = append(items, map[string]any{
			"id": fmt.Sprintf("waiting-%03d", index), "status": "waiting",
		})
	}

	counts := remoteTaskQueueFromItems(items)
	if counts.Total != 301 || counts.History != 200 || counts.Waiting != 101 {
		t.Fatalf("queue counts = %#v, want total=301 history=200 waiting=101", counts)
	}
	active := remoteTaskResponseItems(items, false)
	if len(active) != 101 {
		t.Fatalf("active response rows = %d, want 101", len(active))
	}
	page, next := remoteTaskPageSlice(active, "", len(active))
	if len(page) != 101 || next != "" {
		t.Fatalf("active page = %d rows, cursor %q; want every active row", len(page), next)
	}
}

func TestTaskCountInputIncludesTerminalRuntimeHistory(t *testing.T) {
	for _, status := range []string{"done", "completed", "canceled", "cancelled"} {
		terminal := s3ops.TransferSnapshot{Status: status}
		input := remoteTaskListArgs{IncludeHistory: false}
		if runtimeTaskMatches(terminal, input) {
			t.Fatalf("active-only response matched terminal %q", status)
		}
		if !runtimeTaskMatches(terminal, remoteTaskCountInput(input)) {
			t.Fatalf("queue count scope omitted terminal %q", status)
		}
	}
}

func TestQueueCountsMatchDartRuntimeStatusBuckets(t *testing.T) {
	items := []any{
		map[string]any{"status": "pending"},
		map[string]any{"status": "running"},
		map[string]any{"status": "failed"},
		map[string]any{"status": "completed"},
		map[string]any{"status": "cancelled"},
	}
	counts := remoteTaskQueueFromItems(items)
	if counts.Total != 5 || counts.Waiting != 1 || counts.Active != 1 ||
		counts.Failed != 1 || counts.History != 2 {
		t.Fatalf("queue counts = %#v, want pending=waiting and terminal aliases=history", counts)
	}
}
