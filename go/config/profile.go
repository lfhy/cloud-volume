// Profile management for multi-gateway support.
// Profiles are stored as JSON values in a single bbolt DB (config.db).
// On first open, legacy TOML files are migrated automatically.
//
// The public API (SaveProfile, LoadProfile, ListProfiles, etc.) is unchanged
// from the TOML era so callers in bridge/ and go/storage/ don't need updates.

package config

import (
	bolt "go.etcd.io/bbolt"
	"path/filepath"
	"strings"
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
	// Disabled reports the account's opt-out state. A disabled account is kept
	// in the list (so the user can re-enable it) but skipped by the file manager
	// and P2P.
	Disabled bool `json:"disabled"`
}

// Constants shared across the old TOML layout and the new bbolt layout.
const (
	profilesDir           = "profiles"
	activeProfileFileName = "active_profile"
	defaultProfileName    = "default"
)

// SaveProfile persists a config under a named profile (bbolt).
func SaveProfile(name string, config RemoteStorageConfig) error {
	normalized := config.Normalized().WithDefaultWebDAVCredentials()
	return saveProfileToDB(name, normalized)
}

// LoadProfile reads a config for a named profile (bbolt).
func LoadProfile(name string) (RemoteStorageConfig, error) {
	return loadProfileFromDB(name)
}

// ListProfiles returns all stored profiles (bbolt).
func ListProfiles() ([]ProfileInfo, error) {
	return listProfilesFromDB()
}

// DeleteProfile removes a profile from bbolt.
func DeleteProfile(name string) error {
	cleanName := sanitizeProfileName(name)
	if err := deleteProfileFromDB(cleanName); err != nil {
		return err
	}
	// If the deleted profile was active, clear the marker.
	activeName, err := activeProfileName()
	if err != nil {
		return err
	}
	if activeName == cleanName {
		db, release, err := acquireConfigDB()
		if err != nil {
			return err
		}
		defer release()
		_ = db.Update(func(tx *bolt.Tx) error {
			return tx.Bucket(metaBucketKey).Delete(activeProfileKey)
		})
	}
	return nil
}

// SetActiveProfile stores the selected profile in bbolt.
func SetActiveProfile(name string) error {
	return setActiveProfileInDB(name)
}

// ActiveProfileName returns the selected profile name.
func ActiveProfileName() (string, error) {
	return activeProfileName()
}

// ResetAllProfiles removes every stored account, leaving the app in a
// first-run state.
func ResetAllProfiles() error {
	return resetAllProfilesInDB()
}

// MigrateDefault is a no-op kept for backward compatibility with bridge
// callers. The TOML→bbolt migration now happens automatically when the
// process-wide config DB handle is first created.
func MigrateDefault() error {
	// Trigger DB creation + migration if not done yet.
	_, release, err := acquireConfigDB()
	if err != nil {
		return err
	}
	defer release()
	return nil
}

// ProfilesDir returns the legacy profiles directory path (used during migration).
func ProfilesDir() (string, error) {
	rootPath, err := appDataRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, profilesDir), nil
}

// ProfileConfigPath returns the legacy TOML path for a profile (used during migration).
func ProfileConfigPath(name string) (string, error) {
	dir, err := ProfilesDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, profileFileName(name)), nil
}

// ActiveProfilePath returns the legacy active-profile marker file path (migration only).
func ActiveProfilePath() (string, error) {
	rootPath, err := appDataRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, activeProfileFileName), nil
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
	cleanName = cleanName[strings.LastIndexByte(cleanName, '/')+1:]
	cleanName = cleanName[strings.LastIndexByte(cleanName, '\\')+1:]
	cleanName = strings.TrimSuffix(cleanName, ".toml")
	return strings.TrimSpace(cleanName)
}
