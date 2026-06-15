//go:build linux

package mount

import (
	"path/filepath"
	"testing"
)

func TestResolveMountPathUsesCustomLinuxMountTarget(t *testing.T) {
	target, err := ResolveMountPath("demo", MountOptions{MountPath: "/tmp/demo-mount"})
	if err != nil {
		t.Fatalf("ResolveMountPath returned error: %v", err)
	}
	if target != filepath.Clean("/tmp/demo-mount") {
		t.Fatalf("ResolveMountPath = %q, want %q", target, filepath.Clean("/tmp/demo-mount"))
	}
}

func TestResolveMountPathFallsBackToManagedLinuxRoot(t *testing.T) {
	target, err := ResolveMountPath("demo", MountOptions{})
	if err != nil {
		t.Fatalf("ResolveMountPath returned error: %v", err)
	}
	want, err := linuxMountPath("demo")
	if err != nil {
		t.Fatalf("linuxMountPath returned error: %v", err)
	}
	if target != want {
		t.Fatalf("ResolveMountPath = %q, want %q", target, want)
	}
}
