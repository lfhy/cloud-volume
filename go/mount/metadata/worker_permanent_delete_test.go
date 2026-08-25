// Permanent-delete replay tests keep page trash intent durable across restarts.
package metadata

import (
	"context"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

func TestPermanentDeleteRetainsHardModeAfterReopen(t *testing.T) {
	backend := &hardDeleteBackend{fakeBackend: newFakeBackend()}
	backend.objects["/old.txt"] = storageops.ObjectInfo{Key: "old.txt", Size: 3}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Hour)
	if _, err := service.ListPage(context.Background(), rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, err := service.Resolve(rootInode, "old.txt")
	if err != nil {
		t.Fatal(err)
	}
	if err := service.Delete(inode, WriteOptions{Origin: "page", HardDelete: true}); err != nil {
		t.Fatal(err)
	}
	namespace := service.store.namespace
	if err := service.Close(); err != nil {
		t.Fatal(err)
	}
	store, err := OpenStore(namespace)
	if err != nil {
		t.Fatal(err)
	}
	resumed := NewService(store, backend)
	defer resumed.Close()
	if err := resumed.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) { op.NextAttemptUnixNano = time.Now().Add(-time.Second).UnixNano() })
	}); err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(resumed)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatal(err)
	}
	if backend.hardDeleteCalls != 1 {
		t.Fatalf("hard delete calls after reopen = %d, want 1", backend.hardDeleteCalls)
	}
}
