// Mounted object page tests pin merged local-first paging and ordering for Flutter browsing.
package mount

import (
	"os"
	"path/filepath"
	"testing"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type mountedListTestBackend struct{}

func (mountedListTestBackend) Initialize(*mountSession) error       { return nil }
func (mountedListTestBackend) Start(*mountSession) error            { return nil }
func (mountedListTestBackend) Stop(*mountSession) error             { return nil }
func (mountedListTestBackend) IsActive(*mountSession) (bool, error) { return true, nil }
func (mountedListTestBackend) CleanupStale(*mountSession) error     { return nil }

func TestPaginateObjectInfos(t *testing.T) {
	t.Parallel()

	items := []s3ops.ObjectInfo{
		{Key: "a/", IsDir: true},
		{Key: "b.txt", IsDir: false},
		{Key: "c.txt", IsDir: false},
	}
	page := paginateObjectInfos(items, "", 2)
	if len(page.Items) != 2 || page.NextToken != "2" {
		t.Fatalf("unexpected first page: %+v", page)
	}

	page = paginateObjectInfos(items, page.NextToken, 2)
	if len(page.Items) != 1 || page.Items[0].Key != "c.txt" || page.NextToken != "" {
		t.Fatalf("unexpected second page: %+v", page)
	}
}

func TestListMountedObjectPageIncludesPendingLocalFiles(t *testing.T) {
	access := newTestBucketAccess(t)
	cachePath := filepath.Join(access.cacheRoot, "drafts", "c.zip")
	if err := ensureTestLocalFile(cachePath, []byte("payload")); err != nil {
		t.Fatalf("write local file: %v", err)
	}
	access.registerLocalWrite("drafts/c.zip", cachePath, 7)
	access.cache.storeList("drafts", nil)

	session := &mountSession{
		config: storageconfig.RemoteStorageConfig{
			Bucket:           "test-bucket",
			WindowsMountMode: storageconfig.WindowsMountModeCloudFilesCached,
		}.Normalized(),
		bucket:  "test-bucket",
		access:  access,
		backend: mountedListTestBackend{},
		mounted: true,
	}

	previous := globalManager.session
	globalManager.session = session
	defer func() { globalManager.session = previous }()

	page, handled, err := ListMountedObjectPage(
		session.config,
		"test-bucket",
		"drafts",
		"",
		50,
	)
	if err != nil {
		t.Fatalf("ListMountedObjectPage: %v", err)
	}
	if !handled {
		t.Fatal("expected mounted page to be handled")
	}
	if len(page.Items) != 1 || page.Items[0].Key != "drafts/c.zip" {
		t.Fatalf("unexpected mounted items: %+v", page.Items)
	}
}

func ensureTestLocalFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}
