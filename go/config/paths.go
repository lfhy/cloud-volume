package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
)

var appDataRootOverride struct {
	sync.RWMutex
	path string
}

const (
	configDirName       = ".cloud-volume"
	legacyConfigDirName = ".remote-storage"
	configFileName      = "config.toml"
)

// DefaultConfigPath resolves the TOML path used by the desktop app and CLI.
func DefaultConfigPath() (string, error) {
	rootPath, err := appDataRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, configFileName), nil
}

// appDataRoot returns the root folder for config and runtime data.
// On every platform it lives under the user home directory (e.g. ~/.cloud-volume),
// which keeps Windows from needing write access to the (often Program Files)
// install directory.
func appDataRoot() (string, error) {
	appDataRootOverride.RLock()
	override := appDataRootOverride.path
	appDataRootOverride.RUnlock()
	if override != "" {
		return override, nil
	}
	homePath, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home: %w", err)
	}
	return filepath.Join(homePath, configDirName), nil
}

// SetAppDataRoot lets mobile hosts provide their private writable directory.
func SetAppDataRoot(root string) error {
	root = strings.TrimSpace(root)
	if root == "" {
		return fmt.Errorf("app data root is empty")
	}
	appDataRootOverride.Lock()
	appDataRootOverride.path = filepath.Clean(root)
	appDataRootOverride.Unlock()
	return nil
}

// legacyAppDataRoot returns the pre-Cloud Volume config root for upgrades.
// On Windows it additionally covers the install-dir layout used by older
// Cloud Volume builds, where config/runtime/cache lived next to cloud-volume.exe.
func legacyAppDataRoot() (string, error) {
	homePath, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home: %w", err)
	}
	legacyRoot := filepath.Join(homePath, legacyConfigDirName)
	if pathExists(filepath.Join(legacyRoot, configFileName)) ||
		pathExists(filepath.Join(legacyRoot, profilesDir)) {
		return legacyRoot, nil
	}
	if runtime.GOOS == "windows" {
		if installRoot, err := windowsInstallRoot(); err == nil && installRoot != "" {
			return installRoot, nil
		}
	}
	return legacyRoot, nil
}

// windowsInstallRoot returns the directory holding cloud-volume.exe, used to
// migrate config/runtime data emitted by older Windows installs that wrote
// alongside the executable.
func windowsInstallRoot() (string, error) {
	exePath, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("resolve executable path: %w", err)
	}
	return filepath.Dir(exePath), nil
}

// AppDataRoot returns the platform application-data directory that hosts the
// config TOML, profiles, sync settings, and runtime data. Exposed so sibling
// packages (e.g. the sync store) can place their files alongside config.
func AppDataRoot() (string, error) {
	return appDataRoot()
}

// pathExists reports whether a file or directory exists.
func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func removeFileIfExists(path string) error {
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func removeDirIfExists(path string) error {
	if err := os.RemoveAll(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}
