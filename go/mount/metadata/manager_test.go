// Manager tests keep namespace sharing and root-scoped provider reads stable.
package metadata

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

func TestManagerRegistryReusesOneManagerForItsRuntimeRoot(t *testing.T) {
	var registry managerRegistry
	base := filepath.Join(t.TempDir(), "metadata")
	first, err := registry.acquire(base)
	if err != nil {
		t.Fatal(err)
	}
	second, err := registry.acquire(base)
	if err != nil {
		t.Fatal(err)
	}
	if first != second {
		t.Fatal("registry returned different managers for the same runtime root")
	}
	if _, err := registry.acquire(filepath.Join(t.TempDir(), "metadata")); err == nil {
		t.Fatal("registry accepted a changed runtime root")
	}
}

func TestManagerAcquirePreservesRootPrefixScope(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := fakeConfig("scoped-profile")
	config.RootPrefix = "account/view"
	config.CacheDirectory = t.TempDir()

	handle, err := manager.Acquire(config, "bucket")
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Release(handle)
	scoped, ok := handle.Service.Backend().(interface{ Root() string })
	if !ok {
		t.Fatal("metadata backend lost the configured root scope")
	}
	if got := scoped.Root(); got != "account/view" {
		t.Fatalf("scoped backend root = %q, want account/view", got)
	}
}

func TestMaterializeDirectoryUsesRootPrefixInProviderRequest(t *testing.T) {
	paths := make(chan string, 1)
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != "PROPFIND" {
			http.Error(writer, "expected PROPFIND", http.StatusMethodNotAllowed)
			return
		}
		select {
		case paths <- request.URL.EscapedPath():
		default:
		}
		writer.Header().Set("Content-Type", "application/xml")
		writer.WriteHeader(http.StatusMultiStatus)
		_, _ = writer.Write([]byte(`<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response><D:href>/archive/2026/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype><D:getcontentlength>0</D:getcontentlength></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
  <D:response><D:href>/archive/2026/report.txt</D:href><D:propstat><D:prop><D:resourcetype></D:resourcetype><D:getcontentlength>3</D:getcontentlength></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
</D:multistatus>`))
	}))
	defer server.Close()

	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := storageconfig.RemoteStorageConfig{
		ProfileID:      "scoped-webdav-profile",
		StorageType:    storageconfig.StorageTypeWebDAV,
		Endpoint:       server.URL,
		WebDAVUsername: "user",
		WebDAVPassword: "password",
		RootPrefix:     "archive/2026",
		CacheDirectory: t.TempDir(),
	}
	handle, err := manager.Acquire(config, "bucket")
	if err != nil {
		t.Fatal(err)
	}
	defer handle.Release()
	items, err := handle.Service.ListDirectory(context.Background(), "")
	if err != nil {
		t.Fatalf("materialize root: %v", err)
	}
	select {
	case got := <-paths:
		if got != "/archive/2026/" {
			t.Fatalf("provider path = %q, want /archive/2026/", got)
		}
	default:
		t.Fatal("metadata materialization did not issue a provider request")
	}
	if len(items) != 1 || items[0].Key != "report.txt" {
		t.Fatalf("scoped metadata result = %+v", items)
	}
}

func TestAcquireWithBackendRefreshesExistingServicePolicy(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := fakeConfig("policy-profile")
	config.CacheDirectory = t.TempDir()
	config.WritebackQuietSeconds = 3

	first, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
	if err != nil {
		t.Fatal(err)
	}
	if quiet := first.Service.quietPeriod(); quiet != 3*time.Second {
		t.Fatalf("initial quiet period = %s, want 3s", quiet)
	}

	config.WritebackQuietSeconds = 7
	config.BucketSettings = map[string]storageconfig.BucketSettings{"bucket": {ReadOnly: true}}
	second, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
	if err != nil {
		t.Fatal(err)
	}
	if first.Service != second.Service {
		t.Fatal("second acquire did not retain the existing service")
	}
	if quiet := second.Service.quietPeriod(); quiet != 7*time.Second {
		t.Fatalf("refreshed quiet period = %s, want 7s", quiet)
	}
	if !second.Service.isReadOnly() {
		t.Fatal("existing service did not refresh read-only policy")
	}
	first.Release()
	second.Release()
}

