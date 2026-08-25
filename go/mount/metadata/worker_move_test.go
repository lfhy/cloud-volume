// Move recovery tests exercise immutable provider snapshots across local edits.
package metadata

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

func TestMoveConfirmationKeepsFrozenTargetAfterLaterRename(t *testing.T) {
	backend := &moveConfirmationFailureBackend{
		fakeBackend: newFakeBackend(), failTargetHead: true, failTargetKey: "middle.txt",
	}
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
	if err := service.Rename(inode, rootInode, "middle.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := newManualWorker(service)
	first := claimSingleMove(t, worker)
	worker.execute(ctx, first)
	afterFirst := journalOp(t, service, first.Seq)
	if !afterFirst.MoveApplied || afterFirst.State != OpStatePending || afterFirst.MoveSource != "old.txt" || afterFirst.MoveTarget != "middle.txt" {
		t.Fatalf("first move snapshot = %+v", afterFirst)
	}
	if moves := backend.moveCount(); moves != 1 {
		t.Fatalf("move count after failed confirmation = %d, want 1", moves)
	}
	if err := service.Rename(inode, rootInode, "final.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	forceOpDue(t, service, first.Seq)
	worker.runDueOnce(ctx)
	worker.runDueOnce(ctx)
	if moves := backend.moveCount(); moves != 2 {
		t.Fatalf("remote move count = %d, want old->middle then middle->final", moves)
	}
	if _, exists := backend.objects["/middle.txt"]; exists {
		t.Fatalf("frozen confirmation did not allow later move: %+v", backend.objects)
	}
	if _, exists := backend.objects["/final.txt"]; !exists {
		t.Fatalf("later rename did not reach final target: %+v", backend.objects)
	}
}

func TestLocalOnlyMoveConfirmationKeepsFrozenTargetAfterLaterRename(t *testing.T) {
	backend := &moveConfirmationFailureBackend{
		fakeBackend: newFakeBackend(), failTargetHead: true, failTargetKey: "middle.txt",
	}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	ctx := context.Background()
	inode, _, err := service.WritePath(
		ctx, "old.txt", strings.NewReader("new"), 3, WriteOptions{Origin: "test"},
	)
	if err != nil {
		t.Fatal(err)
	}
	firstWrite := journalOp(t, service, 1)
	markOpAppliedForTest(t, service, firstWrite.Seq)
	if err := service.Rename(inode, rootInode, "middle.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := newManualWorker(service)
	first := claimSingleMove(t, worker)
	worker.execute(ctx, first)
	afterFirst := journalOp(t, service, first.Seq)
	if !afterFirst.MoveApplied || afterFirst.State != OpStatePending || afterFirst.MoveSource != "" || afterFirst.MoveTarget != "middle.txt" {
		t.Fatalf("local-only move snapshot = %+v", afterFirst)
	}
	if err := service.Rename(inode, rootInode, "final.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	forceOpDue(t, service, first.Seq)
	worker.runDueOnce(ctx)
	worker.runDueOnce(ctx)
	if uploads := countWorkerOperation(backend.ops, "upload:middle.txt"); uploads != 1 {
		t.Fatalf("local-only rename upload count = %d, ops=%+v", uploads, backend.ops)
	}
	if moves := countWorkerOperation(backend.ops, "move:middle.txt:final.txt"); moves != 1 {
		t.Fatalf("later local-only move count = %d, ops=%+v", moves, backend.ops)
	}
}

func TestMoveReconcilesGenericProviderNotFoundAfterApply(t *testing.T) {
	backend := &moveReportsNotFoundAfterApply{fakeBackend: newFakeBackend()}
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
	worker := newManualWorker(service)
	op := claimSingleMove(t, worker)
	worker.execute(ctx, op)
	after := journalOp(t, service, op.Seq)
	if after.State != OpStateApplied || !after.MoveApplied {
		t.Fatalf("generic provider result did not reconcile applied move: %+v", after)
	}
	if moves := countWorkerOperation(backend.ops, "move:old.txt:new.txt"); moves != 1 {
		t.Fatalf("remote move count = %d, ops=%+v", moves, backend.ops)
	}
}

func TestMissingDirectoryMoveDoesNotBecomeApplied(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/old/"] = storageops.ObjectInfo{Key: "old/", IsDir: true, ETag: "etag-old-dir"}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	ctx := context.Background()
	if _, err := service.ListPage(ctx, rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, err := service.Resolve(rootInode, "old")
	if err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(inode, rootInode, "new", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	delete(backend.objects, "/old/")
	worker := newManualWorker(service)
	op := claimSingleMove(t, worker)
	worker.execute(ctx, op)
	after := journalOp(t, service, op.Seq)
	if after.MoveApplied || after.State != OpStatePending {
		t.Fatalf("missing source and target directory was treated as applied: %+v", after)
	}
}

func TestDirectoryMoveConfirmsExplicitMarkerWithoutChildren(t *testing.T) {
	backend := &directoryMarkerMoveBackend{fakeBackend: newFakeBackend()}
	backend.objects["/old/"] = storageops.ObjectInfo{Key: "old/", IsDir: true, ETag: "etag-old-dir"}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	ctx := context.Background()
	if _, err := service.ListPage(ctx, rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, err := service.Resolve(rootInode, "old")
	if err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(inode, rootInode, "new", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := newManualWorker(service)
	op := claimSingleMove(t, worker)
	worker.execute(ctx, op)
	after := journalOp(t, service, op.Seq)
	if after.State != OpStateApplied || !after.MoveApplied {
		t.Fatalf("explicit directory marker was not confirmed: %+v", after)
	}
}

type moveReportsNotFoundAfterApply struct {
	*fakeBackend
	reported bool
}

type directoryMarkerMoveBackend struct{ *fakeBackend }

func (b *directoryMarkerMoveBackend) MoveObject(
	_ context.Context, _ string, source, target string, _ bool, _ string,
) error {
	sourceKey := "/" + strings.Trim(source, "/") + "/"
	info, ok := b.objects[sourceKey]
	if !ok {
		return errors.New("directory source missing")
	}
	delete(b.objects, sourceKey)
	targetKey := "/" + strings.Trim(target, "/") + "/"
	info.Key = strings.Trim(target, "/") + "/"
	b.objects[targetKey] = info
	b.ops = append(b.ops, "move:"+source+":"+target)
	return nil
}

func (b *moveReportsNotFoundAfterApply) MoveObject(
	ctx context.Context, bucket, source, target string, isDirectory bool, taskID string,
) error {
	if err := b.fakeBackend.MoveObject(ctx, bucket, source, target, isDirectory, taskID); err != nil {
		return err
	}
	if !b.reported {
		b.reported = true
		return errors.New("webdav move: 404 Not Found")
	}
	return nil
}

func newManualWorker(service *Service) *Worker {
	return &Worker{service: service, wake: make(chan struct{}, 1), running: map[uint64]struct{}{}}
}

func claimSingleMove(t *testing.T, worker *Worker) Op {
	t.Helper()
	claimed := worker.claimDue()
	if len(claimed) != 1 || claimed[0].Type != OpRename {
		t.Fatalf("claimed operations = %+v, want one rename", claimed)
	}
	return claimed[0]
}

func journalOp(t *testing.T, service *Service, seq uint64) Op {
	t.Helper()
	var op Op
	if err := service.store.view(func(tx boltTxT) error {
		var err error
		op, err = getOp(tx, seq)
		return err
	}); err != nil {
		t.Fatal(err)
	}
	return op
}

func forceOpDue(t *testing.T, service *Service, seq uint64) {
	t.Helper()
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, seq, func(op *Op) {
			op.NextAttemptUnixNano = time.Now().Add(-time.Second).UnixNano()
		})
	}); err != nil {
		t.Fatal(err)
	}
}

func markOpAppliedForTest(t *testing.T, service *Service, seq uint64) {
	t.Helper()
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, seq, func(op *Op) { op.State = OpStateApplied })
	}); err != nil {
		t.Fatal(err)
	}
}

func countWorkerOperation(ops []string, wanted string) int {
	count := 0
	for _, operation := range ops {
		if operation == wanted {
			count++
		}
	}
	return count
}
