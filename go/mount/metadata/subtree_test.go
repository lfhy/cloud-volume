// Additional metadata coverage: subtree purge, dependency ordering, crash/replay.
package metadata

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

func TestWorkerDeletePurgesSubtreeRecords(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/dir/"] = storageops.ObjectInfo{Key: "dir/", IsDir: true}
	backend.objects["/dir/child.txt"] = storageops.ObjectInfo{Key: "dir/child.txt", Size: 2}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	page, err := service.ListPage(context.Background(), rootInode, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	var dirInode uint64
	for _, item := range page.Items {
		if item.Key == "dir/" {
			dirInode = mustParseInode(t, item.Inode)
		}
	}
	if dirInode == 0 {
		t.Fatal("dir inode not found")
	}
	if _, err := service.ListPage(context.Background(), dirInode, "", 10); err != nil {
		t.Fatal(err)
	}
	if err := service.Delete(dirInode, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, ok := backend.objects["/dir/"]; ok {
		t.Fatalf("remote directory not deleted: %+v", backend.objects)
	}
	if status := service.Status(); status.InodeCount != 1 {
		t.Fatalf("subtree records leaked, inode count=%d: %+v", status.InodeCount, status)
	}
}

func TestWorkerWaitsForPendingParentMkdir(t *testing.T) {
	backend := newFakeBackend()
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Hour)
	dirInode, err := service.CreateDirectory(rootInode, "parent", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	ref, err := service.StageWrite(dirInode, 1, strings.NewReader("data"), 4)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(dirInode, "child.txt", ref, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	claimed := worker.claimDue()
	for _, op := range claimed {
		if op.Type == OpWrite {
			t.Fatalf("child write claimed while parent mkdir pending: %+v", op)
		}
		// Release without executing so the store keeps the pending state.
		worker.releaseInode(op.InodeID)
	}
}

func TestCrashReplayRestoresPendingWriteAfterReopen(t *testing.T) {
	backend := newFakeBackend()
	root := t.TempDir() + "/metadata"
	cacheRoot := t.TempDir() + "/cache"
	store, err := OpenStore(Namespace{ID: "test", Root: root, CacheRoot: cacheRoot, Bucket: "bucket"})
	if err != nil {
		t.Fatal(err)
	}
	service := NewService(store, backend)
	// A tiny quiet period keeps the persisted op immediately due after the
	// simulated crash; no worker exists yet, so nothing executes early.
	service.SetQuietPeriod(time.Nanosecond)
	_, ref, err := service.StageWriteForName(rootInode, "note.txt", 1, strings.NewReader("data"), 4)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "note.txt", ref, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	// Simulate a crash between staging and remote execution: close without
	// draining, reopen, then drain against the same backend.
	if err := store.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := OpenStore(Namespace{ID: "test", Root: root, CacheRoot: cacheRoot, Bucket: "bucket"})
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	resumed := NewService(reopened, backend)
	resumed.SetQuietPeriod(time.Nanosecond)
	worker := NewWorker(resumed)
	defer worker.Stop()
	drainErr := worker.Drain(context.Background())
	if drainErr != nil {
		t.Fatalf("drain: %v", drainErr)
	}
	if backend.objects["/note.txt"].Size != 4 {
		t.Fatalf("replayed upload missing: %+v", backend.objects)
	}
	for _, hash := range ref.Chunks {
		if _, err := os.Stat(resumed.chunkPath(hash)); !os.IsNotExist(err) {
			t.Fatalf("pending chunk %s not retired after replay: %v", hash, err)
		}
	}
}

func TestMaterializePreservesPendingChildDroppedByRemote(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/file.txt"] = storageops.ObjectInfo{Key: "file.txt", Size: 3}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Hour)
	if _, err := service.ListPage(context.Background(), rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, err := service.Resolve(rootInode, "file.txt")
	if err != nil {
		t.Fatal(err)
	}
	ref, err := service.StageWrite(inode, 1, strings.NewReader("new"), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "file.txt", ref, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	// Remote drops the object; the pending local write must survive.
	delete(backend.objects, "/file.txt")
	if err := service.MaterializeDirectory(context.Background(), rootInode); err != nil {
		t.Fatal(err)
	}
	object, err := service.StatInode(context.Background(), inode)
	if err != nil {
		t.Fatal(err)
	}
	if object.State != StatePending {
		t.Fatalf("pending inode dropped by rematerialization: %+v", object)
	}
	for _, hash := range ref.Chunks {
		if _, err := os.Stat(service.chunkPath(hash)); err != nil {
			t.Fatalf("pending chunk %s lost: %v", hash, err)
		}
	}
}

func mustParseInode(t *testing.T, value string) uint64 {
	t.Helper()
	var inode uint64
	for _, digit := range value {
		if digit < '0' || digit > '9' {
			t.Fatalf("invalid inode %q", value)
		}
		inode = inode*10 + uint64(digit-'0')
	}
	return inode
}
