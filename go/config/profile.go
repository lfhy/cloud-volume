// Profile management for multi-gateway support.
// Profiles live under the same app data root as the active config file.
// The default profile is named "default" and maps to the existing config.toml.

package config

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const (
	profilesDir           = "profiles"
	activeProfileFileName = "active_profile"
	defaultProfileName    = "default"
)

// ProfileInfo describes a stored profile for Flutter.
type ProfileInfo struct {
	Name         string `json:"name"`
	DisplayName  string `json:"displayName"`
	StorageType  string `json:"storageType"`
	ProviderType string `json:"providerType"`
	Endpoint     string `json:"endpoint"`
	AccessKeyID  string `json:"accessKeyId"`
	Active       bool   `json:"active"`
}

// ProfilesDir returns the path to the profile config directory.
func ProfilesDir() (string, error) {
	rootPath, err := appDataRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, profilesDir), nil
}

// ProfileConfigPath returns the config file path for a named profile.
func ProfileConfigPath(name string) (string, error) {
	dir, err := ProfilesDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, profileFileName(name)), nil
}

// ActiveProfilePath returns the file that stores the selected profile name.
func ActiveProfilePath() (string, error) {
	rootPath, err := appDataRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, activeProfileFileName), nil
}

// MigrateDefault moves legacy config files into the current default locations.
func MigrateDefault() error {
	if err := migrateLegacyConfigRoot(); err != nil {
		return err
	}

	defaultPath, err := DefaultConfigPath()
	if err != nil {
		return err
	}
	dir, err := ProfilesDir()
	if err != nil {
		return err
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	defaultProfilePath := filepath.Join(dir, profileFileName(defaultProfileName))
	if pathExists(defaultProfilePath) || !pathExists(defaultPath) {
		return nil
	}
	return copyFileIfMissing(defaultPath, defaultProfilePath)
}

// ActiveProfileName returns the selected profile name, falling back to default.
func ActiveProfileName() (string, error) {
	path, err := ActiveProfilePath()
	if err != nil {
		return "", err
	}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return defaultProfileName, nil
	}
	if err != nil {
		return "", err
	}
	name := sanitizeProfileName(string(data))
	if name == "" {
		return defaultProfileName, nil
	}
	return name, nil
}

// SetActiveProfile persists the selected profile for the next bootstrap.
func SetActiveProfile(name string) error {
	cleanName := sanitizeProfileName(name)
	if cleanName == "" {
		return errors.New("profile name is empty")
	}
	path, err := ProfileConfigPath(cleanName)
	if err != nil {
		return err
	}
	if !pathExists(path) {
		return os.ErrNotExist
	}
	activePath, err := ActiveProfilePath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(activePath), 0o700); err != nil {
		return err
	}
	return os.WriteFile(activePath, []byte(cleanName+"\n"), 0o600)
}

// ListProfiles returns all stored profile names and management metadata.
func ListProfiles() ([]ProfileInfo, error) {
	dir, err := ProfilesDir()
	if err != nil {
		return nil, err
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	activeName, err := ActiveProfileName()
	if err != nil {
		return nil, err
	}

	var result []ProfileInfo
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".toml") {
			continue
		}
		name := strings.TrimSuffix(e.Name(), ".toml")
		config, err := LoadProfile(name)
		if err != nil {
			return nil, err
		}
		normalized := config.Normalized()
		result = append(result, ProfileInfo{
			Name:         name,
			DisplayName:  normalized.AccountLabel(name),
			StorageType:  normalized.StorageType,
			ProviderType: normalized.ProviderType,
			Endpoint:     normalized.Endpoint,
			AccessKeyID:  normalized.AccessKeyID,
			Active:       name == activeName,
		})
	}

	if result == nil {
		result = []ProfileInfo{}
	}

	sort.Slice(result, func(i, j int) bool {
		if result[i].Active != result[j].Active {
			return result[i].Active
		}
		if result[i].Name == defaultProfileName {
			return true
		}
		return result[i].Name < result[j].Name
	})

	return result, nil
}

// SaveProfile persists a config under a named profile.
func SaveProfile(name string, config RemoteStorageConfig) error {
	cleanName := sanitizeProfileName(name)
	if cleanName == "" {
		return errors.New("profile name is empty")
	}
	path, err := ProfileConfigPath(cleanName)
	if err != nil {
		return err
	}
	return NewStore(path).Save(config)
}

