// Worker ordering tests cover remote-edge snapshots across local tree moves.
package metadata

import (
	"context"
	"strings"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

func TestWorkerWritesRemoteSourceBeforeLaterRename(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/old.txt"] = storageops.ObjectInfo{Key: "old.txt", Size: 3, ETag: "etag-old"}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	ctx := context.Background()
	if _, err := service.ListPage(ctx, rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, err := service.Resolve(rootInode, "old.txt")
	if err != nil {
		t.Fatal(err)
	}
	ref, err := service.StageWrite(inode, 1, strings.NewReader("new"), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "old.txt", ref, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(inode, rootInode, "new.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(ctx); err != nil {
		t.Fatal(err)
	}
	if _, exists := backend.objects["/old.txt"]; exists {
		t.Fatalf("old remote path survived write+rename: %+v", backend.objects)
	}
	if object := backend.objects["/new.txt"]; object.Size != 3 {
		t.Fatalf("new remote path missing uploaded content: %+v", backend.objects)
	}
	upload, move := -1, -1
	for index, operation := range backend.ops {
		if operation == "upload:old.txt" {
			upload = index
		}
		if operation == "move:old.txt:new.txt" {
			move = index
		}
	}
	if upload < 0 || move < 0 || upload > move {
		t.Fatalf("remote mutation order = %+v, want upload old before move", backend.ops)
	}
}

func TestDirectoryRenameWaitsForEarlierChildWrite(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/dir/"] = storageops.ObjectInfo{Key: "dir/", IsDir: true}
	backend.objects["/dir/child.txt"] = storageops.ObjectInfo{Key: "dir/child.txt", Size: 3}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	ctx := context.Background()
	if _, err := service.ListPage(ctx, rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	dir, err := service.Resolve(rootInode, "dir")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.ListPage(ctx, dir, "", 10); err != nil {
		t.Fatal(err)
	}
	child, err := service.Resolve(dir, "child.txt")
	if err != nil {
		t.Fatal(err)
	}
	ref, err := service.StageWrite(child, 1, strings.NewReader("new"), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(dir, "child.txt", ref, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(dir, rootInode, "renamed", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := &Worker{service: service, wake: make(chan struct{}, 1), running: map[uint64]struct{}{}}
	claimed := worker.claimDue()
	defer worker.releaseInode(child)
	for _, op := range claimed {
		if op.Type == OpRename {
			t.Fatalf("directory rename bypassed child write: %+v", claimed)
		}
	}
}
