// Mount cache cleanup removes stale cache and staging files from the runtime directory.
package mount

import (
	"fmt"
	"os"

	storageconfig "remote-storage/go/config"
)

// ClearMountCacheResult reports how many files were removed during cleanup.
type ClearMountCacheResult struct {
	RemovedCount int   `json:"removedCount"`
	FreedBytes   int64 `json:"freedBytes"`
}

// ClearMountCache removes all cache and staging files under the mount runtime
// directory. It skips active mount sessions to avoid disrupting in-progress I/O.
func ClearMountCache() (ClearMountCacheResult, error) {
	mountRoot, err := storageconfig.MountRuntimeDir()
	if err != nil {
		return ClearMountCacheResult{}, fmt.Errorf("resolve mount runtime dir: %w", err)
	}

	entries, err := os.ReadDir(mountRoot)
	if err != nil {
		if os.IsNotExist(err) {
			return ClearMountCacheResult{}, nil
		}
		return ClearMountCacheResult{}, fmt.Errorf("read mount runtime dir: %w", err)
	}

	var totalRemoved int
	var totalFreed int64

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		bucketRoot := mountRoot + "/" + entry.Name()

		// Skip if there's an active session marker for this bucket.
		if active, _ := isMountSessionActive(bucketRoot); active {
			continue
		}

		for _, sub := range []string{"cache", "staging"} {
			subDir := bucketRoot + "/" + sub
			info, err := os.Stat(subDir)
			if err != nil {
				continue
			}
			if !info.IsDir() {
				continue
			}
			removed, freed := removeDirContents(subDir)
			totalRemoved += removed
			totalFreed += freed
		}
	}

	return ClearMountCacheResult{
		RemovedCount: totalRemoved,
		FreedBytes:   totalFreed,
	}, nil
}

// isMountSessionActive checks whether a bucket mount session appears active.
func isMountSessionActive(bucketRoot string) (bool, error) {
	// The presence of a running WebDAV server PID file indicates active state.
	pidPath := bucketRoot + "/webdav.pid"
	if _, err := os.Stat(pidPath); err != nil {
		return false, nil
	}
	return true, nil
}

// removeDirContents removes all files and subdirectories under dir, returning
// the count and total bytes freed. The root directory itself is preserved.
func removeDirContents(dir string) (count int, freedBytes int64) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0, 0
	}
	for _, entry := range entries {
		fullPath := dir + "/" + entry.Name()
		if entry.IsDir() {
			subCount, subFreed := removeDirContents(fullPath)
			count += subCount
			freedBytes += subFreed
			_ = os.Remove(fullPath)
			continue
		}
		info, statErr := entry.Info()
		if statErr != nil {
			continue
		}
		size := info.Size()
		if err := os.Remove(fullPath); err == nil {
			count++
			freedBytes += size
		}
	}
	return
}
