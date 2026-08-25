// Worker ordering tests cover remote-edge snapshots across local tree moves.
package metadata

import (
	"context"
	"errors"
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

func TestWriteConfirmationRetainsPendingRenameDuringRefresh(t *testing.T) {
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
	time.Sleep(time.Millisecond)
	worker := &Worker{service: service, wake: make(chan struct{}, 1), running: map[uint64]struct{}{}}
	claimed := worker.claimDue()
	if len(claimed) != 1 || claimed[0].Type != OpWrite {
		t.Fatalf("first claim = %+v, want only write", claimed)
	}
	worker.execute(ctx, claimed[0])

	if err := service.MaterializeDirectory(ctx, rootInode); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Resolve(rootInode, "old.txt"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("refresh revived remote source: %v", err)
	}
	if resolved, err := service.Resolve(rootInode, "new.txt"); err != nil || resolved != inode {
		t.Fatalf("refresh lost renamed inode: got=%d want=%d err=%v", resolved, inode, err)
	}

	worker.runDueOnce(ctx)
	if _, exists := backend.objects["/old.txt"]; exists {
		t.Fatalf("old remote path survived rename: %+v", backend.objects)
	}
	if _, exists := backend.objects["/new.txt"]; !exists {
		t.Fatalf("new remote path missing after rename: %+v", backend.objects)
	}
}

func TestRefreshUnmaterializedRenameTargetKeepsRemoteSource(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/source/"] = storageops.ObjectInfo{Key: "source/", IsDir: true}
	backend.objects["/source/old.txt"] = storageops.ObjectInfo{Key: "source/old.txt", Size: 3, ETag: "etag-old"}
	backend.objects["/target/"] = storageops.ObjectInfo{Key: "target/", IsDir: true}
	backend.objects["/target/new.txt"] = storageops.ObjectInfo{Key: "target/new.txt", Size: 6, ETag: "etag-target"}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	ctx := context.Background()
	if _, err := service.ListPage(ctx, rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	source, err := service.Resolve(rootInode, "source")
	if err != nil {
		t.Fatal(err)
	}
	target, err := service.Resolve(rootInode, "target")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.ListPage(ctx, source, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, err := service.Resolve(source, "old.txt")
	if err != nil {
		t.Fatal(err)
	}
	ref, err := service.StageWrite(inode, 1, strings.NewReader("new"), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(source, "old.txt", ref, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(inode, target, "new.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	time.Sleep(time.Millisecond)
	worker := &Worker{service: service, wake: make(chan struct{}, 1), running: map[uint64]struct{}{}}
	claimed := worker.claimDue()
	if len(claimed) != 1 || claimed[0].Type != OpWrite {
		t.Fatalf("first claim = %+v, want only write", claimed)
	}
	worker.execute(ctx, claimed[0])

	if err := service.MaterializeDirectory(ctx, target); err != nil {
		t.Fatal(err)
	}
	if resolved, err := service.Resolve(target, "new.txt"); err != nil || resolved != inode {
		t.Fatalf("target refresh replaced pending inode: got=%d want=%d err=%v", resolved, inode, err)
	}
	worker.runDueOnce(ctx)
	if _, exists := backend.objects["/source/old.txt"]; exists {
		t.Fatalf("source survived cross-directory move: %+v", backend.objects)
	}
	if object, exists := backend.objects["/target/new.txt"]; !exists || object.Size != 3 {
		t.Fatalf("target was not replaced by staged write: %+v", backend.objects)
	}
}

func TestMoveReplayConfirmsAppliedRemoteMoveAfterReopen(t *testing.T) {
	backend := &moveConfirmationFailureBackend{fakeBackend: newFakeBackend(), failTargetHead: true}
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
	if err := service.Rename(inode, rootInode, "new.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	time.Sleep(time.Millisecond)
	worker := &Worker{service: service, wake: make(chan struct{}, 1), running: map[uint64]struct{}{}}
	claimed := worker.claimDue()
	if len(claimed) != 1 || claimed[0].Type != OpRename {
		t.Fatalf("first claim = %+v, want one rename", claimed)
	}
	worker.execute(ctx, claimed[0])
	if moves := backend.moveCount(); moves != 1 {
		t.Fatalf("remote move count after interrupted confirmation = %d, want 1", moves)
	}
	var afterFirst Op
	if err := service.store.view(func(tx boltTxT) error {
		var err error
		afterFirst, err = getOp(tx, claimed[0].Seq)
		return err
	}); err != nil {
		t.Fatal(err)
	}
	if !afterFirst.MoveApplied || afterFirst.State != OpStatePending {
		t.Fatalf("rename did not retain applied-move phase: %+v", afterFirst)
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
	resumed.SetQuietPeriod(time.Nanosecond)
	// Materializing the target before retry must preserve the remote source edge
	// until the persisted move phase confirms the target.
	if err := resumed.MaterializeDirectory(ctx, rootInode); err != nil {
		t.Fatal(err)
	}
	if err := resumed.store.update(func(tx boltTxT) error {
		return replaceOp(tx, claimed[0].Seq, func(op *Op) {
			op.NextAttemptUnixNano = time.Now().Add(-time.Second).UnixNano()
		})
	}); err != nil {
		t.Fatal(err)
	}
	retryWorker := NewWorker(resumed)
	defer retryWorker.Stop()
	if err := retryWorker.Drain(ctx); err != nil {
		t.Fatal(err)
	}
	if moves := backend.moveCount(); moves != 1 {
		t.Fatalf("replay repeated an already-applied remote move: %d", moves)
	}
	if _, err := resumed.StatPath(ctx, "new.txt"); err != nil {
		t.Fatalf("replayed rename missing desired target: %v", err)
	}
}

// moveConfirmationFailureBackend fails the first target HEAD after accepting
// a move, reproducing the crash/retry boundary without changing the move.
type moveConfirmationFailureBackend struct {
	*fakeBackend
	failTargetHead bool
	failTargetKey  string
}

func (b *moveConfirmationFailureBackend) HeadObject(ctx context.Context, bucket, key string) (storageops.ObjectInfo, error) {
	target := b.failTargetKey
	if target == "" {
		target = "new.txt"
	}
	if key == target && b.failTargetHead {
		b.failTargetHead = false
		return storageops.ObjectInfo{}, errors.New("temporary target confirmation failure")
	}
	return b.fakeBackend.HeadObject(ctx, bucket, key)
}

func (b *moveConfirmationFailureBackend) moveCount() int {
	count := 0
	for _, operation := range b.ops {
		if strings.HasPrefix(operation, "move:") {
			count++
		}
	}
	return count
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

func TestWorkerCreatesRecursiveChildrenAtConfirmedParentBeforeAncestorMove(t *testing.T) {
	backend := &directoryMarkerMoveBackend{fakeBackend: newFakeBackend()}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	ctx := context.Background()

	if _, err := service.EnsureDirectoryPath(ctx, "project/core/proxy", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	project, err := service.Resolve(rootInode, "project")
	if err != nil {
		t.Fatal(err)
	}
	worker := newManualWorker(service)
	first := worker.claimDue()
	if len(first) != 1 || first[0].Type != OpMkdir {
		t.Fatalf("first claim = %+v, want project mkdir", first)
	}
	worker.execute(ctx, first[0])
	if err := service.Rename(project, rootInode, "renamed", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}

	if err := worker.Drain(ctx); err != nil {
		t.Fatalf("recursive mkdir plus ancestor rename stalled: %v", err)
	}
	want := []string{
		"mkdir:project",
		"mkdir:project/core",
		"mkdir:project/core/proxy",
		"move:project:renamed",
	}
	if strings.Join(backend.ops, ",") != strings.Join(want, ",") {
		t.Fatalf("remote operation order = %+v, want %+v", backend.ops, want)
	}
	if status := service.Status(); status.PendingOps != 0 || status.FailedOps != 0 {
		t.Fatalf("worker left recursive operations unsettled: %+v", status)
	}
}
