//go:build windows && cgo

package mount

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWindowsCloudFilesWriteProbeOnce(t *testing.T) {
	root := t.TempDir()
	probeDir := filepath.Join(root, windowsCloudFilesHealthProbeDir)
	probeFile := filepath.Join(probeDir, windowsCloudFilesHealthProbeFile)

	if err := windowsCloudFilesWriteProbeOnce(probeDir, probeFile); err != nil {
		t.Fatalf("write probe failed: %v", err)
	}
	if _, err := os.Stat(probeFile); !os.IsNotExist(err) {
		t.Fatalf("expected probe file to be removed, got err=%v", err)
	}
}
