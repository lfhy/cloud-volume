// MVP recovery tests pin durable Desired state and remote-base rebuild behavior.
package metadata

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

func TestPendingRenameSurvivesReopenBeforeWorker(t *testing.T) {
	backend := newFakeBackend()
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Hour)
	ctx := context.Background()
	if _, _, err := service.WritePath(
		ctx, "draft.txt", strings.NewReader("payload"), 7, WriteOptions{Origin: "page"},
	); err != nil {
		t.Fatal(err)
	}
	if err := service.RenamePath(ctx, "draft.txt", "final.txt", WriteOptions{Origin: "page"}); err != nil {
		t.Fatal(err)
	}
	namespace := service.store.namespace
	if err := service.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := OpenStore(namespace)
	if err != nil {
		t.Fatal(err)
	}
	resumed := NewService(reopened, backend)
	defer resumed.Close()
	object, err := resumed.StatPath(ctx, "final.txt")
	if err != nil || object.State != StatePending || object.Size != 7 {
		t.Fatalf("reopened Desired rename = %+v err=%v", object, err)
	}
	if _, err := resumed.StatPath(ctx, "draft.txt"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("reopened source path error = %v, want not found", err)
	}
}

func TestForcedResetRebuildsIdleRemoteBase(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/remote.txt"] = storageops.ObjectInfo{Key: "remote.txt", Size: 5}
	service := newTestService(t, backend)
	ctx := context.Background()
	if _, err := service.ListPage(ctx, rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	result, err := service.Reset(true)
	if err != nil || !result.Reset {
		t.Fatalf("forced reset result=%+v err=%v", result, err)
	}
	page, err := service.ListPage(ctx, rootInode, "", 10)
	if err != nil || len(page.Items) != 1 || page.Items[0].Key != "remote.txt" {
		t.Fatalf("rebuilt remote page=%+v err=%v", page, err)
	}
	if _, err := os.Stat(service.store.namespace.Root + "/metadata.db"); err != nil {
		t.Fatalf("rebuilt database is unavailable: %v", err)
	}
}
