// Metadata tests pin inode identity, pagination, and rename transaction behavior.
package metadata

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

type fakeBackend struct {
	objects map[string]storageops.ObjectInfo
	ops     []string
}

func newFakeBackend() *fakeBackend { return &fakeBackend{objects: map[string]storageops.ObjectInfo{}} }

func (b *fakeBackend) ListObjectsPage(_ context.Context, _, prefix, _ string, _ int32) (storageops.ObjectPage, error) {
	trimmedPrefix := strings.Trim(prefix, "/")
	normalizedPrefix := "/"
	if trimmedPrefix != "" {
		normalizedPrefix += trimmedPrefix + "/"
	}
	items := make([]storageops.ObjectInfo, 0)
	for key, info := range b.objects {
		if key == normalizedPrefix {
			continue
		}
		if !strings.HasPrefix(key, normalizedPrefix) {
			continue
		}
		rel := strings.TrimSuffix(key[len(normalizedPrefix):], "/")
		if rel == "" || strings.Contains(rel, "/") {
			continue
		}
		info.Key = rel
		if strings.HasSuffix(key, "/") {
			info.Key += "/"
			info.IsDir = true
		}
		items = append(items, info)
	}
	sort.Slice(items, func(i, j int) bool { return items[i].Key < items[j].Key })
	return storageops.ObjectPage{Items: items}, nil
}

func (b *fakeBackend) HeadObject(_ context.Context, _, key string) (storageops.ObjectInfo, error) {
	info, ok := b.objects["/"+key]
	if !ok {
		return storageops.ObjectInfo{}, os.ErrNotExist
	}
	info.Key = key
	return info, nil
}

func (b *fakeBackend) CreateDirectory(_ context.Context, _, prefix, name string) error {
	prefix = strings.Trim(prefix, "/")
	full := name
	if prefix != "" {
		full = prefix + "/" + name
	}
	b.objects["/"+full+"/"] = storageops.ObjectInfo{Key: full + "/", IsDir: true}
	b.ops = append(b.ops, "mkdir:"+full)
	return nil
}

func (b *fakeBackend) DeleteObject(_ context.Context, _, key string, isDir bool, _ string) error {
	delete(b.objects, "/"+key)
	if isDir {
		prefix := "/" + strings.TrimSuffix(key, "/") + "/"
		for candidate := range b.objects {
			if strings.HasPrefix(candidate, prefix) {
				delete(b.objects, candidate)
			}
		}
	}
	b.ops = append(b.ops, "delete:"+key)
	return nil
}

func (b *fakeBackend) DeleteObjectHard(ctx context.Context, bucket, key string, dir bool, task string) error {
	return b.DeleteObject(ctx, bucket, key, dir, task)
}

func (b *fakeBackend) RenameObject(_ context.Context, _, key string, _ bool, newName string) error {
	b.ops = append(b.ops, "rename:"+key+":"+newName)
	return nil
}

func (b *fakeBackend) MoveObject(_ context.Context, _, source, target string, _ bool, _ string) error {
	info, ok := b.objects["/"+source]
	if !ok {
		return os.ErrNotExist
	}
	delete(b.objects, "/"+source)
	info.Key = target
	b.objects["/"+target] = info
	b.ops = append(b.ops, "move:"+source+":"+target)
	return nil
}

func (b *fakeBackend) UploadFile(_ context.Context, _, key, localPath, _ string) error {
	size := int64(4)
	if info, err := os.Stat(localPath); err == nil {
		size = info.Size()
	} else if localPath != "" {
		return err
	}
	b.objects["/"+key] = storageops.ObjectInfo{Key: key, Size: size, LastModified: "2026-01-01 00:00:00"}
	b.ops = append(b.ops, "upload:"+key)
	return nil
}

func (b *fakeBackend) lastOperation(kind string) string {
	prefix := kind + ":"
	for index := len(b.ops) - 1; index >= 0; index-- {
		if len(b.ops[index]) > len(prefix) && b.ops[index][:len(prefix)] == prefix {
			return b.ops[index][len(prefix):]
		}
	}
	return ""
}

