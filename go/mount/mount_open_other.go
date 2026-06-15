//go:build !darwin && !windows && !linux

// Unsupported platforms keep the open action explicit instead of silently succeeding.
package mount

import "fmt"

func openMountPath(mountPath string) error {
	return fmt.Errorf("open mount path is not supported on this platform")
}
