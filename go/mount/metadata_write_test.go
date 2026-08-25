// Metadata mount-write tests pin the single journal-owned mutation path.
package mount

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"

	storageconfig "remote-storage/go/config"
	"remote-storage/go/mount/metadata"
	storageops "remote-storage/go/storage"
)

type metadataMountWriteBackend struct {
	mu                         sync.Mutex
	objects                    map[string]storageops.ObjectInfo
	rejectUnknownDirectoryList bool
	listPrefixes               []string
}

func newMetadataMountWriteBackend() *metadataMountWriteBackend {
	return &metadataMountWriteBackend{objects: map[string]storageops.ObjectInfo{}}
}

func (b *metadataMountWriteBackend) ListObjectsPage(
	_ context.Context, _ string, prefix, _ string, _ int32,
) (storageops.ObjectPage, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	parent := strings.Trim(prefix, "/")
	b.listPrefixes = append(b.listPrefixes, parent)
	if b.rejectUnknownDirectoryList && parent != "" {
		if _, ok := b.objects[parent+"/"]; !ok {
			return storageops.ObjectPage{}, os.ErrNotExist
		}
	}
	items := make([]storageops.ObjectInfo, 0)
	for key, object := range b.objects {
		clean := strings.TrimSuffix(key, "/")
		if parentVirtualPrefix(clean) != parent {
			continue
		}
		object.Key = strings.TrimPrefix(key, strings.TrimSuffix(parent, "/")+"/")
		if parent == "" {
			object.Key = key
		}
		items = append(items, object)
	}
	sort.Slice(items, func(i, j int) bool { return items[i].Key < items[j].Key })
	return storageops.ObjectPage{Items: items}, nil
}

func (b *metadataMountWriteBackend) HeadObject(_ context.Context, _ string, key string) (storageops.ObjectInfo, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	clean := strings.Trim(key, "/")
	if object, ok := b.objects[clean]; ok {
		object.Key = clean
		return object, nil
	}
	if object, ok := b.objects[clean+"/"]; ok {
		object.Key = clean + "/"
		return object, nil
	}
	return storageops.ObjectInfo{}, os.ErrNotExist
}

func (b *metadataMountWriteBackend) CreateDirectory(_ context.Context, _ string, prefix, name string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	key := strings.Trim(strings.Trim(prefix, "/")+"/"+strings.Trim(name, "/"), "/")
	b.objects[key+"/"] = storageops.ObjectInfo{Key: key + "/", IsDir: true}
	return nil
}

func (b *metadataMountWriteBackend) DeleteObject(_ context.Context, _ string, key string, isDir bool, _ string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	clean := strings.Trim(key, "/")
	delete(b.objects, clean)
	delete(b.objects, clean+"/")
	if isDir {
		for candidate := range b.objects {
			if strings.HasPrefix(candidate, clean+"/") {
				delete(b.objects, candidate)
			}
		}
	}
	return nil
}

func (b *metadataMountWriteBackend) DeleteObjectHard(ctx context.Context, bucket, key string, dir bool, task string) error {
	return b.DeleteObject(ctx, bucket, key, dir, task)
}

func (b *metadataMountWriteBackend) RenameObject(_ context.Context, _ string, key string, isDir bool, newName string) error {
	return b.MoveObject(context.Background(), "", key, joinVirtualPath(parentVirtualPrefix(key), newName), isDir, "")
}

func (b *metadataMountWriteBackend) MoveObject(_ context.Context, _ string, source, target string, isDir bool, _ string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	source, target = strings.Trim(source, "/"), strings.Trim(target, "/")
	if !isDir {
		object, ok := b.objects[source]
		if !ok {
			return os.ErrNotExist
		}
		delete(b.objects, source)
		object.Key = target
		b.objects[target] = object
		return nil
	}
	moved := false
	for candidate, object := range b.objects {
		if candidate != source+"/" && !strings.HasPrefix(candidate, source+"/") {
			continue
		}
		next := target + strings.TrimPrefix(candidate, source)
		delete(b.objects, candidate)
		object.Key = next
		b.objects[next] = object
		moved = true
	}
	if !moved {
		return os.ErrNotExist
	}
	return nil
}

func (b *metadataMountWriteBackend) UploadFile(_ context.Context, _ string, key, localPath, _ string) error {
	file, err := os.Open(localPath)
	if err != nil {
		return err
	}
	defer file.Close()
	data, err := io.ReadAll(file)
	if err != nil {
		return err
	}
	b.mu.Lock()
	b.objects[strings.Trim(key, "/")] = storageops.ObjectInfo{Key: strings.Trim(key, "/"), Size: int64(len(data))}
	b.mu.Unlock()
	return nil
}

