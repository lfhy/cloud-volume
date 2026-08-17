// Metadata chunk cache tests ensure generic cache cleanup never drops pending blocks.
package config

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCacheStatsAndClearAllProtectPendingMetadataChunks(t *testing.T) {
	cacheRoot := t.TempDir()
	pendingPath, manifestPath := writeProtectedChunk(t, cacheRoot, "namespace", []byte("keep"))
	orphanPath := filepath.Join(filepath.Dir(pendingPath), chunkHash([]byte("drop")))
	if err := os.WriteFile(orphanPath, []byte("drop"), 0o600); err != nil {
		t.Fatal(err)
	}
	normalPath := filepath.Join(cacheRoot, "ordinary.bin")
	if err := os.WriteFile(normalPath, []byte("ordinary"), 0o600); err != nil {
		t.Fatal(err)
	}

	stats, err := GetCacheStats(RemoteStorageConfig{CacheDirectory: cacheRoot})
	if err != nil {
		t.Fatal(err)
	}
	if stats.ProtectedFiles != 1 || stats.ProtectedBytes != int64(len("keep")) {
		t.Fatalf("protected stats = %+v", stats)
	}

	result, err := CleanCache(
		RemoteStorageConfig{CacheDirectory: cacheRoot},
		CleanCacheRequest{ClearAll: true},
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.Removed != 2 || result.SkippedProtected != 1 {
		t.Fatalf("clear result = %+v", result)
	}
	for _, path := range []string{pendingPath, manifestPath} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("protected cache file %s was removed: %v", path, err)
		}
	}
	for _, path := range []string{orphanPath, normalPath} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("unprotected cache file %s remains: %v", path, err)
		}
	}
}

func TestRuleCleanupSkipsOldPendingChunk(t *testing.T) {
	cacheRoot := t.TempDir()
	pendingPath, _ := writeProtectedChunk(t, cacheRoot, "namespace", []byte("keep"))
	oldPath := filepath.Join(cacheRoot, "old.bin")
	if err := os.WriteFile(oldPath, []byte("drop"), 0o600); err != nil {
		t.Fatal(err)
	}
	old := time.Now().Add(-48 * time.Hour)
	for _, path := range []string{pendingPath, oldPath} {
		if err := os.Chtimes(path, old, old); err != nil {
			t.Fatal(err)
		}
	}

	result, err := CleanCache(
		RemoteStorageConfig{CacheDirectory: cacheRoot, CacheMaxAgeDays: 1},
		CleanCacheRequest{},
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.Removed != 1 || result.SkippedProtected != 1 {
		t.Fatalf("rule result = %+v", result)
	}
	if _, err := os.Stat(pendingPath); err != nil {
		t.Fatalf("pending chunk removed: %v", err)
	}
	if _, err := os.Stat(oldPath); !os.IsNotExist(err) {
		t.Fatalf("old ordinary cache remains: %v", err)
	}
}

func TestCorruptChunkManifestProtectsWholeNamespace(t *testing.T) {
	cacheRoot := t.TempDir()
	hash := chunkHash([]byte("keep"))
	root := filepath.Join(cacheRoot, metadataChunkStoreDir, "namespace")
	chunkPath := filepath.Join(root, "chunks", hash[:2], hash)
	if err := os.MkdirAll(filepath.Dir(chunkPath), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(chunkPath, []byte("keep"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "protection.json"), []byte("{bad"), 0o600); err != nil {
		t.Fatal(err)
	}
	ordinary := filepath.Join(cacheRoot, "ordinary.bin")
	if err := os.WriteFile(ordinary, []byte("drop"), 0o600); err != nil {
		t.Fatal(err)
	}

	result, err := CleanCache(
		RemoteStorageConfig{CacheDirectory: cacheRoot},
		CleanCacheRequest{ClearAll: true},
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.SkippedProtected != 1 {
		t.Fatalf("corrupt manifest should conservatively protect chunk: %+v", result)
	}
	if _, err := os.Stat(chunkPath); err != nil {
		t.Fatalf("chunk removed despite corrupt manifest: %v", err)
	}
	if _, err := os.Stat(ordinary); !os.IsNotExist(err) {
		t.Fatalf("ordinary cache was not removed: %v", err)
	}
}

func writeProtectedChunk(t *testing.T, cacheRoot, namespace string, content []byte) (string, string) {
	t.Helper()
	hash := chunkHash(content)
	root := filepath.Join(cacheRoot, metadataChunkStoreDir, namespace)
	path := filepath.Join(root, "chunks", hash[:2], hash)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatal(err)
	}
	manifestPath := filepath.Join(root, "protection.json")
	data, err := json.Marshal(metadataChunkProtectionManifest{
		Version: 1, Chunks: map[string]int64{hash: int64(len(content))},
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(manifestPath, data, 0o600); err != nil {
		t.Fatal(err)
	}
	return path, manifestPath
}

func chunkHash(content []byte) string {
	sum := sha256.Sum256(content)
	return hex.EncodeToString(sum[:])
}
