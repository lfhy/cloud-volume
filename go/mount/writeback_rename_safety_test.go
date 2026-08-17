// Writeback rename safety tests keep running uploads and local cache moves ordered.
package mount

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type runningRenameTestBackend struct {
	*mutationMoveTestBackend
	uploadStarted chan struct{}
	moveStarted   chan struct{}
	releaseUpload chan struct{}
	releaseMove   chan struct{}
	uploadOnce    sync.Once
	moveOnce      sync.Once
}

func newRunningRenameTestBackend() *runningRenameTestBackend {
	backend := &runningRenameTestBackend{
		mutationMoveTestBackend: newMutationMoveTestBackend(),
		uploadStarted:           make(chan struct{}),
		moveStarted:             make(chan struct{}),
		releaseUpload:           make(chan struct{}),
	}
	backend.files["old.txt"] = true
	return backend
}

func (b *runningRenameTestBackend) UploadFile(
	ctx context.Context,
	_,
	remotePath,
	_ string,
	_ string,
) error {
	b.uploadOnce.Do(func() { close(b.uploadStarted) })
	select {
	case <-b.releaseUpload:
	case <-ctx.Done():
		return ctx.Err()
	}
	b.mu.Lock()
	b.files[strings.Trim(remotePath, "/")] = true
	b.mu.Unlock()
	return nil
}

func (b *runningRenameTestBackend) MoveObject(
	ctx context.Context,
	bucket,
	source,
	target string,
	isDir bool,
	taskID string,
) error {
	b.moveOnce.Do(func() { close(b.moveStarted) })
	if b.releaseMove != nil {
		select {
		case <-b.releaseMove:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return b.mutationMoveTestBackend.MoveObject(ctx, bucket, source, target, isDir, taskID)
}

func TestRenameWaitsForRunningWritebackBeforeMovingRemoteObject(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newRunningRenameTestBackend()
	access.backend = backend
	access.writeback.mu.Lock()
	access.writeback.quiet = time.Hour
	access.writeback.mu.Unlock()

	localPath := createTempFile(t, access.cacheRoot, "old.txt", "pending")
	access.stageLocalWrite("old.txt", localPath, int64(len("pending")))
	access.writeback.mu.Lock()
	taskID := access.writeback.entries["old.txt"].taskID
	access.writeback.mu.Unlock()
	if !access.writeback.triggerTask(taskID) {
		t.Fatal("expected writeback task to start")
	}
	select {
	case <-backend.uploadStarted:
	case <-time.After(time.Second):
		t.Fatal("running upload did not start")
	}

	renameDone := make(chan error, 1)
	go func() {
		renameDone <- access.renamePath(context.Background(), "old.txt", "new.txt", false)
	}()
	select {
	case <-backend.moveStarted:
		t.Fatal("remote move ran before the running upload completed")
	case <-time.After(100 * time.Millisecond):
	}

	close(backend.releaseUpload)
	select {
	case err := <-renameDone:
		if err != nil {
			t.Fatalf("rename after writeback drain: %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("rename did not finish after the upload completed")
	}
	if backend.has("old.txt") || !backend.has("new.txt") {
		t.Fatalf("remote rename left incorrect objects: old=%t new=%t", backend.has("old.txt"), backend.has("new.txt"))
	}
}

func TestWritebackRenameKeepsSourceWhenCacheMoveFails(t *testing.T) {
	access := newTestBucketAccess(t)
	localPath := createTempFile(t, t.TempDir(), "source.txt", "pending")
	access.stageLocalWrite("source.txt", localPath, int64(len("pending")))

	targetPath := access.cachePathFor("target.txt")
	if err := os.WriteFile(filepath.Dir(targetPath), []byte("not a directory"), 0o600); err != nil {
		t.Fatalf("block target cache parent: %v", err)
	}
	if renamed, err := access.writeback.rename("source.txt", "target.txt", false); err == nil || renamed {
		t.Fatalf("cache move failure was accepted: renamed=%t err=%v", renamed, err)
	}
	if access.writeback.entries["source.txt"] == nil || access.writeback.entries["target.txt"] != nil {
		t.Fatalf("queue changed after failed cache move: %+v", access.writeback.entries)
	}
	if _, err := os.Stat(localPath); err != nil {
		t.Fatalf("source bytes were removed after failed cache move: %v", err)
	}
	if _, ok := access.cache.localFile("source.txt"); !ok {
		t.Fatal("source cache marker was removed after failed cache move")
	}
}

func TestRenameGatesConcurrentDirectoryCreateAndDelete(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newRunningRenameTestBackend()
	backend.releaseMove = make(chan struct{})
	access.backend = backend

	renameDone := make(chan error, 1)
	go func() {
		renameDone <- access.renamePath(context.Background(), "old.txt", "new.txt", false)
	}()
	select {
	case <-backend.moveStarted:
	case <-time.After(time.Second):
		t.Fatal("remote move did not start")
	}

	createDone := make(chan error, 1)
	deleteDone := make(chan error, 1)
	go func() { createDone <- access.createDirectory(context.Background(), "old.txt/child") }()
	go func() { deleteDone <- access.deletePath(context.Background(), "old.txt", false) }()
	select {
	case err := <-createDone:
		t.Fatalf("directory create bypassed rename gate: %v", err)
	case err := <-deleteDone:
		t.Fatalf("delete bypassed rename gate: %v", err)
	case <-time.After(100 * time.Millisecond):
	}

	close(backend.releaseMove)
	select {
	case err := <-renameDone:
		if err != nil {
			t.Fatalf("rename: %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("rename did not finish")
	}
	for name, done := range map[string]chan error{"create": createDone, "delete": deleteDone} {
		select {
		case err := <-done:
			if err != nil {
				t.Fatalf("%s after rename: %v", name, err)
			}
		case <-time.After(time.Second):
			t.Fatalf("%s did not resume after rename", name)
		}
	}
}
