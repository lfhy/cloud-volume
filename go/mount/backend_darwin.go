//go:build darwin

// macOS backend keeps the current WebDAV-based Finder mount behavior.
package mount

import (
	"log"
	"os"
	"path/filepath"
	"strings"

	storageconfig "remote-storage/go/config"
)

const managedMountPrefix = "云卷-"

type macOSWebDAVBackend struct{}

var (
	probeExactWebDAVMountActive = isExactWebDAVMountActive
	probePathWebDAVMountActive  = isWebDAVMountActive
)

func newPlatformMountBackend(_ storageconfig.RemoteStorageConfig) (mountBackend, error) {
	return &macOSWebDAVBackend{}, nil
}

func (b *macOSWebDAVBackend) Initialize(session *mountSession) error {
	session.mountName = managedMountPrefix + session.bucket
	if session.requestedPath != "" {
		session.mountPath = session.requestedPath
	} else {
		session.mountPath = filepath.Join("/Volumes", session.mountName)
	}
	session.mountTarget = session.mountPath
	return nil
}

func (b *macOSWebDAVBackend) Start(session *mountSession) error {
	return session.start()
}

func (b *macOSWebDAVBackend) Stop(session *mountSession) error {
	return session.stop()
}

func (b *macOSWebDAVBackend) IsActive(session *mountSession) (bool, error) {
	if session != nil && session.mountAttempted && !session.mounted {
		if strings.TrimSpace(session.serverURL) == "" {
			return false, nil
		}
		return probeExactWebDAVMountActive(session.serverURL, session.mountTarget)
	}
	return probePathWebDAVMountActive(session.mountTarget)
}

func (b *macOSWebDAVBackend) CleanupStale(session *mountSession) error {
	paths, err := listWebDAVMountPaths()
	if err != nil {
		return err
	}
	matches := matchingBucketMountPaths(paths, session.mountName)
	log.Printf(
		"[mount/backend] cleanup-stale bucket=%q mount_name=%q matches=%q",
		session.bucket,
		session.mountName,
		matches,
	)
	for _, mountPath := range matches {
		if err := unmountWebDAV(mountPath); err != nil {
			return err
		}
	}
	return nil
}

func cleanupAllManagedMounts() error {
	paths, err := listWebDAVMountPaths()
	if err != nil {
		return err
	}
	matches := matchingManagedMountPaths(paths)
	log.Printf("[mount/backend] cleanup-all matches=%q", matches)
	for _, mountPath := range matches {
		if err := unmountWebDAV(mountPath); err != nil {
			return err
		}
	}
	return nil
}

func matchingBucketMountPaths(paths []string, mountName string) []string {
	matches := make([]string, 0, len(paths))
	for _, mountPath := range paths {
		clean := filepath.Clean(strings.TrimSpace(mountPath))
		for _, root := range macOSManagedMountRoots() {
			basePath := filepath.Join(root, mountName)
			if clean == basePath || strings.HasPrefix(clean, basePath+"-") {
				matches = append(matches, clean)
				break
			}
		}
	}
	return matches
}

func matchingManagedMountPaths(paths []string) []string {
	matches := make([]string, 0, len(paths))
	for _, mountPath := range paths {
		clean := filepath.Clean(strings.TrimSpace(mountPath))
		for _, root := range macOSManagedMountRoots() {
			basePrefix := filepath.Join(root, managedMountPrefix)
			if strings.HasPrefix(clean, basePrefix) {
				matches = append(matches, clean)
				break
			}
		}
	}
	return matches
}

func macOSManagedMountRoots() []string {
	roots := []string{"/Volumes"}
	if home, err := os.UserHomeDir(); err == nil && strings.TrimSpace(home) != "" {
		roots = append(roots, filepath.Join(home, "云卷"))
	}
	return roots
}
