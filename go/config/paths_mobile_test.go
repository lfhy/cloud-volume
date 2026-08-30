package config

import (
	"path/filepath"
	"testing"
)

// SetAppDataRoot lets Android redirect config/runtime data into app-private
// storage. These tests pin the override semantics used by the mobile bridge.
func TestSetAppDataRootOverridesDefaultConfigPath(t *testing.T) {
	restoreAppDataRoot(t)

	root := t.TempDir()
	if err := SetAppDataRoot(root); err != nil {
		t.Fatalf("SetAppDataRoot(%q) failed: %v", root, err)
	}

	got, err := DefaultConfigPath()
	if err != nil {
		t.Fatalf("DefaultConfigPath() failed: %v", err)
	}
	if want := filepath.Join(root, configFileName); got != want {
		t.Fatalf("DefaultConfigPath() = %q, want %q", got, want)
	}
	if got, err := AppDataRoot(); err != nil || got != filepath.Clean(root) {
		t.Fatalf("AppDataRoot() = %q, %v; want %q", got, err, filepath.Clean(root))
	}
}

func TestSetAppDataRootRejectsEmptyPath(t *testing.T) {
	restoreAppDataRoot(t)

	if err := SetAppDataRoot("   "); err == nil {
		t.Fatal("SetAppDataRoot(whitespace) = nil error, want error")
	}
}

// restoreAppDataRoot clears the override after each test so desktop tests
// keep resolving the real home-directory layout.
func restoreAppDataRoot(t *testing.T) {
	t.Helper()
	t.Cleanup(func() {
		if err := switchConfigDBRoot(func() {
			appDataRootOverride.Lock()
			appDataRootOverride.path = ""
			appDataRootOverride.Unlock()
		}); err != nil {
			t.Errorf("reset app data root: %v", err)
		}
	})
}
