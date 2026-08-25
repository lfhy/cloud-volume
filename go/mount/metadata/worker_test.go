// Worker tests exercise journal claim/execution, retry, conflict, and lifecycle.
package metadata

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

func TestWorkerExecutesDueMkdir(t *testing.T) {
	backend := newFakeBackend()
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	inode, err := service.CreateDirectory(rootInode, "dir", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatal(err)
	}
	if backend.objects["/dir/"].Key != "dir/" {
		t.Fatalf("provider mkdir missing: %+v", backend.objects)
	}
	status := service.Status()
	if status.PendingOps != 0 || status.FailedOps != 0 {
		t.Fatalf("worker left operations: %+v", status)
	}
	object, err := service.StatInode(context.Background(), inode)
	if err != nil {
		t.Fatal(err)
	}
	if object.State != StateSynced {
		t.Fatalf("inode state = %d, want synced", object.State)
	}
}

func TestConfirmRemoteUsesWorkerBackendSnapshot(t *testing.T) {
	operationBackend := newFakeBackend()
	operationBackend.objects["/file.txt"] = storageops.ObjectInfo{Key: "file.txt", Size: 3}
	service := newTestService(t, operationBackend)
	if _, err := service.ListPage(context.Background(), rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, err := service.Resolve(rootInode, "file.txt")
	if err != nil {
		t.Fatal(err)
	}
	service.SetBackend(newFakeBackend())
	if err := service.confirmRemote(
		context.Background(), operationBackend, Op{InodeID: inode}, rootInode, "file.txt", true,
	); err != nil {
		t.Fatalf("confirmation used a refreshed backend instead of operation backend: %v", err)
	}
}

type failingBackend struct {
	*fakeBackend
	failNext error
}

func (b *failingBackend) CreateDirectory(ctx context.Context, bucket, prefix, name string) error {
	if b.failNext != nil {
		err := b.failNext
		b.failNext = nil
		return err
	}
	return b.fakeBackend.CreateDirectory(ctx, bucket, prefix, name)
}

func TestWorkerRetriesTransientFailure(t *testing.T) {
	backend := &failingBackend{fakeBackend: newFakeBackend()}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	if _, err := service.CreateDirectory(rootInode, "dir", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatal(err)
	}
	if backend.objects["/dir/"].Key != "dir/" {
		t.Fatalf("provider mkdir missing: %+v", backend.objects)
	}
}

func TestForcedResetWaitsForInFlightWorker(t *testing.T) {
	backend := &blockingCreateBackend{
		fakeBackend: newFakeBackend(), started: make(chan struct{}), release: make(chan struct{}),
	}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	if _, err := service.CreateDirectory(rootInode, "running", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := &Worker{service: service, wake: make(chan struct{}, 1), running: map[uint64]struct{}{}}
	workerDone := make(chan struct{})
	go func() {
		worker.runDueOnce(context.Background())
		close(workerDone)
	}()
	select {
	case <-backend.started:
	case <-time.After(time.Second):
		t.Fatal("worker did not enter provider call")
	}

	resetDone := make(chan ResetResult, 1)
	resetErr := make(chan error, 1)
	go func() {
		result, err := service.Reset(true)
		if err != nil {
			resetErr <- err
			return
		}
		resetDone <- result
	}()
	select {
	case result := <-resetDone:
		t.Fatalf("forced reset completed during provider call: %+v", result)
	case err := <-resetErr:
		t.Fatal(err)
	case <-time.After(50 * time.Millisecond):
	}
	close(backend.release)
	select {
	case <-workerDone:
	case <-time.After(time.Second):
		t.Fatal("worker did not finish after provider release")
	}
	select {
	case result := <-resetDone:
		if !result.Reset {
			t.Fatalf("forced reset result = %+v", result)
		}
	case err := <-resetErr:
		t.Fatal(err)
	case <-time.After(time.Second):
		t.Fatal("forced reset did not finish after worker")
	}
}

type conflictingBackend struct {
	*fakeBackend
	mu         sync.Mutex
	replaced   bool
	remoteETag string
}

func (b *conflictingBackend) HeadObject(ctx context.Context, bucket, key string) (storageops.ObjectInfo, error) {
	if key == "file.txt" {
		b.mu.Lock()
		defer b.mu.Unlock()
		return storageops.ObjectInfo{Key: key, Size: 7, ETag: b.remoteETag, LastModified: "2026-01-02 00:00:00"}, nil
	}
	return b.fakeBackend.HeadObject(ctx, bucket, key)
}

func TestWorkerMarksConflictOnRemoteFingerprintChange(t *testing.T) {
	backend := &conflictingBackend{fakeBackend: newFakeBackend(), remoteETag: "etag-old"}
	backend.objects["/file.txt"] = storageops.ObjectInfo{Key: "file.txt", Size: 3, ETag: "etag-old"}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	if _, err := service.ListPage(context.Background(), rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, err := service.Resolve(rootInode, "file.txt")
	if err != nil {
		t.Fatal(err)
	}
	content, err := service.StageWrite(inode, 1, strings.NewReader("new"), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "file.txt", content, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if service.Status().PendingOps != 1 {
		t.Fatalf("expected pending write op")
	}
	// Simulate another client overwriting the remote object after the local op.
	backend.mu.Lock()
	backend.remoteETag = "etag-remote-wins"
	backend.mu.Unlock()
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err == nil {
		t.Fatal("expected worker drain to report a conflict")
	}
	status := service.Status()
	if status.FailedOps == 0 || status.ConflictInodes == 0 {
		t.Fatalf("conflict not recorded: %+v", status)
	}
}

type stagedWrite struct {
	value string
	read  bool
}

func (s *stagedWrite) Read(p []byte) (int, error) {
	if s.read {
		return 0, io.EOF
	}
	s.read = true
	copy(p, s.value)
	return len(s.value), io.EOF
}

type uploadCaptureBackend struct {
	*fakeBackend
	uploaded      map[string]string
	uploadedBytes map[string][]byte
}

func (b *uploadCaptureBackend) UploadFile(ctx context.Context, bucket, key, localPath, taskID string) error {
	if b.uploaded == nil {
		b.uploaded = map[string]string{}
	}
	b.uploaded[key] = localPath
	// Read the staged file so missing content surfaces as an error instead of
	// a fake success that hides worker bugs.
	data, err := os.ReadFile(localPath)
	if err != nil {
		return err
	}
	if b.uploadedBytes == nil {
		b.uploadedBytes = map[string][]byte{}
	}
	b.uploadedBytes[key] = append([]byte(nil), data...)
	b.objects["/"+key] = storageops.ObjectInfo{Key: key, Size: int64(len(data)), LastModified: "2026-01-01 00:00:00"}
	b.ops = append(b.ops, "upload:"+key)
	return nil
}

func TestWorkerUploadsStagedWriteAndRetiresContent(t *testing.T) {
	backend := &uploadCaptureBackend{fakeBackend: newFakeBackend()}
	backend.objects["/dir/"] = storageops.ObjectInfo{Key: "dir/", IsDir: true}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	if _, err := service.ListPage(context.Background(), rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, ref, err := service.StageWriteForName(rootInode, "uploaded.txt", 1, strings.NewReader("hello"), 5)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "uploaded.txt", ref, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatal(err)
	}
	if backend.objects["/uploaded.txt"].Size != 5 {
		t.Fatalf("provider upload missing: %+v", backend.objects)
	}
	if !bytes.Equal(backend.uploadedBytes["uploaded.txt"], []byte("hello")) {
		t.Fatalf("uploaded content = %q, want hello", backend.uploadedBytes["uploaded.txt"])
	}
	for _, hash := range ref.Chunks {
		if _, err := os.Stat(service.chunkPath(hash)); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("pending chunk %s still exists: %v", hash, err)
		}
	}

	object, err := service.StatInode(context.Background(), inode)
	if err != nil {
		t.Fatal(err)
	}
	if object.State != StateSynced || object.Size != 5 {
		t.Fatalf("unexpected object after upload: %+v", object)
	}
}

// postUploadVerificationBackend simulates a provider that accepted the PUT
// but stopped answering the first confirmation HEAD.
type postUploadVerificationBackend struct {
	*uploadCaptureBackend
	mu    sync.Mutex
	heads int
}

func (b *postUploadVerificationBackend) HeadObject(ctx context.Context, bucket, key string) (storageops.ObjectInfo, error) {
	b.mu.Lock()
	b.heads++
	head := b.heads
	b.mu.Unlock()
	if head == 2 {
		<-ctx.Done()
		return storageops.ObjectInfo{}, ctx.Err()
	}
	return b.fakeBackend.HeadObject(ctx, bucket, key)
}

func TestWorkerReconcilesWriteAfterPostUploadVerificationTimeout(t *testing.T) {
	oldTimeout := workerVerificationTimeout
	workerVerificationTimeout = 10 * time.Millisecond
	defer func() { workerVerificationTimeout = oldTimeout }()

	backend := &postUploadVerificationBackend{
		uploadCaptureBackend: &uploadCaptureBackend{fakeBackend: newFakeBackend()},
	}
	backend.objects["/overwrite.txt"] = storageops.ObjectInfo{
		Key: "overwrite.txt", Size: 3, ETag: "etag-old",
	}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	ctx := context.Background()
	if _, err := service.ListPage(ctx, rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	inode, err := service.Resolve(rootInode, "overwrite.txt")
	if err != nil {
		t.Fatal(err)
	}
	ref, err := service.StageWrite(inode, 1, strings.NewReader("new"), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "overwrite.txt", ref, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}

	worker := &Worker{
		service: service, wake: make(chan struct{}, 1), running: map[uint64]struct{}{},
	}
	claimed := worker.claimDue()
	if len(claimed) != 1 {
		t.Fatalf("claimed operations = %+v, want one write", claimed)
	}
	worker.execute(ctx, claimed[0])
	var afterTimeout Op
	if err := service.store.view(func(tx boltTxT) error {
		var err error
		afterTimeout, err = getOp(tx, claimed[0].Seq)
		return err
	}); err != nil {
		t.Fatal(err)
	}
	if afterTimeout.State != OpStateVerifying {
		t.Fatalf("state after confirmation timeout = %d, want verifying", afterTimeout.State)
	}

	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, afterTimeout.Seq, func(op *Op) {
			op.NextAttemptUnixNano = time.Now().Add(-time.Second).UnixNano()
		})
	}); err != nil {
		t.Fatal(err)
	}
	worker.runDueOnce(ctx)
	if status := service.Status(); status.PendingOps != 0 || status.FailedOps != 0 {
		t.Fatalf("reconciliation left work behind: %+v", status)
	}
	for _, hash := range ref.Chunks {
		if _, statErr := os.Stat(service.chunkPath(hash)); !errors.Is(statErr, os.ErrNotExist) {
			t.Fatalf("chunk %s was not retired after reconciliation: %v", hash, statErr)
		}
	}
}

func TestWorkerRetiresQueuedWriteGenerationsIndependently(t *testing.T) {
	backend := &uploadCaptureBackend{fakeBackend: newFakeBackend()}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	inode, first, err := service.StageWriteForName(rootInode, "rapid.txt", 1, strings.NewReader("first"), 5)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "rapid.txt", first, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	_, second, err := service.StageWriteForName(rootInode, "rapid.txt", 2, strings.NewReader("second"), 6)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "rapid.txt", second, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatal(err)
	}
	if status := service.Status(); status.PendingOps != 0 || status.PendingContent != 0 {
		t.Fatalf("queued writes were not fully retired: %+v", status)
	}
	if !bytes.Equal(backend.uploadedBytes["rapid.txt"], []byte("second")) {
		t.Fatalf("final upload = %q, want second", backend.uploadedBytes["rapid.txt"])
	}
	for _, ref := range []ContentRef{first, second} {
		for _, hash := range ref.Chunks {
			if _, err := os.Stat(service.chunkPath(hash)); !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("generation %d chunk %s still exists: %v", ref.Generation, hash, err)
			}
		}
	}
	if object, err := service.StatInode(context.Background(), inode); err != nil || object.Size != 6 {
		t.Fatalf("final inode = %+v, err=%v", object, err)
	}
}

