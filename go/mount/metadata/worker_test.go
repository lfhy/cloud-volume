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
