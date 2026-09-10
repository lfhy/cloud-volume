//go:build windows

// Windows-specific coverage keeps metadata chunk admission from regressing to read-only directory Sync.
package metadata

import "testing"

func TestSyncDirectoryFlushesWindowsDirectory(t *testing.T) {
	if err := syncDirectory(t.TempDir()); err != nil {
		t.Fatalf("sync directory: %v", err)
	}
}
