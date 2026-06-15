package config

import (
	"path/filepath"
	"strings"
)

const (
	runtimeDirName = "runtime"
	cacheDirName   = "cache"
)

// RuntimeDir returns the runtime directory used for mount state, temporary
// transfer buffers, and other non-config app data.
func RuntimeDir() (string, error) {
	rootPath, err := appDataRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, runtimeDirName), nil
}

// DefaultCacheDir returns the cache root under the platform app work path.
func DefaultCacheDir() (string, error) {
	rootPath, err := appDataRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, cacheDirName), nil
}

// ResolveCacheDir applies the configured cache override or falls back to workpath/cache.
func ResolveCacheDir(config RemoteStorageConfig) (string, error) {
	cacheDir := strings.TrimSpace(config.CacheDirectory)
	if cacheDir != "" {
		return filepath.Clean(cacheDir), nil
	}
	return DefaultCacheDir()
}

// MountRuntimeDir returns the directory used by mount helpers for cache files
// and per-bucket WebDAV buffer state.
func MountRuntimeDir() (string, error) {
	runtimeDir, err := RuntimeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(runtimeDir, "mounts"), nil
}

// LogsRuntimeDir returns the directory used for bridge and mount diagnostics.
func LogsRuntimeDir() (string, error) {
	runtimeDir, err := RuntimeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(runtimeDir, "logs"), nil
}

// BridgeLogPath points to the append-only Go bridge log file used during desktop runs.
func BridgeLogPath() (string, error) {
	logsDir, err := LogsRuntimeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(logsDir, "bridge.log"), nil
}