func newTestService(t *testing.T, backend Backend) *Service {
	t.Helper()
	root := filepath.Join(t.TempDir(), "metadata")
	store, err := OpenStore(Namespace{ID: "test", Root: root, Bucket: "bucket"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	return NewService(store, backend)
}

func TestMaterializeAndListCreatesStableInodes(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/file.txt"] = storageops.ObjectInfo{Key: "file.txt", Size: 3, LastModified: "2026-01-01 00:00:00"}
	service := newTestService(t, backend)
	page, err := service.ListPage(context.Background(), rootInode, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 1 || page.Items[0].Inode == "" {
		t.Fatalf("unexpected page: %+v", page)
	}
	first := page.Items[0].Inode
	page, err = service.ListPage(context.Background(), rootInode, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 1 || page.Items[0].Inode != first {
		t.Fatalf("inode identity changed: %+v", page)
	}
}

func TestRenameMovesOnlyDirentEdges(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/dir/"] = storageops.ObjectInfo{Key: "dir/", IsDir: true}
	backend.objects["/dir/child.txt"] = storageops.ObjectInfo{Key: "dir/child.txt", Size: 1}
	service := newTestService(t, backend)
	if _, err := service.ListPage(context.Background(), rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	dir, err := service.Resolve(rootInode, "dir")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.ListPage(context.Background(), dir, "", 10); err != nil {
		t.Fatal(err)
	}
	child, err := service.Resolve(dir, "child.txt")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(rootInode, "target", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	target, err := service.Resolve(rootInode, "target")
	if err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(dir, target, "renamed", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	childPath, err := service.Path(child)
	if err != nil {
		t.Fatal(err)
	}
	if childPath != "target/renamed/child.txt" {
		t.Fatalf("child path = %q", childPath)
	}
	if _, err := service.Resolve(rootInode, "dir"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("old name still resolves: %v", err)
	}
}

func TestRenameRejectsAncestorCycle(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/a/"] = storageops.ObjectInfo{Key: "a/", IsDir: true}
	backend.objects["/a/b/"] = storageops.ObjectInfo{Key: "a/b/", IsDir: true}
	service := newTestService(t, backend)
	if _, err := service.ListPage(context.Background(), rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	a, _ := service.Resolve(rootInode, "a")
	if _, err := service.ListPage(context.Background(), a, "", 10); err != nil {
		t.Fatal(err)
	}
	b, _ := service.Resolve(a, "b")
	if err := service.Rename(a, b, "inside", WriteOptions{Origin: "test"}); !errors.Is(err, ErrCycle) {
		t.Fatalf("expected cycle, got %v", err)
	}
}

func TestStaleCursorRequiresReload(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/a"] = storageops.ObjectInfo{Key: "a", Size: 1}
	backend.objects["/b"] = storageops.ObjectInfo{Key: "b", Size: 1}
	service := newTestService(t, backend)
	page, err := service.ListPage(context.Background(), rootInode, "", 1)
	if err != nil {
		t.Fatal(err)
	}
	if page.NextToken == "" {
		t.Fatal("expected pagination token")
	}
	// A desired-tree mutation must bump the directory revision so continuing
	// an old snapshot becomes an explicit reload instead of silent divergence.
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "new-dir", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if _, err := service.ListPage(context.Background(), rootInode, page.NextToken, 1); !errors.Is(err, ErrStaleCursor) {
		t.Fatalf("expected stale cursor, got %v", err)
	}
}

func TestReadOnlyRejectsWrites(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetReadOnly(true)
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "dir", WriteOptions{}); !errors.Is(err, ErrReadOnly) {
		t.Fatalf("expected read-only error, got %v", err)
	}
}

func TestResetGuardRequiresForceWithPendingOps(t *testing.T) {
	// Keep the pending op far in the future so a background worker, if any,
	// cannot consume it while the guard is being exercised.
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "pending", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	result, err := service.Reset(false)
	if err != nil {
		t.Fatal(err)
	}
	if result.Reset || !result.Required || result.Pending == 0 {
		t.Fatalf("unexpected reset result: %+v", result)
	}
	result, err = service.Reset(true)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Reset {
		t.Fatalf("forced reset failed: %+v", result)
	}
	if status := service.Status(); status.InodeCount == 0 || status.PendingOps != 0 {
		t.Fatalf("unexpected rebuilt status: %+v", status)
	}
}

func TestProfileIdentityPersistsAcrossSaves(t *testing.T) {
	if got := NamespaceID(fakeConfig("p1"), "bucket"); got != NamespaceID(fakeConfig("p1"), "bucket") {
		t.Fatal("namespace identity is not deterministic")
	}
	if NamespaceID(fakeConfig("p1"), "bucket") == NamespaceID(fakeConfig("p2"), "bucket") {
		t.Fatal("different profiles must not share a namespace")
	}
}

func fakeConfig(profileID string) storageconfig.RemoteStorageConfig {
	return storageconfig.RemoteStorageConfig{ProfileID: profileID, StorageType: "s3", Endpoint: "example", Bucket: "b"}
}

var _ = fmt.Sprintf
