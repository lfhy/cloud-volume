package config

import (
	"os"
	"path/filepath"
	"testing"
)

// Profile migration tests protect upgrades from the old Remote Storage data root.
func TestMigrateDefaultCopiesLegacyConfigToCloudVolumeProfile(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	legacyConfigPath := filepath.Join(home, legacyConfigDirName, configFileName)
	if err := os.MkdirAll(filepath.Dir(legacyConfigPath), 0o700); err != nil {
		t.Fatalf("create legacy config dir: %v", err)
	}
	payload := []byte("endpoint = \"https://legacy.example\"\naccess_key_id = \"ak\"\nsecret_access_key = \"sk\"\n")
	if err := os.WriteFile(legacyConfigPath, payload, 0o600); err != nil {
		t.Fatalf("write legacy config: %v", err)
	}

	if err := MigrateDefault(); err != nil {
		t.Fatalf("MigrateDefault returned error: %v", err)
	}

	defaultPath, err := DefaultConfigPath()
	if err != nil {
		t.Fatalf("DefaultConfigPath returned error: %v", err)
	}
	assertFileBytes(t, defaultPath, payload)

	profilePath, err := ProfileConfigPath("default")
	if err != nil {
		t.Fatalf("ProfileConfigPath returned error: %v", err)
	}
	assertFileBytes(t, profilePath, payload)
	assertPathMissing(t, legacyConfigPath)
}

func TestMigrateDefaultCopiesLegacyProfiles(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	legacyProfilePath := filepath.Join(home, legacyConfigDirName, profilesDir, "default.toml")
	if err := os.MkdirAll(filepath.Dir(legacyProfilePath), 0o700); err != nil {
		t.Fatalf("create legacy profiles dir: %v", err)
	}
	payload := []byte("endpoint = \"https://profile.example\"\naccess_key_id = \"ak\"\nsecret_access_key = \"sk\"\n")
	if err := os.WriteFile(legacyProfilePath, payload, 0o600); err != nil {
		t.Fatalf("write legacy profile: %v", err)
	}

	if err := MigrateDefault(); err != nil {
		t.Fatalf("MigrateDefault returned error: %v", err)
	}

	defaultPath, err := DefaultConfigPath()
	if err != nil {
		t.Fatalf("DefaultConfigPath returned error: %v", err)
	}
	assertFileBytes(t, defaultPath, payload)

	profilePath, err := ProfileConfigPath("default")
	if err != nil {
		t.Fatalf("ProfileConfigPath returned error: %v", err)
	}
	assertFileBytes(t, profilePath, payload)
	assertPathMissing(t, legacyProfilePath)
}

func TestDeleteDefaultProfileRemovesMigratableSources(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	config := validTestConfig()
	if err := SaveProfile("default", config); err != nil {
		t.Fatalf("SaveProfile returned error: %v", err)
	}
	defaultPath, err := DefaultConfigPath()
	if err != nil {
		t.Fatalf("DefaultConfigPath returned error: %v", err)
	}
	legacyConfigPath := filepath.Join(home, legacyConfigDirName, configFileName)
	legacyProfilePath := filepath.Join(home, legacyConfigDirName, profilesDir, "default.toml")
	for _, path := range []string{defaultPath, legacyConfigPath, legacyProfilePath} {
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			t.Fatalf("create dir for %s: %v", path, err)
		}
		if err := os.WriteFile(path, []byte("endpoint = \"https://old.example\"\n"), 0o600); err != nil {
			t.Fatalf("write %s: %v", path, err)
		}
	}

	if err := DeleteProfile("default"); err != nil {
		t.Fatalf("DeleteProfile returned error: %v", err)
	}
	if err := MigrateDefault(); err != nil {
		t.Fatalf("MigrateDefault returned error: %v", err)
	}

	profiles, err := ListProfiles()
	if err != nil {
		t.Fatalf("ListProfiles returned error: %v", err)
	}
	if len(profiles) != 0 {
		t.Fatalf("profiles = %v, want empty", profiles)
	}
	for _, path := range []string{defaultPath, legacyConfigPath, legacyProfilePath} {
		assertPathMissing(t, path)
	}
}

func validTestConfig() RemoteStorageConfig {
	return RemoteStorageConfig{
		Endpoint:           "https://current.example",
		AccessKeyID:        "ak",
		SecretAccessKey:    "sk",
		HasSecretAccessKey: true,
	}
}

func assertFileBytes(t *testing.T, path string, want []byte) {
	t.Helper()

	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if string(got) != string(want) {
		t.Fatalf("%s = %q, want %q", path, string(got), string(want))
	}
}

func assertPathMissing(t *testing.T, path string) {
	t.Helper()

	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("%s still exists or stat failed with %v", path, err)
	}
}
