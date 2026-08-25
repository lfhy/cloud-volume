// Download resume tests lock cache stamp validation and partial-file cleanup.
package mount

import (
	"os"
	"testing"

	s3ops "remote-storage/go/s3"
)

func TestCompleteDownloadUsableRequiresMatchingStamp(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	localPath := createTempFile(t, root, "cache/object.txt", "hello world")
	info := s3ops.ObjectInfo{
		Key:          "object.txt",
		Size:         11,
		LastModified: "2026-05-26 22:00:00",
		ETag:         "etag-v1",
	}
	if err := writeDownloadStamp(localPath, info); err != nil {
		t.Fatalf("writeDownloadStamp: %v", err)
	}
	if !isCompleteDownloadUsable(localPath, info) {
		t.Fatal("expected complete cache file to be usable with matching stamp")
	}
	if isCompleteDownloadUsable(localPath, s3ops.ObjectInfo{
		Key:          info.Key,
		Size:         info.Size,
		LastModified: "2026-05-26 22:00:01",
		ETag:         info.ETag,
	}) {
		t.Fatal("expected cache file to be invalid after remote last-modified changes")
	}
}

func TestCompleteDownloadUsableRejectsSameSizeSameTimestampETagChange(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	localPath := createTempFile(t, root, "cache/object.txt", "hello world")
	original := s3ops.ObjectInfo{
		Key:          "object.txt",
		Size:         11,
		LastModified: "2026-05-26 22:00:00",
		ETag:         "etag-v1",
	}
	if err := writeDownloadStamp(localPath, original); err != nil {
		t.Fatalf("writeDownloadStamp: %v", err)
	}
	overwritten := original
	overwritten.ETag = "etag-v2"
	if isCompleteDownloadUsable(localPath, overwritten) {
		t.Fatal("expected cache file to be invalid after same-size same-time overwrite")
	}
}

func TestPromoteConfirmedPendingStampKeepsMaterializedCache(t *testing.T) {
	root := t.TempDir()
	localPath := createTempFile(t, root, "cache/object.txt", "hello world")
	pending := s3ops.ObjectInfo{
		Key: "object.txt", Size: 11, LastModified: "2026-05-26 22:00:00", ETag: "etag-v1",
	}
	if err := writePendingDownloadStamp(localPath, pending, 42, 7); err != nil {
		t.Fatalf("writePendingDownloadStamp: %v", err)
	}
	if isCompleteDownloadUsable(localPath, pending) {
		t.Fatal("pending stamp unexpectedly matched a confirmed cache")
	}
	promoteConfirmedPendingStamp(localPath, pending, 42, 7)
	if !isCompleteDownloadUsable(localPath, pending) {
		t.Fatal("confirmed pending cache was not promoted")
	}
	stamp, ok := loadDownloadStamp(localPath)
	if !ok || stamp.MetadataInode != 0 || stamp.MetadataGeneration != 0 {
		t.Fatalf("promoted stamp still carries metadata identity: %+v ok=%t", stamp, ok)
	}
}

func TestReconcileDownloadArtifactsClearsChangedRemoteState(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	localPath := createTempFile(t, root, "cache/object.txt", "hello world")
	partialPath := partialDownloadPath(localPath)
	if err := os.WriteFile(partialPath, []byte("hello "), 0o644); err != nil {
		t.Fatalf("write partial download: %v", err)
	}

	original := s3ops.ObjectInfo{
		Key:          "object.txt",
		Size:         11,
		LastModified: "2026-05-26 22:00:00",
	}
	if err := writeDownloadStamp(localPath, original); err != nil {
		t.Fatalf("write final stamp: %v", err)
	}
	if err := writeDownloadStamp(partialPath, original); err != nil {
		t.Fatalf("write partial stamp: %v", err)
	}

	updated := s3ops.ObjectInfo{
		Key:          original.Key,
		Size:         15,
		LastModified: "2026-05-26 22:05:00",
	}
	reconcileDownloadArtifacts(localPath, updated)

	assertPathMissing(t, localPath)
	assertPathMissing(t, partialPath)
	assertPathMissing(t, stampPath(localPath))
	assertPathMissing(t, partialStampPath(localPath))
}

func TestReconcileDownloadArtifactsClearsOversizedPartial(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	localPath := root + "/cache/object.txt"
	partialPath := partialDownloadPath(localPath)
	if err := os.MkdirAll(root+"/cache", 0o755); err != nil {
		t.Fatalf("mkdir cache dir: %v", err)
	}
	if err := os.WriteFile(partialPath, []byte("hello world"), 0o644); err != nil {
		t.Fatalf("write oversized partial: %v", err)
	}
	info := s3ops.ObjectInfo{
		Key:          "object.txt",
		Size:         5,
		LastModified: "2026-05-26 22:00:00",
	}
	if err := writeDownloadStamp(partialPath, info); err != nil {
		t.Fatalf("write partial stamp: %v", err)
	}

	reconcileDownloadArtifacts(localPath, info)

	assertPathMissing(t, partialPath)
	assertPathMissing(t, partialStampPath(localPath))
}

func assertPathMissing(t *testing.T, path string) {
	t.Helper()

	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("expected %s to be removed, got err=%v", path, err)
	}
}
