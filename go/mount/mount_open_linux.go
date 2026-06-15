//go:build linux

// Linux mount actions use xdg-open so the mount can be revealed in the host file manager.
package mount

import (
	"fmt"
	"os/exec"
)

func openMountPath(mountPath string) error {
	output, err := exec.Command("xdg-open", mountPath).CombinedOutput()
	if err != nil {
		return fmt.Errorf("open mount path: %w: %s", err, string(output))
	}
	return nil
}
