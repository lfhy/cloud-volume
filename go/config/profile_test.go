package config

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func setTestHome(t *testing.T, home string) {
	t.Helper()
	if err := switchConfigDBRoot(nil); err != nil {
		t.Fatalf("close shared config db before HOME switch: %v", err)
	}
	t.Setenv("HOME", home)
	if runtime.GOOS == "windows" {
		t.Setenv("USERPROFILE", home)
	}
	t.Cleanup(func() {
		if err := switchConfigDBRoot(nil); err != nil {
			t.Errorf("close shared config db after HOME test: %v", err)
		}
	})
}

func validTestConfig() RemoteStorageConfig {
	return RemoteStorageConfig{
		Endpoint:           "https://current.example",
		AccessKeyID:        "ak",
		SecretAccessKey:    "sk",
		HasSecretAccessKey: true,
	}
}

func assertPathMissing(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("%s still exists or stat failed with %v", path, err)
	}
}

// MigrateDefault now imports legacy TOML into bbolt and deletes the old files.
func TestMigrateDefaultImportsLegacyConfig(t *testing.T) {
	home := t.TempDir()
	setTestHome(t, home)

	legacyConfigPath := filepath.Join(home, legacyConfigDirName, configFileName)
	os.MkdirAll(filepath.Dir(legacyConfigPath), 0o700)
	os.WriteFile(legacyConfigPath,
		[]byte("endpoint = \"https://legacy.example\"\naccess_key_id = \"ak\"\nsecret_access_key = \"sk\"\n"), 0o600)

	if err := MigrateDefault(); err != nil {
		t.Fatalf("MigrateDefault returned error: %v", err)
	}

	// Profile should be in bbolt now.
	profiles, err := ListProfiles()
	if err != nil {
		t.Fatalf("ListProfiles returned error: %v", err)
	}
	if len(profiles) != 1 {
		t.Fatalf("expected 1 profile after migration, got %d", len(profiles))
	}
	if profiles[0].Endpoint != "https://legacy.example" {
		t.Fatalf("unexpected endpoint %q", profiles[0].Endpoint)
	}
	// Old config files should be cleaned up.
	assertPathMissing(t, legacyConfigPath)
}

func TestMigrateDefaultImportsLegacyProfilesDir(t *testing.T) {
	home := t.TempDir()
	setTestHome(t, home)

	profileDir := filepath.Join(home, configDirName, profilesDir)
	profilePath := filepath.Join(profileDir, "myaccount.toml")
	os.MkdirAll(profileDir, 0o700)
	os.WriteFile(profilePath,
		[]byte("endpoint = \"https://profile.example\"\naccess_key_id = \"ak\"\nsecret_access_key = \"sk\"\n"), 0o600)

	if err := MigrateDefault(); err != nil {
		t.Fatalf("MigrateDefault returned error: %v", err)
	}

	profiles, err := ListProfiles()
	if err != nil {
		t.Fatalf("ListProfiles returned error: %v", err)
	}
	if len(profiles) != 1 {
		t.Fatalf("expected 1 profile, got %d", len(profiles))
	}
	if profiles[0].Name != "myaccount" {
		t.Fatalf("unexpected profile name %q", profiles[0].Name)
	}
	assertPathMissing(t, profilePath)
}

func TestSaveLoadDeleteProfile(t *testing.T) {
	home := t.TempDir()
	setTestHome(t, home)

	cfg := validTestConfig()
	if err := SaveProfile("alpha", cfg); err != nil {
		t.Fatalf("SaveProfile returned error: %v", err)
	}

	loaded, err := LoadProfile("alpha")
	if err != nil {
		t.Fatalf("LoadProfile returned error: %v", err)
	}
	if loaded.Endpoint != "https://current.example" {
		t.Fatalf("unexpected endpoint %q", loaded.Endpoint)
	}

	profiles, err := ListProfiles()
	if err != nil {
		t.Fatalf("ListProfiles returned error: %v", err)
	}
	if len(profiles) != 1 || profiles[0].Name != "alpha" {
		t.Fatalf("unexpected profiles: %v", profiles)
	}

	if err := DeleteProfile("alpha"); err != nil {
		t.Fatalf("DeleteProfile returned error: %v", err)
	}

	profiles, _ = ListProfiles()
	if len(profiles) != 0 {
		t.Fatalf("expected 0 profiles after delete, got %d", len(profiles))
	}
}

func TestSetActiveProfile(t *testing.T) {
	home := t.TempDir()
	setTestHome(t, home)

	if err := SaveProfile("alpha", validTestConfig()); err != nil {
		t.Fatalf("SaveProfile alpha: %v", err)
	}
	if err := SaveProfile("beta", validTestConfig()); err != nil {
		t.Fatalf("SaveProfile beta: %v", err)
	}
	if err := SetActiveProfile("beta"); err != nil {
		t.Fatalf("SetActiveProfile: %v", err)
	}

	active, err := ActiveProfileName()
	if err != nil {
		t.Fatalf("ActiveProfileName: %v", err)
	}
	if active != "beta" {
		t.Fatalf("expected active profile beta, got %q", active)
	}

	profiles, _ := ListProfiles()
	for _, p := range profiles {
		if p.Name == "beta" && !p.Active {
			t.Fatalf("beta should be active")
		}
	}
}

func TestResetAllProfiles(t *testing.T) {
	home := t.TempDir()
	setTestHome(t, home)

	SaveProfile("alpha", validTestConfig())
	SetActiveProfile("alpha")

	if err := ResetAllProfiles(); err != nil {
		t.Fatalf("ResetAllProfiles: %v", err)
	}

	profiles, _ := ListProfiles()
	if len(profiles) != 0 {
		t.Fatalf("expected 0 profiles after reset, got %d", len(profiles))
	}
}
