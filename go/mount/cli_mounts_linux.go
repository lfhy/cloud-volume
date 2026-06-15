//go:build linux

// Linux CLI helpers let the standalone binary inspect and unmount system FUSE mountpoints.
package mount

import "fmt"

func resolveMountPath(bucket string, options MountOptions) (string, error) {
	if mountPath := normalizeMountPath(options.MountPath); mountPath != "" {
		return mountPath, nil
	}
	if bucket == "" {
		return "", fmt.Errorf("missing bucket name")
	}
	return linuxMountPath(bucket)
}

func probeMountPath(mountPath string) (bool, error) {
	return linuxMountActive(mountPath)
}

func unmountMountPath(mountPath string) error {
	if mountPath == "" {
		return fmt.Errorf("mount path is empty")
	}
	active, err := linuxMountActive(mountPath)
	if err != nil {
		return err
	}
	if !active {
		return nil
	}
	return linuxUnmountPath(mountPath)
}
