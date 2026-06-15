//go:build !darwin && !windows && !linux

// Unsupported platforms keep the manager API intact but return a clear error on mount.
package mount

import (
	"fmt"

	storageconfig "remote-storage/go/config"
)

type unsupportedMountBackend struct{}

func newPlatformMountBackend(_ storageconfig.RemoteStorageConfig) (mountBackend, error) {
	return nil, fmt.Errorf("bucket mount is not supported on this platform")
}

func (b *unsupportedMountBackend) Initialize(session *mountSession) error {
	return fmt.Errorf("bucket mount is not supported on this platform")
}

func (b *unsupportedMountBackend) Start(session *mountSession) error {
	return fmt.Errorf("bucket mount is not supported on this platform")
}

func (b *unsupportedMountBackend) Stop(session *mountSession) error {
	return nil
}

func (b *unsupportedMountBackend) IsActive(session *mountSession) (bool, error) {
	return false, nil
}

func (b *unsupportedMountBackend) CleanupStale(session *mountSession) error {
	return nil
}

func cleanupAllManagedMounts() error {
	return nil
}
