// Ordering tests pin the page-one visibility contract: active tasks must
// never be pushed off the first page by accumulated terminal history.
package main

import (
	"fmt"
	"testing"
)

func TestSortRemoteTaskItemsKeepsActiveFirst(t *testing.T) {
	items := make([]any, 0, 120)
	for index := 0; index < 118; index++ {
		items = append(items, map[string]any{
			"id":        fmt.Sprintf("sync:ns:g-history-%03d", index),
			"status":    "done",
			"createdAt": fmt.Sprintf("2026-08-01T00:%02d:00Z", index%60),
			"updatedAt": fmt.Sprintf("2026-08-01T00:%02d:00Z", index%60),
		})
	}
	items = append(items,
		map[string]any{
			"id": "sync:ns:g-active-new", "status": "running",
			"createdAt": "2026-08-21T01:00:00Z", "updatedAt": "2026-08-21T01:00:00Z",
		},
		map[string]any{
			"id": "sync:ns:g-failed-new", "status": "failed",
			"createdAt": "2026-08-21T02:00:00Z", "updatedAt": "2026-08-21T02:00:00Z",
		},
	)
	page, next := remoteTaskPageSlice(items, "", 100)
	if next == "" {
		t.Fatal("expected a pagination cursor for 120 items")
	}
	if len(page) != 100 {
		t.Fatalf("page size = %d, want 100", len(page))
	}
	first := page[0].(map[string]any)["id"].(string)
	if first != "sync:ns:g-failed-new" {
		t.Fatalf("newest active-first id = %q, want the failed task", first)
	}
	var activeSeen int
	for _, raw := range page {
		if activeTaskStates()[raw.(map[string]any)["status"].(string)] {
			activeSeen++
		}
	}
	if activeSeen != 2 {
		t.Fatalf("page-one active count = %d, want both active tasks", activeSeen)
	}
}

func TestRemoteTaskPageSliceCursorContinues(t *testing.T) {
	items := make([]any, 0, 5)
	for index := 0; index < 5; index++ {
		items = append(items, map[string]any{
			"id":        fmt.Sprintf("sync:ns:g-%d", index),
			"status":    "done",
			"createdAt": fmt.Sprintf("2026-08-01T00:00:0%dZ", index),
		})
	}
	page, next := remoteTaskPageSlice(items, "", 2)
	if len(page) != 2 || next != "2" {
		t.Fatalf("first slice = %d items, cursor %q", len(page), next)
	}
	rest, done := remoteTaskPageSlice(items, next, 100)
	if done != "" || len(rest) != 3 {
		t.Fatalf("second slice = %d items, cursor %q", len(rest), done)
	}
}