func TestWorkerRenameWaitsForEarlierLocalWriteGeneration(t *testing.T) {
	backend := &uploadCaptureBackend{fakeBackend: newFakeBackend()}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Hour)
	inode, ref, err := service.StageWriteForName(rootInode, "before.txt", 1, strings.NewReader("contents"), 8)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "before.txt", ref, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(inode, rootInode, "after.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}

	var rename Op
	err = service.store.update(func(tx boltTxT) error {
		for seq := uint64(1); ; seq++ {
			op, err := getOp(tx, seq)
			if errors.Is(err, ErrNotFound) {
				return nil
			}
			if err != nil {
				return err
			}
			if op.Type != OpRename {
				continue
			}
			rename = op
			previous := op
			op.NextAttemptUnixNano = time.Now().Add(-time.Second).UnixNano()
			return putOp(tx, op, previous)
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	if rename.ContentGeneration != ref.Generation {
		t.Fatalf("rename generation = %d, want %d", rename.ContentGeneration, ref.Generation)
	}

	worker := &Worker{service: service, wake: make(chan struct{}, 1), running: map[uint64]struct{}{}}
	if claimed := worker.claimDue(); len(claimed) != 0 {
		t.Fatalf("rename bypassed earlier pending write: %+v", claimed)
	}
}

func TestWorkerRenameOverFileSchedulesRemoteDelete(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/victim.txt"] = storageops.ObjectInfo{Key: "victim.txt", Size: 1}
	backend.objects["/source.txt"] = storageops.ObjectInfo{Key: "source.txt", Size: 2}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	if _, err := service.ListPage(context.Background(), rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	source, err := service.Resolve(rootInode, "source.txt")
	if err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(source, rootInode, "victim.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, ok := backend.objects["/victim.txt"]; !ok || backend.objects["/victim.txt"].Size != 2 {
		t.Fatalf("rename target wrong: %+v", backend.objects)
	}
	if backend.lastOperation("delete") != "victim.txt" {
		t.Fatalf("replaced inode delete missing: %+v", backend.ops)
	}
}

type hardDeleteBackend struct {
	*fakeBackend
	hardDeleteCalls int
}

func (b *hardDeleteBackend) DeleteObjectHard(ctx context.Context, bucket, key string, dir bool, task string) error {
	b.hardDeleteCalls++
	return b.fakeBackend.DeleteObject(ctx, bucket, key, dir, task)
}

func TestWorkerUsesHardDeleteForPermanentIntent(t *testing.T) {
	backend := &hardDeleteBackend{fakeBackend: newFakeBackend()}
	backend.objects["/old.txt"] = storageops.ObjectInfo{Key: "old.txt", Size: 3}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
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
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatal(err)
	}
	if backend.hardDeleteCalls != 1 {
		t.Fatalf("hard delete calls = %d, want 1", backend.hardDeleteCalls)
	}
}

func TestManagerAcquireUsesUnscopedBackendAndRefLifecycle(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	config := fakeConfig("profile-id")
	config.CacheDirectory = t.TempDir()
	first, err := manager.Acquire(config, "bucket")
	if err != nil {
		t.Fatal(err)
	}
	second, err := manager.Acquire(config, "bucket")
	if err != nil {
		t.Fatal(err)
	}
	if first.Service != second.Service {
		t.Fatal("manager did not retain the same service")
	}
	manager.Release(second)
	if services := manager.List(); len(services) != 1 {
		t.Fatalf("service released too early: %+v", services)
	}
	manager.Release(nil)
	manager.Release(first)
	if services := manager.List(); len(services) != 0 {
		t.Fatalf("service not released: %+v", services)
	}
}

func TestManagerAcquireRejectsMissingProfileID(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	config := fakeConfig("")
	if _, err := manager.Acquire(config, "bucket"); err == nil {
		t.Fatal("expected missing profileId error")
	}
}
