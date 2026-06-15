// Overlay bridge tests pin local-first moves from macOS temp overlay paths into the mounted bucket view.
package mount

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestMoveOverlayDirectoryToRemoteStagesLocallyFirst(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	oldVirtualPath := ".TemporaryItems/archive-temp"
	newVirtualPath := "unzipped/folder"

	sourceDir := access.overlay.localPath(oldVirtualPath)
	if err := os.MkdirAll(sourceDir, 0o755); err != nil {
		t.Fatalf("mkdir overlay source: %v", err)
	}
	sourceFile := filepath.Join(sourceDir, "hello.txt")
	if err := os.WriteFile(sourceFile, []byte("hello"), 0o644); err != nil {
		t.Fatalf("write overlay file: %v", err)
	}

	if err := access.moveOverlayPathToRemote(context.Background(), oldVirtualPath, newVirtualPath); err != nil {
		t.Fatalf("moveOverlayPathToRemote: %v", err)
	}

	if _, err := access.overlay.statPath(oldVirtualPath); !os.IsNotExist(err) {
		t.Fatalf("expected overlay source removal, got %v", err)
	}

	dirInfo, ok := access.cache.cachedObject(newVirtualPath)
	if !ok || !dirInfo.IsDir {
		t.Fatalf("expected staged target directory in cache, got ok=%t info=%+v", ok, dirInfo)
	}

	stagedPath := access.cachePathFor("unzipped/folder/hello.txt")
	data, err := os.ReadFile(stagedPath)
	if err != nil {
		t.Fatalf("read staged cache file: %v", err)
	}
	if string(data) != "hello" {
		t.Fatalf("unexpected staged data %q", string(data))
	}

	if _, ok := access.cache.localFile("unzipped/folder/hello.txt"); !ok {
		t.Fatal("expected staged local file marker for moved overlay file")
	}
	if !access.writeback.hasPendingAtOrBelow("unzipped/folder", true) {
		t.Fatal("expected delayed writeback entries for moved overlay directory")
	}
}

func newTestBucketAccess(t *testing.T) *bucketAccess {
	t.Helper()

	root := t.TempDir()
	overlay, err := newLocalMountOverlay(filepath.Join(root, "overlay"))
	if err != nil {
		t.Fatalf("newLocalMountOverlay: %v", err)
	}
	access := &bucketAccess{
		backend:        mountTestBackend{},
		bucket:         "test-bucket",
		sessionRoot:    root,
		cacheRoot:      filepath.Join(root, "cache"),
		stageRoot:      filepath.Join(root, "staging"),
		requestTimeout: time.Second,
		listTTL:        time.Second,
		prefetchTTL:    time.Second,
		cache:          newBucketCache(time.Second, time.Second),
		overlay:        overlay,
	}
	if err := os.MkdirAll(access.cacheRoot, 0o755); err != nil {
		t.Fatalf("mkdir cache root: %v", err)
	}
	if err := os.MkdirAll(access.stageRoot, 0o755); err != nil {
		t.Fatalf("mkdir stage root: %v", err)
	}
	writeback, err := newWritebackQueue(access)
	if err != nil {
		t.Fatalf("newWritebackQueue: %v", err)
	}
	access.writeback = writeback
	t.Cleanup(func() {
		_ = access.close()
	})
	return access
}