func TestPageReleaseDoesNotCloseMountHeldNamespace(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := fakeConfig("shared-profile")
	config.CacheDirectory = t.TempDir()

	mountHandle, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
	if err != nil {
		t.Fatal(err)
	}
	pageHandle, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
	if err != nil {
		t.Fatal(err)
	}
	pageHandle.Release()
	if services := manager.List(); len(services) != 1 {
		t.Fatalf("page release closed mount-held service: %+v", services)
	}
	if _, err := mountHandle.Service.StatInode(context.Background(), rootInode); err != nil {
		t.Fatalf("mount-held service became unusable: %v", err)
	}
	mountHandle.Release()
	if services := manager.List(); len(services) != 0 {
		t.Fatalf("mount release did not close final service: %+v", services)
	}
}

func TestPageReleaseRetainsPendingNamespaceUntilLaterIdleRelease(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := fakeConfig("page-pending-profile")
	config.CacheDirectory = t.TempDir()
	backend := newFakeBackend()
	handle, err := manager.AcquireWithBackend(config, "bucket", backend)
	if err != nil {
		t.Fatal(err)
	}
	handle.Service.SetQuietPeriod(time.Hour)
	if _, _, err := handle.Service.WritePath(
		context.Background(), "draft.txt", strings.NewReader("draft"), 5, WriteOptions{Origin: "page"},
	); err != nil {
		t.Fatal(err)
	}
	handle.Release()
	if services := manager.List(); len(services) != 1 {
		t.Fatalf("page release closed pending namespace: %+v", services)
	}
	if err := handle.Service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) { op.NextAttemptUnixNano = time.Now().Add(-time.Second).UnixNano() })
	}); err != nil {
		t.Fatal(err)
	}
	if err := manager.DrainAll(context.Background()); err != nil {
		t.Fatal(err)
	}
	reopened, err := manager.AcquireWithBackend(config, "bucket", backend)
	if err != nil {
		t.Fatal(err)
	}
	reopened.Release()
	if services := manager.List(); len(services) != 0 {
		t.Fatalf("idle namespace stayed retained after later release: %+v", services)
	}
}

func TestPageReleaseRetainsFailedNamespace(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := fakeConfig("page-failed-profile")
	config.CacheDirectory = t.TempDir()
	handle, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
	if err != nil {
		t.Fatal(err)
	}
	handle.Service.SetQuietPeriod(time.Hour)
	if _, err := handle.Service.CreateDirectoryPath(context.Background(), "failed", WriteOptions{Origin: "page"}); err != nil {
		t.Fatal(err)
	}
	if err := handle.Service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) { op.State = OpStateFailed })
	}); err != nil {
		t.Fatal(err)
	}
	handle.Release()
	if services := manager.List(); len(services) != 1 {
		t.Fatalf("page release closed failed namespace: %+v", services)
	}
}

func TestPageReleaseRetainsPendingContent(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := fakeConfig("page-content-profile")
	config.CacheDirectory = t.TempDir()
	handle, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := handle.Service.StageWriteForName(
		rootInode, "draft.txt", 1, strings.NewReader("draft"), 5,
	); err != nil {
		t.Fatal(err)
	}
	handle.Release()
	if services := manager.List(); len(services) != 1 {
		t.Fatalf("page release closed namespace with pending content: %+v", services)
	}
}

func TestAcquireWithBackendRefreshesTransportHeldByMount(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := fakeConfig("transport-profile")
	config.CacheDirectory = t.TempDir()
	oldBackend := newFakeBackend()
	oldBackend.objects["/old.txt"] = storageops.ObjectInfo{Key: "old.txt", Size: 1}
	mountHandle, err := manager.AcquireWithBackend(config, "bucket", oldBackend)
	if err != nil {
		t.Fatal(err)
	}
	if err := mountHandle.Service.MaterializeDirectory(context.Background(), rootInode); err != nil {
		t.Fatal(err)
	}

	newBackend := newFakeBackend()
	newBackend.objects["/new.txt"] = storageops.ObjectInfo{Key: "new.txt", Size: 2}
	pageHandle, err := manager.AcquireWithBackend(config, "bucket", newBackend)
	if err != nil {
		t.Fatal(err)
	}
	defer pageHandle.Release()
	defer mountHandle.Release()
	if err := mountHandle.Service.MaterializeDirectory(context.Background(), rootInode); err != nil {
		t.Fatal(err)
	}
	page, err := mountHandle.Service.ListPage(context.Background(), rootInode, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 1 || page.Items[0].Key != "new.txt" {
		t.Fatalf("mount-held service kept stale backend: %+v", page.Items)
	}
}
