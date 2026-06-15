package config

import (
	"path/filepath"
	"testing"
)

// Store tests lock down the first-run contract before the Flutter shell depends on it.
func TestLoadBootstrapStateForMissingFile(t *testing.T) {
	store := NewStore(filepath.Join(t.TempDir(), "config.toml"))

	state, err := store.LoadBootstrapState()
	if err != nil {
		t.Fatalf("LoadBootstrapState returned error: %v", err)
	}

	if state.Configured {
		t.Fatalf("expected missing config to be unconfigured")
	}
	if !state.Config.UsePathStyle {
		t.Fatalf("expected default config to enable path-style access")
	}
	if !state.Config.HideDotFiles {
		t.Fatalf("expected default config to hide dot files")
	}
	if filepath.Base(state.Config.ResolvedCacheDirectory) != "cache" {
		t.Fatalf("expected default resolved cache dir to end in cache, got %q", state.Config.ResolvedCacheDirectory)
	}
	if state.Config.CacheDirectory != "" {
		t.Fatalf("expected stored cache directory to stay empty, got %q", state.Config.CacheDirectory)
	}
}

func TestSaveAndLoadRoundTrip(t *testing.T) {
	store := NewStore(filepath.Join(t.TempDir(), "config.toml"))
	cacheDir := filepath.Join(t.TempDir(), "custom-cache")
	input := RemoteStorageConfig{
		Endpoint:                 " https://s3.example.com ",
		Region:                   " us-east-1 ",
		Bucket:                   " media-bucket ",
		AccessKeyID:              " ACCESS ",
		SecretAccessKey:          " SECRET ",
		RootPrefix:               " /music/archive/ ",
		DefaultDownloadDirectory: " /Users/demo/Downloads/remote-storage ",
		CacheDirectory:           " " + cacheDir + " ",
		HideDotFiles:             true,
		UsePathStyle:             true,
		WindowsMountMode:         WindowsMountModeCloudFilesDirect,
	}

	if err := store.Save(input); err != nil {
		t.Fatalf("Save returned error: %v", err)
	}

	loaded, err := store.Load()
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	if loaded.Endpoint != "https://s3.example.com" {
		t.Fatalf("unexpected endpoint %q", loaded.Endpoint)
	}
	if loaded.RootPrefix != "music/archive" {
		t.Fatalf("unexpected root prefix %q", loaded.RootPrefix)
	}
	if loaded.DefaultDownloadDirectory != "/Users/demo/Downloads/remote-storage" {
		t.Fatalf("unexpected default download directory %q", loaded.DefaultDownloadDirectory)
	}
	if loaded.CacheDirectory != cacheDir {
		t.Fatalf("unexpected cache directory %q", loaded.CacheDirectory)
	}
	if !loaded.HideDotFiles {
		t.Fatalf("expected hide dot files to stay enabled")
	}
	if loaded.WindowsMountMode != WindowsMountModeCloudFilesDirect {
		t.Fatalf("unexpected windows mount mode %q", loaded.WindowsMountMode)
	}
	if !loaded.IsConfigured() {
		t.Fatalf("expected saved config to be configured")
	}
}

func TestSaveRejectsIncompleteConfig(t *testing.T) {
	store := NewStore(filepath.Join(t.TempDir(), "config.toml"))

	err := store.Save(RemoteStorageConfig{
		Endpoint: "https://s3.example.com",
		Bucket:   "media",
	})
	if err == nil {
		t.Fatalf("expected Save to reject incomplete config")
	}
}
