// Stat cache tests keep Finder destination probes on the local-first path.
package mount

import (
	"context"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

type countingHeadBackend struct {
	storageops.Backend
	headCalls atomic.Int32
}

func (b *countingHeadBackend) HeadObject(
	context.Context,
	string,
	string,
) (storageops.ObjectInfo, error) {
	b.headCalls.Add(1)
	return storageops.ObjectInfo{}, os.ErrNotExist
}

func TestStatPathUsesFreshDirectoryListingAsNegativeCache(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := &countingHeadBackend{Backend: access.backend}
	access.backend = backend
	access.cache.storeList("docs", []storageops.ObjectInfo{{Key: "docs/known.txt"}})

	if _, err := access.statPath(context.Background(), "docs/new.txt"); !os.IsNotExist(err) {
		t.Fatalf("stat missing cached child: %v", err)
	}
	if calls := backend.headCalls.Load(); calls != 0 {
		t.Fatalf("remote HeadObject calls = %d, want 0", calls)
	}
}

func TestStatPathKeepsChildrenOfLocalDirectoryOffRemote(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := &countingHeadBackend{Backend: access.backend}
	access.backend = backend
	access.stageLocalDirectory("docs", time.Now())

	if _, err := access.statPath(context.Background(), "docs/new.txt"); !os.IsNotExist(err) {
		t.Fatalf("stat missing local child: %v", err)
	}
	if calls := backend.headCalls.Load(); calls != 0 {
		t.Fatalf("remote HeadObject calls = %d, want 0", calls)
	}
}

func TestRegisterLocalWriteKeepsFileModificationTime(t *testing.T) {
	access := newTestBucketAccess(t)
	localPath := access.cachePathFor("mtime.txt")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(localPath, []byte("data"), 0o644); err != nil {
		t.Fatal(err)
	}
	want := time.Date(2024, time.January, 2, 3, 4, 5, 0, time.UTC)
	if err := os.Chtimes(localPath, want, want); err != nil {
		t.Fatal(err)
	}
	access.registerLocalWrite("mtime.txt", localPath, 4)
	item, ok := access.cache.localFile("mtime.txt")
	wantText := want.Local().Format("2006-01-02 15:04:05")
	if !ok || item.info.LastModified != wantText {
		t.Fatalf("local marker mtime = %+v ok=%t, want %q", item.info, ok, wantText)
	}
}
