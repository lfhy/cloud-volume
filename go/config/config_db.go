// Config persistence backed by a single bbolt DB file. Each profile is stored
// as a JSON-encoded RemoteStorageConfig under the "profiles" bucket, keyed by
// profile name. The active profile name lives in the "meta" bucket.
//
// On first open, if the DB does not yet exist, all legacy TOML files under
// the profiles/ directory are imported and then deleted so the migration is
// one-way and idempotent.
package config

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"

	bolt "go.etcd.io/bbolt"
)

const (
	configDBFileName = "config.db"
)

var (
	profilesBucketKey = []byte("profiles")
	metaBucketKey     = []byte("meta")
	activeProfileKey  = []byte("active_profile")
)

// configDBPath returns the path to the bbolt config database.
func configDBPath() (string, error) {
	root, err := appDataRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(root, configDBFileName), nil
}

// migrateTomlToBbolt reads all legacy TOML profile files and the legacy
// default config, imports them into bbolt, then removes the old files.
func migrateTomlToBbolt(db *bolt.DB) error {
	type tomProfile struct {
		name   string
		config RemoteStorageConfig
	}

	var imported []tomProfile

	// 0. Migrate legacy ~/.remote-storage root to ~/.cloud-volume first.
	_ = migrateLegacyConfigRoot()

	// 1. Try the legacy profiles/ directory.
	profilesDir, err := ProfilesDir()
	if err == nil {
		entries, err := os.ReadDir(profilesDir)
		if err == nil {
			for _, e := range entries {
				if e.IsDir() {
					continue
				}
				name := e.Name()
				if filepath.Ext(name) != ".toml" {
					continue
				}
				profileName := name[:len(name)-len(".toml")]
				path := filepath.Join(profilesDir, name)
				cfg, err := NewStore(path).Load()
				if err != nil {
					continue
				}
				imported = append(imported, tomProfile{profileName, cfg})
			}
		}
	}

	// 2. Try the legacy default config.toml.
	defaultPath, err := DefaultConfigPath()
	if err == nil && pathExists(defaultPath) {
		cfg, err := NewStore(defaultPath).Load()
		if err == nil && cfg.IsConfigured() {
			// Only import if not already imported via profiles/.
			alreadyExists := false
			for _, p := range imported {
				if p.name == defaultProfileName {
					alreadyExists = true
					break
				}
			}
			if !alreadyExists {
				imported = append(imported, tomProfile{defaultProfileName, cfg})
			}
		}
	}

	if len(imported) == 0 {
		return nil
	}

	// Write all imported profiles into bbolt.
	if err := db.Update(func(tx *bolt.Tx) error {
		bucket := tx.Bucket(profilesBucketKey)
		for _, p := range imported {
			data, err := json.Marshal(p.config)
			if err != nil {
				continue
			}
			_ = bucket.Put([]byte(p.name), data)
		}
		// Preserve the legacy active profile marker.
		metaBucket := tx.Bucket(metaBucketKey)
		if existing := metaBucket.Get(activeProfileKey); len(existing) == 0 {
			activeName, _ := legacyActiveProfileName()
			if activeName == "" {
				activeName = defaultProfileName
			}
			_ = metaBucket.Put(activeProfileKey, []byte(activeName))
		}
		return nil
	}); err != nil {
		return err
	}

	// Clean up old TOML files after successful import.
	_ = removeDirIfExists(profilesDir)
	_ = removeFileIfExists(defaultPath)
	// Also remove legacy active_profile marker file.
	if root, err := appDataRoot(); err == nil {
		_ = os.Remove(filepath.Join(root, activeProfileFileName))
	}

	return nil
}

// ── Public API (replaces TOML-backed functions) ──────────────────────────────

// saveProfileToDB stores a config under a named profile in bbolt.
func saveProfileToDB(name string, config RemoteStorageConfig) error {
	cleanName := sanitizeProfileName(name)
	if cleanName == "" {
		return fmt.Errorf("profile name is empty")
	}
	db, release, err := acquireConfigDB()
	if err != nil {
		return err
	}
	if err := db.Update(func(tx *bolt.Tx) error {
		bucket := tx.Bucket(profilesBucketKey)
		ensureProfileIdentity(bucket, cleanName, &config)
		data, err := json.Marshal(config)
		if err != nil {
			return fmt.Errorf("encode profile: %w", err)
		}
		if err := bucket.Put([]byte(cleanName), data); err != nil {
			return err
		}
		return appendProfileToOrderIfNeeded(tx, cleanName)
	}); err != nil {
		release()
		return err
	}
	release()
	notifyProfileMutation()
	return nil
}

// loadProfileFromDB reads a config for a named profile from bbolt.
func loadProfileFromDB(name string) (RemoteStorageConfig, error) {
	cleanName := sanitizeProfileName(name)
	db, release, err := acquireConfigDB()
	if err != nil {
		return DefaultConfig(), err
	}
	defer release()
	var config RemoteStorageConfig
	err = db.Update(func(tx *bolt.Tx) error {
		bucket := tx.Bucket(profilesBucketKey)
		data := bucket.Get([]byte(cleanName))
		if data == nil {
			return fmt.Errorf("profile %q not found", cleanName)
		}
		if err := json.Unmarshal(data, &config); err != nil {
			return fmt.Errorf("decode profile: %w", err)
		}
		// Backfill migrated/legacy profiles so metadata namespaces never
		// depend on the unversioned fallback identity.
		ensureProfileIdentity(bucket, cleanName, &config)
		if config.ProfileID == "" {
			return nil
		}
		encoded, err := json.Marshal(config)
		if err != nil {
			return fmt.Errorf("encode profile: %w", err)
		}
		return bucket.Put([]byte(cleanName), encoded)
	})
	if err != nil {
		return DefaultConfig(), err
	}
	return config, nil
}

