// Cache maintenance owns stats, manual clear, rule-based eviction and opening
// the cache directory in the desktop shell. It deliberately only touches files
// inside the resolved cache root; profiles, runtime logs and config stay intact.
package config

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"time"
)

// CacheStats summarises the resolved cache directory for the settings UI.
type CacheStats struct {
	Path           string `json:"path"`
	Exists         bool   `json:"exists"`
	SizeBytes      int64  `json:"sizeBytes"`
	FileCount      int64  `json:"fileCount"`
	ProtectedBytes int64  `json:"protectedBytes"`
	ProtectedFiles int64  `json:"protectedFiles"`
	LastModified   string `json:"lastModified"`
}

// CleanCacheRequest selects which cleanup strategy the bridge should run.
type CleanCacheRequest struct {
	// ClearAll wipes every evictable file under the cache root when true.
	// Otherwise ApplyRules evicts by size/age from the active config.
	ClearAll bool `json:"clearAll"`
}

// CleanCacheResult reports what happened during a cleanup pass.
type CleanCacheResult struct {
	BeforeBytes      int64 `json:"beforeBytes"`
	AfterBytes       int64 `json:"afterBytes"`
	Removed          int64 `json:"removed"`
	FreedBytes       int64 `json:"freedBytes"`
	SkippedProtected int64 `json:"skippedProtected"`
}

// GetCacheStats resolves the cache directory for the active config and walks it
// to compute total size and file count. A missing directory is reported as
// exists=false instead of an error so first-run installs render cleanly.
func GetCacheStats(config RemoteStorageConfig) (CacheStats, error) {
	normalized := config.Normalized()
	cacheDir, err := ResolveCacheDir(normalized)
	if err != nil {
		return CacheStats{}, err
	}
	stats := CacheStats{Path: cacheDir}
	protection := loadMetadataChunkProtection(cacheDir)
	info, err := os.Stat(cacheDir)
	if err != nil {
		if os.IsNotExist(err) {
			return stats, nil
		}
		return stats, fmt.Errorf("stat cache directory: %w", err)
	}
	stats.Exists = true
	stats.LastModified = info.ModTime().Format(time.RFC3339)

	walkErr := filepath.Walk(cacheDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			// Skip unreadable entries instead of aborting the whole walk so the
			// stats card still renders when a stray temp file disappears mid-scan.
			return nil
		}
		if info.IsDir() {
			return nil
		}
		stats.SizeBytes += info.Size()
		stats.FileCount++
		if protection.isPending(path) {
			stats.ProtectedBytes += info.Size()
			stats.ProtectedFiles++
		}
		if info.ModTime().Format(time.RFC3339) > stats.LastModified {
			stats.LastModified = info.ModTime().Format(time.RFC3339)
		}
		return nil
	})
	if walkErr != nil {
		return stats, fmt.Errorf("walk cache directory: %w", walkErr)
	}
	return stats, nil
}

// OpenCacheDirectory launches the platform file manager at the resolved cache
// directory, creating it first when missing so the user always lands somewhere.
func OpenCacheDirectory(config RemoteStorageConfig) error {
	normalized := config.Normalized()
	cacheDir, err := ResolveCacheDir(normalized)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(cacheDir, 0o700); err != nil {
		return fmt.Errorf("create cache directory: %w", err)
	}
	command, args := openFolderCommand(cacheDir)
	if command == "" {
		return fmt.Errorf("opening folders is unsupported on %s", runtime.GOOS)
	}
	if err := exec.Command(command, args...).Start(); err != nil {
		return fmt.Errorf("open cache directory: %w", err)
	}
	return nil
}

