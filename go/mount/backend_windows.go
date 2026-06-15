//go:build windows

// Windows mount selection keeps Cloud Files variants and WebDAV fallback side by side.
package mount

import (
	"fmt"
	"log"
	"strings"

	storageconfig "remote-storage/go/config"
)

func newPlatformMountBackend(cfg storageconfig.RemoteStorageConfig) (mountBackend, error) {
	mode := normalizeWindowsMountMode(cfg.WindowsMountMode)
	log.Printf("[mount/windows] select-backend mode=%q", mode)
	switch mode {
	case storageconfig.WindowsMountModeWebDAV:
		return &windowsWebDAVBackend{}, nil
	case storageconfig.WindowsMountModeCloudFilesCached:
		return newWindowsCloudFilesBackend(storageconfig.WindowsMountModeCloudFilesCached)
	case storageconfig.WindowsMountModeCloudFilesDirect:
		return newWindowsCloudFilesBackend(storageconfig.WindowsMountModeCloudFilesDirect)
	default:
		return nil, fmt.Errorf("unsupported Windows mount mode %q", cfg.WindowsMountMode)
	}
}

func cleanupAllManagedMounts() error {
	if err := cleanupManagedWindowsCloudFilesArtifacts(); err != nil {
		return err
	}
	return cleanupManagedWindowsWebDAVMounts()
}

func normalizeWindowsMountMode(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case storageconfig.WindowsMountModeCloudFilesDirect:
		return storageconfig.WindowsMountModeCloudFilesDirect
	case storageconfig.WindowsMountModeWebDAV:
		return storageconfig.WindowsMountModeWebDAV
	default:
		return storageconfig.WindowsMountModeCloudFilesCached
	}
}
