// Peer-source tests ensure a bridge upload is offered only for its exact version.
package mount

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
	"remote-storage/go/mount/metadata"
	s3ops "remote-storage/go/s3"
)

func TestRememberPeerContentRequiresMatchingVersion(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "source.bin")
	if err := os.WriteFile(path, []byte("content"), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg := storageconfig.RemoteStorageConfig{Endpoint: "https://example.test", AccessKeyID: "access", SecretAccessKey: "secret"}
	info := s3ops.ObjectInfo{Key: "folder/file", Size: 7, LastModified: "v1", ETag: "etag-v1"}
	RememberPeerContent(cfg, "bucket", "folder/file", path, info)
	resolved, size, ok := LocalPeerContentPath(cfg, "bucket", "folder/file", "etag:etag-v1")
	if !ok || resolved != path || size != 7 {
		t.Fatalf("unexpected source result path=%q size=%d ok=%t", resolved, size, ok)
	}
	if _, _, ok := LocalPeerContentPath(cfg, "bucket", "folder/file", "etag:etag-v2"); ok {
		t.Fatal("stale version was offered")
	}
}

func TestPeerContentVersionHintPrefersETagAndFallsBackToTimestampSize(t *testing.T) {
	withETag := s3ops.ObjectInfo{Size: 7, LastModified: "2026-07-28 12:00:00", ETag: "etag-v1"}
	if got := peerContentVersionHint(withETag); got != "etag:etag-v1" {
		t.Fatalf("ETag version hint = %q", got)
	}
	withoutETag := withETag
	withoutETag.ETag = ""
	if got := peerContentVersionHint(withoutETag); got != "mtime-size:2026-07-28 12:00:00:7" {
		t.Fatalf("fallback version hint = %q", got)
	}
}

func TestLocalPeerContentPathRejectsMetadataPendingBytes(t *testing.T) {
	access := newTestBucketAccess(t)
	cfg := storageconfig.RemoteStorageConfig{
		ProfileID: "peer-pending-profile", Endpoint: "https://example.test",
		CacheDirectory: t.TempDir(), Bucket: "test-bucket",
	}
	manager := metadata.NewManager(t.TempDir())
	handle, err := manager.AcquireWithBackend(cfg, access.bucket, &metadataReadTestBackend{})
	if err != nil {
		t.Fatal(err)
	}
	access.metadataHandle = handle
	access.config = cfg.Normalized()
	service := access.metadataService()
	service.SetQuietPeriod(time.Hour)
	t.Cleanup(func() {
		access.metadataHandle = nil
		handle.Release()
		manager.RemoveAllForTest()
	})
	if _, _, err := service.WritePath(
		context.Background(), "pending-peer.txt", strings.NewReader("pending"), 7,
		metadata.WriteOptions{Origin: "page"},
	); err != nil {
		t.Fatal(err)
	}
	localPath := createTempFile(t, access.cacheRoot, "pending-peer.txt", "pending")
	info := s3ops.ObjectInfo{
		Key: "pending-peer.txt", Size: 7, LastModified: "2026-08-18 00:00:00", ETag: "remote-old",
	}
	access.cache.storeObject("pending-peer.txt", info)
	if err := writeDownloadStamp(localPath, info); err != nil {
		t.Fatal(err)
	}
	registerTestSession(t, cfg, access.bucket, access)
	if _, _, ok := LocalPeerContentPath(cfg, access.bucket, "pending-peer.txt", "etag:remote-old"); ok {
		t.Fatal("pending metadata bytes were offered as confirmed peer content")
	}
}
