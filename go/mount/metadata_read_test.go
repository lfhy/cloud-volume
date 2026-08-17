// Metadata read tests keep mounted views aligned with the persistent inode tree.
package mount

import (
	"context"
	"errors"
	"os"
	"sort"
	"testing"

	storageconfig "remote-storage/go/config"
	"remote-storage/go/mount/metadata"
	storageops "remote-storage/go/storage"
)

type metadataReadTestBackend struct {
	mountTestBackend
	objects map[string]storageops.ObjectInfo
}

func (b *metadataReadTestBackend) ListObjectsPage(
	_ context.Context,
	_ string,
	prefix string,
	_ string,
	_ int32,
) (storageops.ObjectPage, error) {
	parent := cleanVirtualPath(prefix)
	items := make([]storageops.ObjectInfo, 0, len(b.objects))
	for key, item := range b.objects {
		clean := cleanVirtualPath(key)
		if parentVirtualPrefix(clean) != parent {
			continue
		}
		item.Key = clean
		if item.IsDir {
			item.Key = ensureDirSuffix(clean)
		}
		items = append(items, item)
	}
	sort.Slice(items, func(i, j int) bool { return items[i].Key < items[j].Key })
	return storageops.ObjectPage{Items: items}, nil
}

func (b *metadataReadTestBackend) HeadObject(
	_ context.Context,
	_ string,
	key string,
) (storageops.ObjectInfo, error) {
	clean := cleanVirtualPath(key)
	for candidate, item := range b.objects {
		if cleanVirtualPath(candidate) != clean {
			continue
		}
		item.Key = clean
		if item.IsDir {
			item.Key = ensureDirSuffix(clean)
		}
		return item, nil
	}
	return storageops.ObjectInfo{}, os.ErrNotExist
}

type directReadTrapBackend struct{ mountTestBackend }

func (directReadTrapBackend) ListObjectsPage(
	_ context.Context,
	_ string,
	_ string,
	_ string,
	_ int32,
) (storageops.ObjectPage, error) {
	return storageops.ObjectPage{}, errors.New("unexpected direct mount listing")
}

func (directReadTrapBackend) HeadObject(
	_ context.Context,
	_ string,
	_ string,
) (storageops.ObjectInfo, error) {
	return storageops.ObjectInfo{}, errors.New("unexpected direct mount stat")
}

func attachMetadataReadService(
	t *testing.T,
	access *bucketAccess,
	backend metadata.Backend,
) {
	t.Helper()
	manager := metadata.NewManager(t.TempDir())
	config := storageconfig.RemoteStorageConfig{
		ProfileID:      "mount-metadata-read-profile",
		CacheDirectory: t.TempDir(),
	}
	handle, err := manager.AcquireWithBackend(config, access.bucket, backend)
	if err != nil {
		t.Fatal(err)
	}
	access.metadataHandle = handle
	t.Cleanup(func() {
		access.metadataHandle = nil
		handle.Release()
		manager.RemoveAllForTest()
	})
}

func TestMetadataReadMergesLegacyLocalStateWithoutDirectProviderReads(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := &metadataReadTestBackend{objects: map[string]storageops.ObjectInfo{
		"remote.txt": {Key: "remote.txt", Size: 3, LastModified: "2026-08-17 10:00:00"},
		"keep.txt":   {Key: "keep.txt", Size: 7, LastModified: "2026-08-17 10:00:01"},
	}}
	attachMetadataReadService(t, access, backend)
	access.backend = directReadTrapBackend{}

	localPath := createTempFile(t, access.cacheRoot, "draft.txt", "local")
	access.registerLocalWrite("draft.txt", localPath, 5)
	access.cache.markDeleted("remote.txt", false)

	items, err := access.listDirectory(context.Background(), "")
	if err != nil {
		t.Fatalf("list metadata directory: %v", err)
	}
	keys := objectKeys(items)
	if !keys["draft.txt"] || !keys["keep.txt"] || keys["remote.txt"] {
		t.Fatalf("merged metadata list = %+v", items)
	}
	if _, err := access.statPath(context.Background(), "remote.txt"); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("tombstoned metadata object stat error = %v, want not exist", err)
	}
	if _, err := access.readRemoteRange(context.Background(), "remote.txt", 0, 1); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("tombstoned metadata object range error = %v, want not exist", err)
	}
	item, err := access.metadataStat(context.Background(), "keep.txt")
	if err != nil {
		t.Fatalf("metadata stat: %v", err)
	}
	if item.inode == 0 || item.info.Size != 7 {
		t.Fatalf("metadata mount object = %+v", item)
	}
	info, err := access.statPath(context.Background(), "keep.txt")
	if err != nil {
		t.Fatalf("mount stat from metadata: %v", err)
	}
	if info.Size != 7 || info.Key != "keep.txt" {
		t.Fatalf("mount metadata stat = %+v", info)
	}
}

func TestMetadataPollRefreshesPersistentRemoteBase(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := &metadataReadTestBackend{objects: map[string]storageops.ObjectInfo{
		"old.txt": {Key: "old.txt", Size: 1},
	}}
	attachMetadataReadService(t, access, backend)
	access.backend = directReadTrapBackend{}
	if _, err := access.listDirectory(context.Background(), ""); err != nil {
		t.Fatalf("initial metadata list: %v", err)
	}

	backend.objects = map[string]storageops.ObjectInfo{
		"new.txt": {Key: "new.txt", Size: 2},
	}
	refreshed := []storageops.ObjectInfo(nil)
	access.externalDirectoryRefresh = func(_ string, items []storageops.ObjectInfo) error {
		refreshed = cloneObjects(items)
		return nil
	}
	if err := access.pollRemoteDirectory(context.Background(), ""); err != nil {
		t.Fatalf("metadata poll: %v", err)
	}
	if len(refreshed) != 1 || refreshed[0].Key != "new.txt" {
		t.Fatalf("external metadata refresh = %+v", refreshed)
	}
	items, err := access.listDirectory(context.Background(), "")
	if err != nil {
		t.Fatalf("list after metadata poll: %v", err)
	}
	keys := objectKeys(items)
	if !keys["new.txt"] || keys["old.txt"] {
		t.Fatalf("metadata list after poll = %+v", items)
	}
}

func objectKeys(items []storageops.ObjectInfo) map[string]bool {
	keys := make(map[string]bool, len(items))
	for _, item := range items {
		keys[item.Key] = true
	}
	return keys
}
