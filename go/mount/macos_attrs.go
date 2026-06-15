//go:build darwin

// macOS mount attributes keep Desktop-visible mount points out of File Provider sync.
package mount

import (
	"fmt"
	"strings"

	"golang.org/x/sys/unix"
)

const (
	fileProviderIgnoreAttr = "com.apple.fileprovider.ignore#P"
	fileProviderIgnoreFlag = "1"
)

func markMountPathIgnoredByFileProvider(mountPath string) error {
	if strings.TrimSpace(mountPath) == "" {
		return fmt.Errorf("mount path is required")
	}
	if err := unix.Setxattr(mountPath, fileProviderIgnoreAttr, []byte(fileProviderIgnoreFlag), 0); err != nil {
		return fmt.Errorf("set %s on mount path: %w", fileProviderIgnoreAttr, err)
	}
	return nil
}
