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
