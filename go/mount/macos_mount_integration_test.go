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

func TestMacOSWebDAVMountedRecursiveCopyIntegration(t *testing.T) {
	if os.Getenv("CLOUD_VOLUME_RUN_MACOS_MOUNT_INTEGRATION") != "1" {
		t.Skip("set CLOUD_VOLUME_RUN_MACOS_MOUNT_INTEGRATION=1 to exercise recursive copy through webdavfs_agent")
	}

	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	handle.Service.SetQuietPeriod(time.Hour)
	server, serverURL, _, err := startWebDAVServer(access, "cloud-volume-copy-integration")
	if err != nil {
		t.Fatalf("startWebDAVServer: %v", err)
	}
	t.Cleanup(func() { _ = server.stop() })

	mountPath := filepath.Join(t.TempDir(), "webdav-mount")
	actualPath, err := mountWebDAV(serverURL, mountPath, "cloud-volume-copy-integration")
	if err != nil {
		t.Fatalf("mountWebDAV: %v", err)
	}
	t.Cleanup(func() { _ = unmountWebDAV(actualPath) })

	sourceRoot := filepath.Join(t.TempDir(), "Controller")
	fixtures := map[string]string{
		"Admin/Controller/MiscCostController.class.php": "<?php class MiscCostController {}",
		"Admin/Repositories/ExportListConfig.class.php": "<?php return ['export' => true];",
		"Admin/Repositories/UploadFileConfig.class.php": "<?php return ['upload' => true];",
		"API/测试/文件+plus.txt":                            "local first",
		"Resources/.localized":                          "",
	}
	for relative, content := range fixtures {
		path := filepath.Join(sourceRoot, filepath.FromSlash(relative))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("create copy fixture parent %q: %v", relative, err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatalf("write copy fixture %q: %v", relative, err)
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	destination := filepath.Join(actualPath, "Controller")
	output, err := exec.CommandContext(ctx, "/usr/bin/ditto", sourceRoot, destination).CombinedOutput()
	if err != nil {
		if ctx.Err() != nil {
			t.Fatalf("recursive copy timed out after %s", 30*time.Second)
		}
		t.Fatalf("recursive copy through mounted WebDAV: %v: %s", err, output)
	}
	if active, err := isWebDAVMountActive(actualPath); err != nil || !active {
		t.Fatalf("mount disappeared during recursive copy: active=%t err=%v", active, err)
	}
	for relative, want := range fixtures {
		data, err := os.ReadFile(filepath.Join(destination, filepath.FromSlash(relative)))
		if err != nil {
			t.Fatalf("read copied file %q from mount: %v", relative, err)
		}
		if got := string(data); got != want {
			t.Fatalf("copied file %q = %q, want %q", relative, got, want)
		}
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
