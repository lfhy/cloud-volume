//go:build !linux

// Non-Linux CLI helpers keep unsupported mount operations explicit.
package mount

import "fmt"

func resolveMountPath(bucket string, options MountOptions) (string, error) {
	if mountPath := normalizeMountPath(options.MountPath); mountPath != "" {
		return mountPath, nil
	}
	if bucket == "" {
		return "", fmt.Errorf("missing bucket name")
	}
	return "", fmt.Errorf("direct CLI mount path resolution is not supported on this platform")
}

func probeMountPath(mountPath string) (bool, error) {
	return false, fmt.Errorf("CLI mount status is not supported on this platform")
}

func unmountMountPath(mountPath string) error {
	return fmt.Errorf("CLI unmount is not supported on this platform")
}