// LoadProfile reads a config for a named profile.
func LoadProfile(name string) (RemoteStorageConfig, error) {
	path, err := ProfileConfigPath(sanitizeProfileName(name))
	if err != nil {
		return DefaultConfig(), err
	}
	return NewStore(path).Load()
}

// DeleteProfile removes a profile file and any legacy source that could restore it.
func DeleteProfile(name string) error {
	cleanName := sanitizeProfileName(name)
	path, err := ProfileConfigPath(cleanName)
	if err != nil {
		return err
	}
	if err := removeFileIfExists(path); err != nil {
		return err
	}
	if cleanName == defaultProfileName {
		if err := deleteDefaultProfileSources(); err != nil {
			return err
		}
	}
	activeName, err := ActiveProfileName()
	if err != nil {
		return err
	}
	if activeName == cleanName {
		if activePath, err := ActiveProfilePath(); err == nil {
			_ = os.Remove(activePath)
		}
	}
	return nil
}

func deleteDefaultProfileSources() error {
	defaultPath, err := DefaultConfigPath()
	if err != nil {
		return err
	}
	if err := removeFileIfExists(defaultPath); err != nil {
		return err
	}
	legacyRoot, err := legacyAppDataRoot()
	if err != nil {
		return err
	}
	legacyPaths := []string{
		filepath.Join(legacyRoot, configFileName),
		filepath.Join(legacyRoot, profilesDir, profileFileName(defaultProfileName)),
	}
	for _, path := range legacyPaths {
		if err := removeFileIfExists(path); err != nil {
			return err
		}
	}
	return nil
}

func migrateLegacyConfigRoot() error {
	legacyRoot, err := legacyAppDataRoot()
	if err != nil {
		return err
	}
	currentRoot, err := appDataRoot()
	if err != nil {
		return err
	}
	if filepath.Clean(legacyRoot) == filepath.Clean(currentRoot) {
		return nil
	}

	currentConfigPath, err := DefaultConfigPath()
	if err != nil {
		return err
	}
	legacyConfigPath := filepath.Join(legacyRoot, configFileName)
	legacyDefaultProfilePath := filepath.Join(legacyRoot, profilesDir, profileFileName(defaultProfileName))
	if pathExists(legacyConfigPath) {
		if err := moveFileToMissingDestination(legacyConfigPath, currentConfigPath); err != nil {
			return err
		}
	} else if pathExists(legacyDefaultProfilePath) {
		if err := moveFileToMissingDestination(legacyDefaultProfilePath, currentConfigPath); err != nil {
			return err
		}
	}

	legacyProfilesDir := filepath.Join(legacyRoot, profilesDir)
	currentProfilesDir, err := ProfilesDir()
	if err != nil {
		return err
	}
	return copyProfileFilesIfMissing(legacyProfilesDir, currentProfilesDir)
}

func profileFileName(name string) string {
	cleanName := sanitizeProfileName(name)
	if cleanName == "" {
		cleanName = defaultProfileName
	}
	return cleanName + ".toml"
}

func sanitizeProfileName(name string) string {
	cleanName := strings.TrimSpace(name)
	cleanName = filepath.Base(cleanName)
	cleanName = strings.TrimSuffix(cleanName, ".toml")
	return strings.TrimSpace(cleanName)
}

func copyProfileFilesIfMissing(srcDir, dstDir string) error {
	entries, err := os.ReadDir(srcDir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dstDir, 0o700); err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".toml") {
			continue
		}
		src := filepath.Join(srcDir, entry.Name())
		dst := filepath.Join(dstDir, entry.Name())
		if err := moveFileToMissingDestination(src, dst); err != nil {
			return err
		}
	}
	return nil
}

func moveFileToMissingDestination(src, dst string) error {
	if !pathExists(src) {
		return nil
	}
	if !pathExists(dst) {
		if err := copyFileIfMissing(src, dst); err != nil {
			return err
		}
	}
	return removeFileIfExists(src)
}

func copyFileIfMissing(src, dst string) error {
	if pathExists(dst) {
		return nil
	}
	input, err := os.Open(src)
	if err != nil {
		return err
	}
	defer input.Close()

	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return err
	}
	output, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}

	if _, err := io.Copy(output, input); err != nil {
		_ = output.Close()
		return err
	}
	return output.Close()
}

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
