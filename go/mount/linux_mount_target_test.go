//go:build linux

package mount

import (
	"os"
	"path/filepath"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestPrepareLinuxMountPathRejectsNonEmptyCustomTarget(t *testing.T) {
	customPath := filepath.Join(t.TempDir(), "mount")
	if err := os.MkdirAll(customPath, 0o755); err != nil {
		t.Fatalf("mkdir custom path: %v", err)
	}
	if err := os.WriteFile(filepath.Join(customPath, "keep.txt"), []byte("keep"), 0o644); err != nil {
		t.Fatalf("seed custom path: %v", err)
	}

	if err := prepareLinuxMountPath(customPath, false); err == nil {
		t.Fatal("expected non-empty custom mount path to be rejected")
	}
}

func TestMountSessionMatchesCustomMountPath(t *testing.T) {
	cfg := storageconfig.DefaultConfig()
	// Normalized must be stored in the session so that reflect.DeepEqual
	// against a freshly normalized config succeeds.
	session := &mountSession{
		config:        cfg.Normalized(),
		bucket:        "demo",
		requestedPath: filepath.Clean("/tmp/demo-mount"),
	}

	if !mountSessionMatches(
		session,
		cfg,
		"demo",
		MountOptions{MountPath: "/tmp/demo-mount"},
	) {
		t.Fatal("expected mount session to match identical custom mount path")
	}

	if mountSessionMatches(
		session,
		cfg,
		"demo",
		MountOptions{MountPath: "/tmp/other-mount"},
	) {
		t.Fatal("expected different custom mount path to force remount")
	}
}
