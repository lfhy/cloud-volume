// Bucket cache tests pin the local metadata overlay behavior used by delayed writeback.
package mount

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	s3ops "remote-storage/go/s3"
)

func TestBucketCacheMergeLocalEntriesAndTombstones(t *testing.T) {
	t.Parallel()

	cache := newBucketCache(time.Minute, time.Minute)
	cache.storeLocalDirectory("docs", s3ops.ObjectInfo{IsDir: true})
	reportPath := createTempFile(t, t.TempDir(), "report.txt", "content")
	cache.storeLocalFile("docs/report.txt", reportPath, s3ops.ObjectInfo{
		Size:  42,
		IsDir: false,
	})

	items := cache.mergeLocalFiles("", []s3ops.ObjectInfo{
		{Key: "docs/", IsDir: true},
		{Key: "old.txt", IsDir: false},
	})
	if len(items) != 2 {
		t.Fatalf("expected 2 merged root items, got %d", len(items))
	}

	cache.markDeleted("old.txt", false)
	items = cache.mergeLocalFiles("", []s3ops.ObjectInfo{
		{Key: "docs/", IsDir: true},
		{Key: "old.txt", IsDir: false},
	})
	for _, item := range items {
		if item.Key == "old.txt" {
			t.Fatal("expected deleted remote item to be hidden by tombstone")
		}
	}

	childItems := cache.mergeLocalFiles("docs", nil)
	if len(childItems) != 1 || childItems[0].Key != "docs/report.txt" {
		t.Fatalf("unexpected child items: %+v", childItems)
	}
}

func TestBucketCacheRenameLocalTree(t *testing.T) {
	t.Parallel()

	cache := newBucketCache(time.Minute, time.Minute)
	root := t.TempDir()
	cachePath := pathForVirtualKey(root, "alpha/note.txt")
	if err := copyFile(cachePath, createTempFile(t, root, "seed.txt", "hello")); err != nil {
		t.Fatalf("seed cache file: %v", err)
	}
	cache.storeLocalDirectory("alpha", s3ops.ObjectInfo{IsDir: true})
	cache.storeLocalFile("alpha/note.txt", cachePath, s3ops.ObjectInfo{
		Size:  5,
		IsDir: false,
	})

	if err := cache.renameLocalFile("alpha", "beta", true, root); err != nil {
		t.Fatalf("rename local directory cache: %v", err)
	}

	if _, ok := cache.localFile("alpha/note.txt"); ok {
		t.Fatal("expected old local file key to be removed")
	}
	item, ok := cache.localFile("beta/note.txt")
	if !ok {
		t.Fatal("expected renamed local file entry to exist")
	}
	if item.info.Key != "beta/note.txt" {
		t.Fatalf("unexpected renamed key: %q", item.info.Key)
	}
}

func TestPathForVirtualKeyUsesStableHashedLayout(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	first := pathForVirtualKey(root, "alpha/note.txt")
	second := pathForVirtualKey(root, "alpha/note.txt")
	other := pathForVirtualKey(root, "alpha/other.txt")

	if first != second {
		t.Fatalf("expected stable path, got %q and %q", first, second)
	}
	if first == other {
		t.Fatalf("expected distinct hashed paths, got %q", first)
	}
	if filepath.Dir(first) == root {
		t.Fatalf("expected sharded subdirectory under root, got %q", first)
	}
}

func createTempFile(t *testing.T, root, name, body string) string {
	t.Helper()

	path := filepath.Join(root, name)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir temp file dir: %v", err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatalf("write temp file: %v", err)
	}
	return path
}
