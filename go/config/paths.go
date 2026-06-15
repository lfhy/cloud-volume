package config

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

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
func appDataRoot() (string, error) {
	if runtime.GOOS == "windows" {
		exePath, err := os.Executable()
		if err != nil {
			return "", fmt.Errorf("resolve executable path: %w", err)
		}
		return filepath.Dir(exePath), nil
	}

	homePath, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home: %w", err)
	}
	return filepath.Join(homePath, configDirName), nil
}

// legacyAppDataRoot returns the pre-Cloud Volume config root for upgrades.
func legacyAppDataRoot() (string, error) {
	homePath, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home: %w", err)
	}
	return filepath.Join(homePath, legacyConfigDirName), nil
}
