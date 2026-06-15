//go:build windows

// Windows Cloud Files path helpers keep managed sync-root locations consistent.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
)

const windowsMountFolderName = "Cloud Volume"

func windowsCloudFilesRootPath() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home: %w", err)
	}
	return filepath.Join(homeDir, windowsMountFolderName), nil
}

func windowsCloudFilesMountPath(bucket string) (string, error) {
	rootPath, err := windowsCloudFilesRootPath()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, windowsCloudFilesMountDirName(bucket)), nil
}

func windowsCloudFilesMountDirName(bucket string) string {
	// Keep the user-visible sync-root path stable so Explorer shortcuts and
	// writeback recovery always point at one deterministic bucket directory.
	return safeSegment(bucket)
}