func attachMetadataWriteService(t *testing.T, access *bucketAccess, backend metadata.Backend) (*metadata.Manager, *metadata.AcquireHandle) {
	t.Helper()
	manager := metadata.NewManager(t.TempDir())
	config := storageconfig.RemoteStorageConfig{ProfileID: "mount-metadata-write-profile", CacheDirectory: t.TempDir(), WritebackQuietSeconds: 1}
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
	return manager, handle
}

func TestMetadataMountWritesUseJournalInsteadOfLegacyQueues(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	manager, _ := attachMetadataWriteService(t, access, backend)
	ctx := context.Background()

	if err := access.createDirectory(ctx, "docs"); err != nil {
		t.Fatal(err)
	}
	localPath := createTempFile(t, access.cacheRoot, "draft.txt", "payload")
	if err := access.stageLocalWrite("docs/draft.txt", localPath, int64(len("payload"))); err != nil {
		t.Fatal(err)
	}
	if access.writeback.hasPendingAtOrBelow("docs", true) {
		t.Fatal("metadata write was also enqueued in legacy writeback")
	}
	if err := access.renamePath(ctx, "docs/draft.txt", "docs/renamed.txt", false); err != nil {
		t.Fatal(err)
	}
	items, err := access.listDirectory(ctx, "docs")
	if err != nil {
		t.Fatal(err)
	}
	keys := objectKeys(items)
	if !keys["docs/renamed.txt"] || keys["docs/draft.txt"] {
		t.Fatalf("mount Desired view after rename = %+v", items)
	}
	if inode, ok := access.metadataOIDForVisiblePath(ctx, "docs/renamed.txt"); !ok || inode == 0 {
		t.Fatalf("pending metadata draft did not receive an OID: inode=%d ok=%t", inode, ok)
	}

	if err := manager.DrainAll(ctx); err != nil {
		t.Fatal(err)
	}
	backend.mu.Lock()
	_, oldExists := backend.objects["docs/draft.txt"]
	remote, newExists := backend.objects["docs/renamed.txt"]
	backend.mu.Unlock()
	if oldExists || !newExists || remote.Size != int64(len("payload")) {
		t.Fatalf("remote journal convergence old=%t new=%t object=%+v", oldExists, newExists, remote)
	}

	if err := access.deletePath(ctx, "docs/renamed.txt", false); err != nil {
		t.Fatal(err)
	}
	if err := manager.DrainAll(ctx); err != nil {
		t.Fatal(err)
	}
	backend.mu.Lock()
	_, exists := backend.objects["docs/renamed.txt"]
	backend.mu.Unlock()
	if exists {
		t.Fatal("metadata delete did not remove the remote object")
	}
}

func TestMetadataQueuedRenameAcceptsAlreadyMovedCloudFilesSource(t *testing.T) {
	// Cloud Files reports rename completion after Explorer has physically moved
	// the sync-root file, so the metadata path must only rebind its marker.
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	manager, _ := attachMetadataWriteService(t, access, backend)
	ctx := context.Background()
	oldPath := createTempFile(t, access.sessionRoot, "old.txt", "payload")
	newPath := filepath.Join(access.sessionRoot, "new.txt")
	if err := access.stageLocalWrite("old.txt", oldPath, int64(len("payload"))); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(oldPath, newPath); err != nil {
		t.Fatalf("simulate Explorer rename: %v", err)
	}
	if err := access.enqueueRenamePath("old.txt", "new.txt", oldPath, newPath, false); err != nil {
		t.Fatalf("metadata queued rename: %v", err)
	}
	marker, ok := access.cache.localFile("new.txt")
	if !ok || marker.localPath != newPath {
		t.Fatalf("renamed local marker = %+v ok=%t, want new path %q", marker, ok, newPath)
	}
	if _, ok := access.cache.localFile("old.txt"); ok {
		t.Fatal("old local marker survived Cloud Files rename")
	}
	if err := manager.DrainAll(ctx); err != nil {
		t.Fatal(err)
	}
	backend.mu.Lock()
	_, oldExists := backend.objects["old.txt"]
	_, newExists := backend.objects["new.txt"]
	backend.mu.Unlock()
	if oldExists || !newExists {
		t.Fatalf("remote journal convergence old=%t new=%t", oldExists, newExists)
	}
}
