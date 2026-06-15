//go:build windows && cgo

// Cloud Files cached-read tests keep hydration from re-reading sync-root placeholders.
package mount

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	s3ops "remote-storage/go/s3"
)

func TestReadCachedRangeClearsSyncRootLocalMarker(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	virtualPath := "docs/draft.txt"
	syncRoot, err := windowsCloudFilesRootPath()
	if err != nil {
		t.Fatalf("windowsCloudFilesRootPath: %v", err)
	}
	placeholderPath := filepath.Join(syncRoot, "test-sync-root", "docs", "draft.txt")
	access.cache.storeLocalFile(virtualPath, placeholderPath, s3ops.ObjectInfo{
		Key:          virtualPath,
		Size:         6,
		LastModified: "2026-05-30 22:00:00",
		IsDir:        false,
	})

	cachePath := access.cachePathFor(virtualPath)
	if err := os.MkdirAll(filepath.Dir(cachePath), 0o755); err != nil {
		t.Fatalf("mkdir cache path: %v", err)
	}
	if err := os.WriteFile(cachePath, []byte("remote"), 0o644); err != nil {
		t.Fatalf("write cache file: %v", err)
	}
	info, err := os.Stat(cachePath)
	if err != nil {
		t.Fatalf("stat cache file: %v", err)
	}
	access.cache.storeObject(virtualPath, s3ops.ObjectInfo{
		Key:          virtualPath,
		Size:         info.Size(),
		LastModified: info.ModTime().Format("2006-01-02 15:04:05"),
		IsDir:        false,
	})

	data, err := access.readCachedRange(context.Background(), virtualPath, 0, 6)
	if err != nil {
		t.Fatalf("readCachedRange: %v", err)
	}
	if string(data) != "remote" {
		t.Fatalf("expected cache-backed read, got %q", string(data))
	}
	item, ok := access.cache.localFile(virtualPath)
	if ok && item.localPath == placeholderPath {
		t.Fatal("expected sync-root local marker to be cleared before cached hydration read")
	}
}
