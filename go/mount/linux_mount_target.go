//go:build linux

// Linux mount-target helpers keep CLI custom mountpoints safe and predictable.
package mount

import (
	"fmt"
	"os"
)

func prepareLinuxMountPath(mountPath string, managed bool) error {
	if managed {
		if err := os.RemoveAll(mountPath); err != nil && !os.IsNotExist(err) {
			return err
		}
		return os.MkdirAll(mountPath, 0o755)
	}
	if err := os.MkdirAll(mountPath, 0o755); err != nil {
		return err
	}
	entries, err := os.ReadDir(mountPath)
	if err != nil {
		return err
	}
	if len(entries) > 0 {
		return fmt.Errorf("custom mount path %q must be empty", mountPath)
	}
	return nil
}
