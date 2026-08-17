// Manager tests keep namespace sharing and root-scoped provider reads stable.
package metadata

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
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
