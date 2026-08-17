// Path write tests ensure UI and mount callers share durable mutation semantics.
package metadata

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

func TestWritePathReservesOneGenerationPerWrite(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	ctx := context.Background()

	inode, first, err := service.WritePath(ctx, "rapid.txt", strings.NewReader("first"), 5, WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	again, second, err := service.WritePath(ctx, "rapid.txt", strings.NewReader("second"), 6, WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	if again != inode || first.Generation == 0 || second.Generation <= first.Generation {
		t.Fatalf("write generations are not unique: inode=%d again=%d first=%+v second=%+v", inode, again, first, second)
	}
	for _, ref := range []ContentRef{first, second} {
		_, pending, err := service.pendingWrite(inode, ref.Generation)
		if err != nil {
			t.Fatalf("generation %d missing: %v", ref.Generation, err)
		}
		if pending.Size != ref.Size || len(pending.Chunks) == 0 {
			t.Fatalf("generation %d has invalid pending ref: %+v", ref.Generation, pending)
		}
	}
	if status := service.Status(); status.PendingOps != 2 {
		t.Fatalf("pending ops = %d, want 2", status.PendingOps)
	}
}

func TestCreateDirectoryPathUpdatesDesiredTree(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)

	inode, err := service.CreateDirectoryPath(context.Background(), "drafts", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	object, err := service.StatPath(context.Background(), "drafts")
	if err != nil {
		t.Fatal(err)
	}
	if object.Inode != mustInodeString(inode) || !object.IsDir || object.State != StatePending {
		t.Fatalf("unexpected directory object: %+v", object)
	}
}

func TestMaterializeDoesNotReviveDeletedPath(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/old.txt"] = storageops.ObjectInfo{Key: "old.txt", Size: 3}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Hour)
	ctx := context.Background()
	if _, err := service.ListPage(ctx, rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	if err := service.DeletePath(ctx, "old.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := service.MaterializeDirectory(ctx, rootInode); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Resolve(rootInode, "old.txt"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("deleted object revived: %v", err)
	}
}

func TestMaterializeDoesNotReviveRenameSource(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/old.txt"] = storageops.ObjectInfo{Key: "old.txt", Size: 3}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Hour)
	ctx := context.Background()
	if _, err := service.ListPage(ctx, rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, err := service.Resolve(rootInode, "old.txt")
	if err != nil {
		t.Fatal(err)
	}
	if err := service.RenamePath(ctx, "old.txt", "new.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := service.MaterializeDirectory(ctx, rootInode); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Resolve(rootInode, "old.txt"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("rename source revived: %v", err)
	}
	resolved, err := service.Resolve(rootInode, "new.txt")
	if err != nil || resolved != inode {
		t.Fatalf("rename target not retained: inode=%d resolved=%d err=%v", inode, resolved, err)
	}
}

func mustInodeString(value uint64) string {
	return strconv.FormatUint(value, 10)
}
