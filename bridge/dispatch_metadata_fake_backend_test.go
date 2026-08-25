// Bridge-local fake backend powers metadata dispatch tests without a provider.
package main

import (
	"context"
	"os"
	"strings"
	"sync"

	bucketmetadata "remote-storage/go/mount/metadata"

	storageops "remote-storage/go/storage"
)

// bridgeFakeBackend is a minimal in-memory metadata.Backend implementation.
type bridgeFakeBackend struct {
	mu              sync.Mutex
	objects         map[string]storageops.ObjectInfo
	hardDeleteCalls int
}

func newBridgeFakeBackend() *bridgeFakeBackend {
	return &bridgeFakeBackend{objects: map[string]storageops.ObjectInfo{}}
}

func (b *bridgeFakeBackend) ListObjectsPage(
	_ context.Context, _, prefix, _ string, _ int32,
) (storageops.ObjectPage, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	// Emulate delimiter-style listing: only direct children of the prefix.
	prefix = strings.Trim(prefix, "/")
	if prefix != "" {
		prefix += "/"
	}
	items := make([]storageops.ObjectInfo, 0, len(b.objects))
	for key, info := range b.objects {
		if !strings.HasPrefix(key, prefix) {
			continue
		}
		rest := strings.TrimPrefix(key, prefix)
		if rest == "" || strings.Contains(strings.TrimSuffix(rest, "/"), "/") {
			continue
		}
		items = append(items, info)
	}
	return storageops.ObjectPage{Items: items}, nil
}

func (b *bridgeFakeBackend) HeadObject(_ context.Context, _, key string) (storageops.ObjectInfo, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	clean := strings.Trim(key, "/")
	if item, ok := b.objects[clean]; ok {
		return item, nil
	}
	if item, ok := b.objects[clean+"/"]; ok {
		return item, nil
	}
	return storageops.ObjectInfo{}, os.ErrNotExist
}

func (b *bridgeFakeBackend) CreateDirectory(_ context.Context, _ string, prefix, name string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	key := joinChildPath(prefix, name)
	b.objects[key+"/"] = storageops.ObjectInfo{Key: key + "/", IsDir: true}
	return nil
}

func (b *bridgeFakeBackend) DeleteObject(_ context.Context, _ string, key string, dir bool, _ string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	clean := strings.Trim(key, "/")
	delete(b.objects, clean)
	delete(b.objects, clean+"/")
	if dir {
		prefix := clean + "/"
		for candidate := range b.objects {
			if strings.HasPrefix(candidate, prefix) {
				delete(b.objects, candidate)
			}
		}
	}
	return nil
}

func (b *bridgeFakeBackend) DeleteObjectHard(ctx context.Context, bucket, key string, dir bool, task string) error {
	b.mu.Lock()
	b.hardDeleteCalls++
	b.mu.Unlock()
	return b.DeleteObject(ctx, bucket, key, dir, task)
}

func (b *bridgeFakeBackend) RenameObject(_ context.Context, _ string, key string, dir bool, name string) error {
	return b.MoveObject(context.Background(), "", key, joinChildPath(parentDirectoryOf(key), name), dir, "")
}

func (b *bridgeFakeBackend) MoveObject(_ context.Context, _ string, source, target string, dir bool, _ string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	source, target = strings.Trim(source, "/"), strings.Trim(target, "/")
	if !dir {
		item, ok := b.objects[source]
		if !ok {
			return os.ErrNotExist
		}
		delete(b.objects, source)
		item.Key = target
		b.objects[target] = item
		return nil
	}
	moved := false
	for candidate, item := range b.objects {
		if candidate != source+"/" && !strings.HasPrefix(candidate, source+"/") {
			continue
		}
		next := target + strings.TrimPrefix(candidate, source)
		delete(b.objects, candidate)
		item.Key = next
		b.objects[next] = item
		moved = true
	}
	if !moved {
		return os.ErrNotExist
	}
	return nil
}

func (b *bridgeFakeBackend) UploadFile(_ context.Context, _ string, key, localPath, _ string) error {
	info, err := os.Stat(localPath)
	if err != nil {
		return err
	}
	b.mu.Lock()
	b.objects[strings.Trim(key, "/")] = storageops.ObjectInfo{Key: strings.Trim(key, "/"), Size: info.Size()}
	b.mu.Unlock()
	return nil
}

// Compile-time interface check.
var _ bucketmetadata.Backend = (*bridgeFakeBackend)(nil)
