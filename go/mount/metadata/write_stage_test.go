// Staged write tests pin rollback and restart recovery for unjournaled content.
package metadata

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestWritePathRollsBackFailedStaging(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	_, _, err := service.WritePath(context.Background(), "draft.txt", strings.NewReader("data"), 5, WriteOptions{Origin: "test"})
	if err == nil {
		t.Fatal("declared-size mismatch unexpectedly succeeded")
	}
	if _, err := service.Resolve(rootInode, "draft.txt"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("failed staging left a phantom dirent: %v", err)
	}
	if status := service.Status(); status.InodeCount != 1 || status.PendingContent != 0 || status.PendingOps != 0 {
		t.Fatalf("failed staging left durable state: %+v", status)
	}
}

func TestRestartDropsUnownedStagedWrite(t *testing.T) {
	root := filepath.Join(t.TempDir(), "metadata")
	cacheRoot := t.TempDir()
	namespace := Namespace{ID: "test", Root: root, CacheRoot: cacheRoot, Bucket: "bucket"}
	store, err := OpenStore(namespace)
	if err != nil {
		t.Fatal(err)
	}
	service := NewService(store, newFakeBackend())
	_, ref, err := service.StageWriteForName(rootInode, "draft.txt", 1, strings.NewReader("data"), 4)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := OpenStore(namespace)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	resumed := NewService(reopened, newFakeBackend())
	if _, err := resumed.Resolve(rootInode, "draft.txt"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("restart retained unowned staged inode: %v", err)
	}
	if status := resumed.Status(); status.PendingContent != 0 || status.PendingOps != 0 {
		t.Fatalf("restart retained unowned staged state: %+v", status)
	}
	for _, hash := range ref.Chunks {
		if _, err := os.Stat(resumed.chunkPath(hash)); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("restart retained unowned chunk %s: %v", hash, err)
		}
	}
}

func TestRollbackStagedWriteRemovesNewReservation(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	reservation, err := service.stageWriteForName(rootInode, "draft.txt", 0, strings.NewReader("data"), 4)
	if err != nil {
		t.Fatal(err)
	}
	if err := service.rollbackStagedWrite(reservation); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Resolve(rootInode, "draft.txt"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("journal-failure cleanup retained inode: %v", err)
	}
	if status := service.Status(); status.PendingContent != 0 || status.PendingOps != 0 {
		t.Fatalf("journal-failure cleanup retained state: %+v", status)
	}
}