// listProfilesFromDB returns all stored profiles from bbolt.
func listProfilesFromDB() ([]ProfileInfo, error) {
	db, release, err := acquireConfigDB()
	if err != nil {
		return nil, err
	}
	defer release()

	activeName := activeProfileNameFromDB(db)

	var result []ProfileInfo
	var order []string
	err = db.View(func(tx *bolt.Tx) error {
		bucket := tx.Bucket(profilesBucketKey)
		if err := bucket.ForEach(func(key, val []byte) error {
			name := string(key)
			var config RemoteStorageConfig
			if err := json.Unmarshal(val, &config); err != nil {
				return nil // skip corrupted entries
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
				Disabled:     normalized.Disabled,
			})
			return nil
		}); err != nil {
			return err
		}
		order = loadProfileOrder(tx)
		return nil
	})
	if err != nil {
		return nil, err
	}
	if result == nil {
		result = []ProfileInfo{}
	}
	if len(order) > 0 {
		result = applyNamedOrder(result, order, func(p ProfileInfo) string { return p.Name })
	} else {
		sort.Slice(result, func(i, j int) bool {
			if result[i].Active != result[j].Active {
				return result[i].Active
			}
			if result[i].Name == defaultProfileName {
				return true
			}
			if result[j].Name == defaultProfileName {
				return false
			}
			return result[i].Name < result[j].Name
		})
	}
	return result, nil
}

// deleteProfileFromDB removes a profile from bbolt.
func deleteProfileFromDB(name string) error {
	cleanName := sanitizeProfileName(name)
	db, release, err := acquireConfigDB()
	if err != nil {
		return err
	}
	defer release()
	return db.Update(func(tx *bolt.Tx) error {
		bucket := tx.Bucket(profilesBucketKey)
		if err := bucket.Delete([]byte(cleanName)); err != nil {
			return err
		}
		if err := removeProfileFromOrder(tx, cleanName); err != nil {
			return err
		}
		return removeBucketsForProfile(tx, cleanName)
	})
}

// activeProfileNameFromDB reads the active profile name from bbolt.
func activeProfileNameFromDB(db *bolt.DB) string {
	var name string
	_ = db.View(func(tx *bolt.Tx) error {
		metaBucket := tx.Bucket(metaBucketKey)
		data := metaBucket.Get(activeProfileKey)
		if len(data) > 0 {
			name = string(data)
		}
		return nil
	})
	if name == "" {
		return defaultProfileName
	}
	return name
}

// setActiveProfileInDB stores the active profile name in bbolt.
func setActiveProfileInDB(name string) error {
	cleanName := sanitizeProfileName(name)
	if cleanName == "" {
		return fmt.Errorf("profile name is empty")
	}
	db, release, err := acquireConfigDB()
	if err != nil {
		return err
	}
	defer release()
	return db.Update(func(tx *bolt.Tx) error {
		// Verify the profile exists.
		bucket := tx.Bucket(profilesBucketKey)
		if bucket.Get([]byte(cleanName)) == nil {
			return fmt.Errorf("profile %q not found", cleanName)
		}
		metaBucket := tx.Bucket(metaBucketKey)
		return metaBucket.Put(activeProfileKey, []byte(cleanName))
	})
}

// activeProfileName reads the active profile name, opening the DB as needed.
func activeProfileName() (string, error) {
	db, release, err := acquireConfigDB()
	if err != nil {
		return defaultProfileName, err
	}
	defer release()
	return activeProfileNameFromDB(db), nil
}

// resetAllProfilesInDB removes every stored account from bbolt.
func resetAllProfilesInDB() error {
	db, release, err := acquireConfigDB()
	if err != nil {
		return err
	}
	defer release()
	return db.Update(func(tx *bolt.Tx) error {
		if err := tx.DeleteBucket(profilesBucketKey); err != nil && err != bolt.ErrBucketNotFound {
			return err
		}
		if _, err := tx.CreateBucket(profilesBucketKey); err != nil {
			return err
		}
		metaBucket := tx.Bucket(metaBucketKey)
		if err := metaBucket.Delete(activeProfileKey); err != nil {
			return err
		}
		return clearListOrders(tx)
	})
}

// legacyActiveProfileName reads the old active_profile text file (migration only).
func legacyActiveProfileName() (string, error) {
	path, err := ActiveProfilePath()
	if err != nil {
		return "", err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	name := sanitizeProfileName(string(data))
	if name == "" {
		return defaultProfileName, nil
	}
	return name, nil
}

// migrateLegacyConfigRoot moves old ~/.remote-storage config files to the
// current ~/.cloud-volume root before the TOML→bbolt import.
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

func copyProfileFilesIfMissing(srcDir, dstDir string) error {
	entries, err := os.ReadDir(srcDir)
	if err != nil {
		return nil // src doesn't exist, nothing to migrate
	}
	if err := os.MkdirAll(dstDir, 0o700); err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".toml" {
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
