//go:build darwin

// Optional macOS integration coverage exercises the real WebDAV mount command
// without making ordinary package tests depend on a mounted volume or Finder.
package mount

import (
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func TestMacOSWebDAVMountAndOpenIntegration(t *testing.T) {
	if os.Getenv("CLOUD_VOLUME_RUN_MACOS_MOUNT_INTEGRATION") != "1" {
		t.Skip("set CLOUD_VOLUME_RUN_MACOS_MOUNT_INTEGRATION=1 to exercise /sbin/mount_webdav")
	}

	access := newTestBucketAccess(t)
	server, serverURL, _, err := startWebDAVServer(access, "cloud-volume-integration")
	if err != nil {
		t.Fatalf("startWebDAVServer: %v", err)
	}
	t.Cleanup(func() { _ = server.stop() })

	mountPath := filepath.Join(t.TempDir(), "webdav-mount")
	actualPath, err := mountWebDAV(serverURL, mountPath, "cloud-volume-integration")
	if err != nil {
		t.Fatalf("mountWebDAV: %v", err)
	}
	t.Cleanup(func() { _ = unmountWebDAV(actualPath) })

	active, err := isWebDAVMountActive(actualPath)
	if err != nil || !active {
		t.Fatalf("mount active = %t, err=%v", active, err)
	}
	assertMountedDirectoryReadable(t, actualPath)

	opened := make(chan string, 1)
	oldLaunch := launchFinder
	launchFinder = func(path string) {
		opened <- path
	}
	t.Cleanup(func() { launchFinder = oldLaunch })
	if err := openMountPath(actualPath); err != nil {
		t.Fatalf("openMountPath: %v", err)
	}
	select {
	case path := <-opened:
		if path != actualPath {
			t.Errorf("open path = %q, want %q", path, actualPath)
		}
	case <-time.After(time.Second):
		t.Fatal("openMountPath did not dispatch the Finder launch hook")
	}
}

func assertMountedDirectoryReadable(t *testing.T, mountPath string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "/bin/ls", "-la", mountPath)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			t.Fatalf("mounted directory probe timed out after %s", 15*time.Second)
		}
		t.Fatalf("mounted directory probe: %v", err)
	}
}
