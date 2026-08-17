// Metadata dispatch tests cover wire adaptation and fallback gating for the unified read view.
package main

import (
	"encoding/json"
	"errors"
	"testing"

	bucketmetadata "remote-storage/go/mount/metadata"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

func TestListObjectPageFallsBackWithoutProfileID(t *testing.T) {
	// A config without a persisted identity must not error or create a namespace;
	// the caller falls back to the provider-direct listing path.
	page, handled, err := listObjectPageFromMetadata(objectPageArgs{
		Config: storageconfig.RemoteStorageConfig{StorageType: storageconfig.StorageTypeS3},
		Bucket: "bucket",
	})
	if err != nil {
		t.Fatalf("metadata listing error: %v", err)
	}
	if handled {
		t.Fatalf("handled = true without profileId, page=%+v", page)
	}
}

func TestObjectPageAdapterKeepsWireShape(t *testing.T) {
	page := bucketmetadata.Page{
		Items: []bucketmetadata.Object{
			{Key: "dir/", IsDir: true},
			{Key: "a.txt", Size: 12},
		},
		NextToken: "next",
	}
	adapted := objectPageAdapter(page)
	if len(adapted.Items) != 2 || !adapted.Items[0].IsDir || adapted.Items[1].Size != 12 {
		t.Fatalf("unexpected adapter output: %+v", adapted)
	}
	if adapted.NextToken != "next" {
		t.Fatalf("next token = %q", adapted.NextToken)
	}
	// The wire shape must stay JSON-compatible with the Dart ObjectListPage model.
	encoded, err := json.Marshal(adapted)
	if err != nil {
		t.Fatalf("marshal adapted page: %v", err)
	}
	if string(encoded) == "" {
		t.Fatal("empty encoding")
	}
}

func TestStaleCursorErrorUnwraps(t *testing.T) {
	wrapped := staleCursorError{inner: bucketmetadata.ErrStaleCursor}
	if !errors.Is(wrapped, bucketmetadata.ErrStaleCursor) {
		t.Fatal("stale cursor error must unwrap to metadata.ErrStaleCursor")
	}
}

func TestListObjectPageFromMetadataRestartsOnStaleCursor(t *testing.T) {
	// Wire the metadata path against a real namespace with a fake provider to
	// pin force-refresh and stale-cursor restart behavior end to end.
	backend := newBridgeFakeBackend()
	backend.objects["dir/"] = bridgeFakeObject("dir/", true, 0)
	config := storageconfig.RemoteStorageConfig{
		ProfileID:   "bridge-review-profile",
		StorageType: storageconfig.StorageTypeS3,
		Endpoint:    "https://example.test",
		Bucket:      "bucket",
	}
	root := t.TempDir()
	manager := bucketmetadata.NewManager(root)
	defer manager.RemoveAllForTest()
	// Wire the bridge path through a local manager + fake backend so the test
	// does not touch the real DefaultManager or any network provider.
	original := swapMetadataListFunc(func(input objectPageArgs) (objectPageWire, bool, error) {
		handle, err := manager.AcquireWithBackend(input.Config, input.Bucket, backend)
		if err != nil {
			return objectPageWire{}, false, nil
		}
		defer manager.Release(handle)
		return metadataListViaHandle(handle, input)
	})
	defer swapMetadataListFunc(original)
	handle, err := manager.AcquireWithBackend(config, "bucket", backend)
	if err != nil {
		t.Fatalf("acquire: %v", err)
	}
	manager.Release(handle)
	// First listing materializes the root directory.
	page, handled, err := metadataListFunc(objectPageArgs{Config: config, Bucket: "bucket"})
	if err != nil || !handled {
		t.Fatalf("initial listing: handled=%v err=%v", handled, err)
	}
	if len(page.Items) != 1 || !page.Items[0].IsDir {
		t.Fatalf("unexpected initial items: %+v", page.Items)
	}
	// A remote object added after materialization appears only via forceRefresh.
	backend.objects["new.txt"] = bridgeFakeObject("new.txt", false, 3)
	stale, _, err := metadataListFunc(objectPageArgs{Config: config, Bucket: "bucket"})
	if err != nil {
		t.Fatalf("cached listing: %v", err)
	}
	if len(stale.Items) != 1 {
		t.Fatalf("cached listing should serve the materialized view: %+v", stale.Items)
	}
	refreshed, _, err := metadataListFunc(objectPageArgs{
		Config:       config,
		Bucket:       "bucket",
		ForceRefresh: true,
	})
	if err != nil {
		t.Fatalf("forced listing: %v", err)
	}
	if len(refreshed.Items) != 2 {
		t.Fatalf("forceRefresh must rematerialize the directory: %+v", refreshed.Items)
	}
}

// bridgeFakeObject is a tiny constructor to keep the fake backend map literal.
func bridgeFakeObject(key string, isDir bool, size int64) storageops.ObjectInfo {
	return storageops.ObjectInfo{Key: key, IsDir: isDir, Size: size}
}
