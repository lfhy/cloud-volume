//go:build linux

// Linux mount path helpers keep user-visible mount locations stable across remounts.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
)

const linuxMountFolderName = "Cloud Volume"

func linuxMountRootPath() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home: %w", err)
	}
	return filepath.Join(homeDir, linuxMountFolderName), nil
}

func linuxMountPath(bucket string) (string, error) {
	rootPath, err := linuxMountRootPath()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, safeSegment(bucket)), nil
}