// CleanCache removes evictable cache files according to the request mode.
// Pending metadata chunks and active splices are protected in both modes.
func CleanCache(config RemoteStorageConfig, request CleanCacheRequest) (CleanCacheResult, error) {
	normalized := config.Normalized()
	cacheDir, err := ResolveCacheDir(normalized)
	if err != nil {
		return CleanCacheResult{}, err
	}
	entries, err := listCacheFiles(cacheDir)
	if err != nil {
		return CleanCacheResult{}, err
	}
	result := CleanCacheResult{BeforeBytes: totalSize(entries)}
	protection := loadMetadataChunkProtection(cacheDir)

	var toRemove []cacheFile
	if request.ClearAll {
		for _, entry := range entries {
			if protection.protected(entry.path) {
				if protection.isPending(entry.path) {
					result.SkippedProtected++
				}
				continue
			}
			toRemove = append(toRemove, entry)
		}
	} else {
		var skipped int
		toRemove, skipped = selectByRules(entries, normalized, protection)
		result.SkippedProtected = int64(skipped)
	}

	for _, file := range toRemove {
		if err := os.Remove(file.path); err != nil && !os.IsNotExist(err) {
			return result, fmt.Errorf("remove %s: %w", file.path, err)
		}
		result.Removed++
	}

	remaining, err := listCacheFiles(cacheDir)
	if err != nil {
		// Removals already succeeded; surface what we removed so the UI still
		// gets a useful number instead of masking the cleanup behind a re-walk error.
		result.AfterBytes = result.BeforeBytes - totalSize(toRemove)
		return result, nil
	}
	result.AfterBytes = totalSize(remaining)
	result.FreedBytes = result.BeforeBytes - result.AfterBytes
	return result, nil
}

// cacheFile pairs a cache file path with the metadata used for eviction.
type cacheFile struct {
	path    string
	size    int64
	modTime time.Time
}

// listCacheFiles walks the cache root and returns regular files, skipping dirs.
func listCacheFiles(cacheDir string) ([]cacheFile, error) {
	if _, err := os.Stat(cacheDir); err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("stat cache directory: %w", err)
	}
	var files []cacheFile
	walkErr := filepath.Walk(cacheDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			return nil
		}
		files = append(files, cacheFile{
			path:    path,
			size:    info.Size(),
			modTime: info.ModTime(),
		})
		return nil
	})
	if walkErr != nil {
		return nil, fmt.Errorf("walk cache directory: %w", walkErr)
	}
	return files, nil
}

// selectByRules applies the configured size/age limits and returns the files
// that should be removed. Age eviction happens first; size eviction then
// removes the oldest survivors until total size fits within the cap.
func selectByRules(
	files []cacheFile, config RemoteStorageConfig, protection metadataChunkProtection,
) ([]cacheFile, int) {
	maxAgeDays := config.CacheMaxAgeDays
	maxSizeMB := config.CacheMaxSizeMB
	if maxAgeDays <= 0 && maxSizeMB <= 0 {
		return nil, 0
	}

	now := time.Now()
	var survivors []cacheFile
	var remove []cacheFile
	skipped := map[string]struct{}{}
	for _, file := range files {
		if maxAgeDays > 0 && now.Sub(file.modTime) > time.Duration(maxAgeDays)*24*time.Hour {
			if protection.protected(file.path) {
				if protection.isPending(file.path) {
					skipped[file.path] = struct{}{}
				}
				survivors = append(survivors, file)
				continue
			}
			remove = append(remove, file)
			continue
		}
		survivors = append(survivors, file)
	}

	if maxSizeMB <= 0 {
		return remove, len(skipped)
	}

	sort.Slice(survivors, func(i, j int) bool {
		return survivors[i].modTime.Before(survivors[j].modTime)
	})
	maxBytes := int64(maxSizeMB) * 1024 * 1024
	current := totalSize(survivors)
	for _, file := range survivors {
		if current <= maxBytes {
			break
		}
		if protection.protected(file.path) {
			if protection.isPending(file.path) {
				skipped[file.path] = struct{}{}
			}
			continue
		}
		remove = append(remove, file)
		current -= file.size
	}
	return remove, len(skipped)
}

func totalSize(files []cacheFile) int64 {
	var total int64
	for _, file := range files {
		total += file.size
	}
	return total
}

// openFolderCommand returns the platform command used to reveal a directory in
// the desktop file manager. Empty command means the platform is unsupported.
func openFolderCommand(target string) (string, []string) {
	switch runtime.GOOS {
	case "darwin":
		return "open", []string{target}
	case "windows":
		return "cmd", []string{"/c", "start", "", target}
	case "linux":
		return "xdg-open", []string{target}
	default:
		return "", nil
	}
}
