//go:build windows && !cgo

// Windows without CGO can still fall back to WebDAV, but Cloud Files modes stay unavailable.
package mount

import "fmt"

func newWindowsCloudFilesBackend(mode string) (mountBackend, error) {
	return nil, fmt.Errorf("Windows mount mode %q requires CGO_ENABLED=1", mode)
}

func cleanupManagedWindowsCloudFilesArtifacts() error {
	return cleanupLegacyWindowsShellNamespaces()
}
