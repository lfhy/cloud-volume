package metadata

import (
	"errors"
	"testing"
	"time"
)

// Explicit history cleanup removes selected terminal journal entries without
// touching a still-pending operation in the same namespace.
func TestClearTaskHistoryIDs(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "finished", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(rootInode, "pending", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) {
			op.State = OpStateApplied
			op.AppliedAtUnixNano = time.Now().UnixNano()
		})
	}); err != nil {
		t.Fatal(err)
	}

	removed, err := service.ClearTaskHistoryIDs([]string{TaskID(service.NamespaceID(), 1)})
	if err != nil || removed != 1 {
		t.Fatalf("explicit cleanup = %d, %v", removed, err)
	}
	if _, err := service.GetTask(TaskID(service.NamespaceID(), 1)); !errors.Is(err, ErrNotFound) {
		t.Fatalf("cleared task still exists: %v", err)
	}
	if _, err := service.GetTask(TaskID(service.NamespaceID(), 2)); err != nil {
		t.Fatalf("pending task was removed: %v", err)
	}
}

// Terminal history must sort by when it finished (applied/canceled time), not
// by creation order, so the newest completed work appears first in the UI.
func TestListTasksOrdersHistoryByFinishTime(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "older", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(rootInode, "newer", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	if err := service.store.update(func(tx boltTxT) error {
		if err := replaceOp(tx, 1, func(op *Op) {
			op.State = OpStateApplied
			op.AppliedAtUnixNano = now.Add(-time.Hour).UnixNano()
		}); err != nil {
			return err
		}
		return replaceOp(tx, 2, func(op *Op) {
			op.State = OpStateApplied
			op.AppliedAtUnixNano = now.UnixNano()
		})
	}); err != nil {
		t.Fatal(err)
	}

	tasks, err := service.ListTasks()
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 2 {
		t.Fatalf("tasks = %d, want 2", len(tasks))
	}
	first := tasks[0]
	second := tasks[1]
	if first.UpdatedAt == "" || second.UpdatedAt == "" {
		t.Fatalf("missing updatedAt stamps: %+v %+v", first, second)
	}
	firstAt, _ := time.Parse(time.RFC3339Nano, first.UpdatedAt)
	secondAt, _ := time.Parse(time.RFC3339Nano, second.UpdatedAt)
	if !secondAt.After(firstAt) {
		t.Fatalf("history order = %s then %s, want newest finish first", first.UpdatedAt, second.UpdatedAt)
	}
}
