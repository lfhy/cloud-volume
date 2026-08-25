package config

import (
	"path/filepath"
	"testing"
)

func TestStoreSaveAndLoadRoundTrip(t *testing.T) {
	store := NewStore(filepath.Join(t.TempDir(), "config.toml"))
	cacheDir := filepath.Join(t.TempDir(), "custom-cache")
	input := RemoteStorageConfig{
		Endpoint:         " https://s3.example.com ",
		Region:           " us-east-1 ",
		Bucket:           " media-bucket ",
		AccessKeyID:      " ACCESS ",
		SecretAccessKey:  " SECRET ",
		RootPrefix:       " /music/archive/ ",
		CacheDirectory:   " " + cacheDir + " ",
		HideDotFiles:     true,
		UsePathStyle:     true,
		WindowsMountMode: WindowsMountModeCloudFilesDirect,
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
	if !loaded.IsConfigured() {
		t.Fatalf("expected saved config to be configured")
	}
}
