// Shared-view tests keep page and mount handles on one pending Desired tree.
package mount

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
	"remote-storage/go/mount/metadata"
)

func TestPageAndMountHandlesSharePendingDesiredView(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	manager := metadata.NewManager(t.TempDir())
	defer manager.RemoveAllForTest()
	config := metadataSharedViewConfig(t)
	mountHandle, err := manager.AcquireWithBackend(config, access.bucket, backend)
	if err != nil {
		t.Fatal(err)
	}
	access.metadataHandle = mountHandle
	t.Cleanup(func() {
		access.metadataHandle = nil
		mountHandle.Release()
	})
	pageHandle, err := manager.AcquireWithBackend(config, access.bucket, backend)
	if err != nil {
		t.Fatal(err)
	}
	defer pageHandle.Release()
	if mountHandle.Service != pageHandle.Service {
		t.Fatal("page and mount acquired different metadata services")
	}
	pageHandle.Service.SetQuietPeriod(time.Hour)
	ctx := context.Background()

	if _, err := pageHandle.Service.CreateDirectoryPath(ctx, "docs", metadata.WriteOptions{Origin: "page"}); err != nil {
		t.Fatal(err)
	}
	assertMetadataMountKeys(t, access, "", "docs/")
	if _, _, err := pageHandle.Service.WritePath(
		ctx, "docs/draft.txt", strings.NewReader("payload"), 7, metadata.WriteOptions{Origin: "page"},
	); err != nil {
		t.Fatal(err)
	}
	assertMetadataMountKeys(t, access, "docs", "docs/draft.txt")
	if err := pageHandle.Service.RenamePath(ctx, "docs/draft.txt", "docs/final.txt", metadata.WriteOptions{Origin: "page"}); err != nil {
		t.Fatal(err)
	}
	assertMetadataMountKeys(t, access, "docs", "docs/final.txt")
	if err := pageHandle.Service.DeletePath(ctx, "docs/final.txt", metadata.WriteOptions{Origin: "page"}); err != nil {
		t.Fatal(err)
	}
	assertMetadataMountKeys(t, access, "docs")
	if _, err := access.statPath(ctx, "docs/final.txt"); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("mount stat after page tombstone = %v, want not exist", err)
	}
}

func metadataSharedViewConfig(t *testing.T) storageconfig.RemoteStorageConfig {
	t.Helper()
	return storageconfig.RemoteStorageConfig{ProfileID: "shared-page-mount", CacheDirectory: t.TempDir()}
}

func assertMetadataMountKeys(t *testing.T, access *bucketAccess, prefix string, wanted ...string) {
	t.Helper()
	items, err := access.listDirectory(context.Background(), prefix)
	if err != nil {
		t.Fatalf("mount list %q: %v", prefix, err)
	}
	keys := make(map[string]bool, len(items))
	for _, item := range items {
		clean := cleanVirtualPath(strings.TrimSuffix(item.Key, "/"))
		if access.overlay.handles(clean) {
			continue
		}
		keys[item.Key] = true
	}
	if len(keys) != len(wanted) {
		t.Fatalf("mount keys for %q = %+v, want %v", prefix, keys, wanted)
	}
	for _, key := range wanted {
		if !keys[key] {
			t.Fatalf("mount keys for %q = %+v, missing %q", prefix, keys, key)
		}
	}
}
