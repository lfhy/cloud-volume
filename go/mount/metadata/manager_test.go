// Manager tests keep namespace sharing and root-scoped provider reads stable.
package metadata

import (
	"path/filepath"
	"testing"
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
