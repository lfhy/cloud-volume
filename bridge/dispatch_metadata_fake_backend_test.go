// Bridge-local fake backend powers metadata dispatch tests without a provider.
package main

import (
	"context"
	"errors"
	"strings"
	"sync"

	bucketmetadata "remote-storage/go/mount/metadata"

	storageops "remote-storage/go/storage"
)

// bridgeFakeBackend is a minimal in-memory metadata.Backend implementation.
type bridgeFakeBackend struct {
	mu      sync.Mutex
	objects map[string]storageops.ObjectInfo
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
	items := make([]storageops.ObjectInfo, 0, len(b.objects))
	for key, info := range b.objects {
		rest := strings.TrimPrefix(key, prefix)
		if rest == "" || strings.Contains(strings.TrimSuffix(rest, "/"), "/") {
			continue
		}
		items = append(items, info)
	}
	return storageops.ObjectPage{Items: items}, nil
}

func (b *bridgeFakeBackend) HeadObject(_ context.Context, _, _ string) (storageops.ObjectInfo, error) {
	return storageops.ObjectInfo{}, errors.New("not found")
}

func (b *bridgeFakeBackend) CreateDirectory(context.Context, string, string, string) error {
	return nil
}

func (b *bridgeFakeBackend) DeleteObject(context.Context, string, string, bool, string) error {
	return nil
}

func (b *bridgeFakeBackend) DeleteObjectHard(context.Context, string, string, bool, string) error {
	return nil
}

func (b *bridgeFakeBackend) RenameObject(context.Context, string, string, bool, string) error {
	return nil
}

func (b *bridgeFakeBackend) MoveObject(context.Context, string, string, string, bool, string) error {
	return nil
}

func (b *bridgeFakeBackend) UploadFile(context.Context, string, string, string, string) error {
	return nil
}

// Compile-time interface check.
var _ bucketmetadata.Backend = (*bridgeFakeBackend)(nil)
