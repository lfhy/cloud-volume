//go:build windows

package mount

import (
	"path/filepath"
	"testing"
)

func TestWindowsCloudFilesMountDirNameUsesStableBucketDirectory(t *testing.T) {
	got := windowsCloudFilesMountDirName("demo/bucket")
	if got != "demo_bucket" {
		t.Fatalf("expected stable sanitized bucket directory, got %q", got)
	}
}

func TestWindowsCloudFilesMountPathUsesStableBucketDirectory(t *testing.T) {
	root, err := windowsCloudFilesRootPath()
	if err != nil {
		t.Fatalf("windowsCloudFilesRootPath: %v", err)
	}
	got, err := windowsCloudFilesMountPath("demo/bucket")
	if err != nil {
		t.Fatalf("windowsCloudFilesMountPath: %v", err)
	}
	want := filepath.Join(root, "demo_bucket")
	if got != want {
		t.Fatalf("expected stable mount path %q, got %q", want, got)
	}
}
