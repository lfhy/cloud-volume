// External invalidation tests verify that out-of-mount mutations
// (NotifyExternalDelete/Upload/Rename) keep a mounted bucketCache consistent
// and are safe no-ops when no matching session exists.
package mount

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
	"remote-storage/go/mount/metadata"
	s3ops "remote-storage/go/s3"
)

// registerTestSession installs a synthetic manager session for the given config
// so NotifyExternal* entry points can target it without a real platform mount.
func registerTestSession(t *testing.T, cfg storageconfig.RemoteStorageConfig, bucket string, access *bucketAccess) {
	t.Helper()
	normalized := cfg.Normalized()
	globalManager.mu.Lock()
	defer globalManager.mu.Unlock()
	globalManager.sessions[normalizeBucketName(bucket)] = &mountSession{
		config: normalized,
		bucket: normalizeBucketName(bucket),
		access: access,
	}
	t.Cleanup(func() {
		globalManager.mu.Lock()
		delete(globalManager.sessions, normalizeBucketName(bucket))
		globalManager.mu.Unlock()
	})
}

func externalInvalidationConfig() storageconfig.RemoteStorageConfig {
	return storageconfig.RemoteStorageConfig{
		Endpoint: "https://example.com",
		Bucket:   "test-bucket",
	}
}

// TestNotifyExternalDeleteClearsCachedEntry seeds a cached remote listing plus a
// staged local file, runs NotifyExternalDelete, and asserts both the tombstone
// is set and the next listDirectory merge hides the path.
func TestNotifyExternalDeleteClearsCachedEntry(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	// Simulate a file that was written via the mount and is pending writeback.
	stagedPath := createTempFile(t, access.cacheRoot, "seed.txt", "hello")
	access.cache.storeLocalFile("ghost.txt", stagedPath, s3ops.ObjectInfo{Size: 5})
	// Also seed a cached directory listing that contains the file.
	access.cache.storeList("", []s3ops.ObjectInfo{{Key: "ghost.txt", Size: 5}})

	cfg := externalInvalidationConfig()
	registerTestSession(t, cfg, "test-bucket", access)

	NotifyExternalDelete(cfg, "test-bucket", "ghost.txt", false)

	if !access.cache.isMarkedDeleted("ghost.txt") {
		t.Fatal("expected NotifyExternalDelete to mark the path deleted")
	}
	merged := access.cache.mergeLocalFiles("", []s3ops.ObjectInfo{{Key: "ghost.txt", Size: 5}})
	for _, item := range merged {
		if item.Key == "ghost.txt" {
			t.Fatalf("expected ghost.txt removed from merged listing, got %+v", merged)
		}
	}
}

// TestMarkExternalDeleteCancelsWritebackAndProjects verifies that a remote-first
// delete cannot be undone by a delayed upload and reaches the platform mount.
func TestMarkExternalDeleteCancelsWritebackAndProjects(t *testing.T) {
	access := newTestBucketAccess(t)
	stagedPath := createTempFile(t, access.cacheRoot, "pending.txt", "hello")
	access.stageLocalWrite("pending.txt", stagedPath, 5)
	if !access.writeback.hasPendingAtOrBelow("pending.txt", false) {
		t.Fatal("expected pending writeback before external delete")
	}

	var projectedPath string
	var projectedDir bool
	access.externalDelete = func(virtualPath string, isDir bool) error {
		projectedPath = virtualPath
		projectedDir = isDir
		return nil
	}
	access.MarkExternalDelete("pending.txt", false)

	if access.writeback.hasPendingAtOrBelow("pending.txt", false) {
		t.Fatal("expected external delete to cancel pending writeback")
	}
	if projectedPath != "pending.txt" || projectedDir {
		t.Fatalf("unexpected platform projection path=%q isDir=%t", projectedPath, projectedDir)
	}
}

func TestInvalidateExternalUploadProjectsCreatedPath(t *testing.T) {
	access := newTestBucketAccess(t)
	var projectedPath string
	var projectedDir bool
	access.externalUpload = func(virtualPath string, isDir bool) error {
		projectedPath = virtualPath
		projectedDir = isDir
		return nil
	}

	access.InvalidateExternalUpload("docs/new-folder", true)

	if projectedPath != "docs/new-folder" || !projectedDir {
		t.Fatalf("unexpected platform projection path=%q isDir=%t", projectedPath, projectedDir)
	}
}

func TestInvalidateExternalUploadPreservesPendingLocalFile(t *testing.T) {
	access := newTestBucketAccess(t)
	stagedPath := createTempFile(t, access.cacheRoot, "pending.txt", "hello")
	access.stageLocalWrite("pending.txt", stagedPath, 5)

	access.InvalidateExternalUpload("pending.txt", false)

	if _, err := os.Stat(stagedPath); err != nil {
		t.Fatalf("pending content was removed: %v", err)
	}
	if _, ok := access.cache.localFile("pending.txt"); !ok {
		t.Fatal("pending local cache marker was removed")
	}
	if !access.writeback.hasPendingAtOrBelow("pending.txt", false) {
		t.Fatal("pending writeback was removed")
	}
}

func TestInvalidateExternalUploadPreservesUnqueuedLocalMarker(t *testing.T) {
	access := newTestBucketAccess(t)
	stagedPath := createTempFile(t, access.cacheRoot, "opened.txt", "hello")
	// FUSE/WebDAV can register a writable local handle before Close schedules
	// its upload. That marker is pending data too and must survive invalidation.
	access.registerLocalWrite("opened.txt", stagedPath, 5)

	access.InvalidateExternalUpload("opened.txt", false)

	if _, err := os.Stat(stagedPath); err != nil {
		t.Fatalf("unqueued local content was removed: %v", err)
	}
	if _, ok := access.cache.localFile("opened.txt"); !ok {
		t.Fatal("unqueued local cache marker was removed")
	}
}

// TestNotifyExternalDeleteOnNonMatchingSessionIsNoop verifies the callback is
// never invoked when the config does not match an existing session.
func TestNotifyExternalDeleteOnNonMatchingSessionIsNoop(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	stagedPath := createTempFile(t, access.cacheRoot, "seed.txt", "hello")
	access.cache.storeLocalFile("ghost.txt", stagedPath, s3ops.ObjectInfo{Size: 5})

	cfg := externalInvalidationConfig()
	registerTestSession(t, cfg, "test-bucket", access)

	// A different endpoint must not match the session.
	other := cfg
	other.Endpoint = "https://other.example.com"
	NotifyExternalDelete(other, "test-bucket", "ghost.txt", false)

	if access.cache.isMarkedDeleted("ghost.txt") {
		t.Fatal("expected no tombstone when config does not match session")
	}
}

// TestNotifyExternalDeleteWithMissingSessionIsNoop verifies the entry points do
// not panic when no session is registered for the bucket at all.
func TestNotifyExternalDeleteWithMissingSessionIsNoop(t *testing.T) {
	t.Parallel()

	cfg := externalInvalidationConfig()
	// No session registered; must not panic and must be a no-op.
	NotifyExternalDelete(cfg, "absent-bucket", "ghost.txt", false)
	NotifyExternalUpload(cfg, "absent-bucket", "ghost.txt", false)
	NotifyExternalRename(cfg, "absent-bucket", "old.txt", "new.txt", false)
}

// TestNotifyExternalUploadInvalidatesStaleListing seeds a stale cached listing
// and a tombstone, then verifies NotifyExternalUpload clears both so a refresh
// can surface the new object.
func TestNotifyExternalUploadInvalidatesStaleListing(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	// Pretend the object was previously deleted via the mount (tombstone set),
	// then re-uploaded out-of-band: the tombstone must be cleared.
	access.cache.markDeleted("docs/report.txt", false)
	// Seed a stale cached listing that does not yet contain the new file.
	access.cache.storeList("docs", []s3ops.ObjectInfo{{Key: "docs/old.txt", Size: 1}})

	cfg := externalInvalidationConfig()
	registerTestSession(t, cfg, "test-bucket", access)

	NotifyExternalUpload(cfg, "test-bucket", "docs/report.txt", false)

	if access.cache.isMarkedDeleted("docs/report.txt") {
		t.Fatal("expected NotifyExternalUpload to clear the stale delete tombstone")
	}
	if _, ok := access.cache.cachedList("docs"); ok {
		t.Fatal("expected NotifyExternalUpload to drop the stale docs listing cache")
	}
}

// TestNotifyExternalUploadRestoresDirectoryTree verifies that restoring a
// deleted directory clears every descendant tombstone. Without this, a restored
// directory would reappear but its children would remain hidden from delete or
// rename operations in the mounted volume.
func TestNotifyExternalUploadRestoresDirectoryTree(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	access.cache.markDeleted("docs", true)
	access.cache.storeList("", []s3ops.ObjectInfo{{Key: "old.txt", Size: 1}})

	cfg := externalInvalidationConfig()
	registerTestSession(t, cfg, "test-bucket", access)

	NotifyExternalUpload(cfg, "test-bucket", "docs", true)

	if access.cache.isMarkedDeleted("docs") || access.cache.isMarkedDeleted("docs/report.txt") {
		t.Fatal("expected restored directory and descendants to clear delete tombstones")
	}
	if _, ok := access.cache.cachedList(""); ok {
		t.Fatal("expected restored directory to invalidate its parent listing")
	}
}

// TestNotifyExternalRenameMovesEntry verifies the combined delete+upload
// invalidation: the old path is tombstoned and the new path's stale state is
// cleared.
func TestNotifyExternalRenameMovesEntry(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	access.cache.markDeleted("moved/destination.txt", false)
	access.cache.storeList("", []s3ops.ObjectInfo{{Key: "source.txt", Size: 3}})

	cfg := externalInvalidationConfig()
	registerTestSession(t, cfg, "test-bucket", access)

	NotifyExternalRename(cfg, "test-bucket", "source.txt", "moved/destination.txt", false)

	if !access.cache.isMarkedDeleted("source.txt") {
		t.Fatal("expected source path to be marked deleted after rename")
	}
	if access.cache.isMarkedDeleted("moved/destination.txt") {
		t.Fatal("expected destination tombstone to be cleared after rename")
	}
}

// TestNotifyExternalUploadAllowsImmediateReList confirms that after an external
// upload invalidation, a listDirectory fetch surfaces the new remote entry
// because the listing cache was dropped.
func TestNotifyExternalUploadAllowsImmediateReList(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	// Seed a stale listing that omits the freshly uploaded file.
	access.cache.storeList("", []s3ops.ObjectInfo{{Key: "old.txt", Size: 1}})

	cfg := externalInvalidationConfig()
	registerTestSession(t, cfg, "test-bucket", access)

	NotifyExternalUpload(cfg, "test-bucket", "new.txt", false)

	items, err := access.listDirectory(context.Background(), "")
	if err != nil {
		t.Fatalf("listDirectory: %v", err)
	}
	// The test backend returns an empty page, so after invalidation the stale
	// old.txt entry must be gone — proving the cache was dropped.
	for _, item := range items {
		if item.Key == "old.txt" {
			t.Fatalf("expected stale old.txt to be absent after upload invalidation, got %+v", items)
		}
	}
	// Sanity: the TTL-backed cache should have been repopulated empty.
	if refreshed, ok := access.cache.cachedList(""); !ok || len(refreshed) != 0 {
		t.Fatalf("expected empty refreshed root listing, got ok=%t items=%+v", ok, refreshed)
	}
}

func TestMetadataProjectionClearsStaleLocalMarkers(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	service := handle.Service
	ctx := context.Background()
	if _, _, _, err := service.WritePathWithProjection(
		ctx, "source.txt", strings.NewReader("new"), 3, metadata.WriteOptions{Origin: "page"},
	); err != nil {
		t.Fatal(err)
	}
	target, err := service.RenamePathWithProjection(
		ctx, "source.txt", "destination.txt", metadata.WriteOptions{Origin: "page"},
	)
	if err != nil {
		t.Fatal(err)
	}
	source := createTempFile(t, access.cacheRoot, "source.txt", "old")
	access.cache.storeLocalFile("source.txt", source, s3ops.ObjectInfo{Size: 3})
	var deleted, uploaded string
	access.externalDelete = func(virtualPath string, _ bool) error {
		deleted = virtualPath
		return nil
	}
	access.externalUpload = func(virtualPath string, _ bool) error {
		uploaded = virtualPath
		return nil
	}

	access.projectMetadataRename("source.txt", target, false)

	if _, err := os.Stat(source); err != nil {
		t.Fatalf("metadata projection removed recoverable source data: %v", err)
	}
	if _, ok := access.cache.localFile("source.txt"); ok {
		t.Fatal("stale source marker survived metadata rename")
	}
	if !access.cache.isMarkedDeleted("source.txt") {
		t.Fatal("metadata rename did not tombstone the source projection")
	}
	if deleted != "" || uploaded != "" {
		t.Fatalf("metadata projection invoked remote-confirmation callbacks delete=%q upload=%q", deleted, uploaded)
	}
}

func TestMetadataProjectionUploadReplacesMatchingLocalDraft(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	projectionInode, _, projection, err := handle.Service.WritePathWithProjection(
		context.Background(), "draft.txt", strings.NewReader("new"), 3, metadata.WriteOptions{Origin: "page"},
	)
	if err != nil || projectionInode == 0 {
		t.Fatalf("page write projection inode=%d err=%v", projectionInode, err)
	}
	stale := createTempFile(t, access.cacheRoot, "draft.txt", "old")
	access.cache.storeLocalFile("draft.txt", stale, s3ops.ObjectInfo{Size: 3})

	access.projectMetadataUpload(projection, false)

	if _, err := os.Stat(stale); err != nil {
		t.Fatalf("metadata projection removed recoverable local data: %v", err)
	}
	if _, ok := access.cache.localFile("draft.txt"); ok {
		t.Fatal("metadata upload left a local marker that would override Desired")
	}
}

func TestMetadataProjectionSkipsSupersededMountWrites(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	service := handle.Service
	service.SetQuietPeriod(24 * time.Hour)
	ctx := context.Background()

	_, _, pageUpload, err := service.WritePathWithProjection(
		ctx, "draft.txt", strings.NewReader("page"), 4, metadata.WriteOptions{Origin: "page"},
	)
	if err != nil {
		t.Fatal(err)
	}
	mountWrite := createTempFile(t, access.cacheRoot, "mount-write.txt", "mount")
	if err := access.stageLocalWrite("draft.txt", mountWrite, int64(len("mount"))); err != nil {
		t.Fatal(err)
	}
	access.projectMetadataUpload(pageUpload, false)
	if marker, ok := access.cache.localFile("draft.txt"); !ok || marker.localPath != mountWrite {
		t.Fatalf("late page upload projection cleared newer mount marker: %+v ok=%t", marker, ok)
	}

	pageDelete, err := service.DeletePathWithProjection(ctx, "draft.txt", metadata.WriteOptions{Origin: "page"})
	if err != nil {
		t.Fatal(err)
	}
	mountRecreate := createTempFile(t, access.cacheRoot, "mount-recreate.txt", "newer")
	if err := access.stageLocalWrite("draft.txt", mountRecreate, int64(len("newer"))); err != nil {
		t.Fatal(err)
	}
	access.projectMetadataDelete(pageDelete, false)
	if access.cache.isMarkedDeleted("draft.txt") {
		t.Fatal("late page delete projection tombstoned a newer mount write")
	}
	if marker, ok := access.cache.localFile("draft.txt"); !ok || marker.localPath != mountRecreate {
		t.Fatalf("late page delete projection cleared newer mount marker: %+v ok=%t", marker, ok)
	}
}

func TestDirectoryProjectionSkipsLaterMountChildWrite(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	service := handle.Service
	service.SetQuietPeriod(24 * time.Hour)
	ctx := context.Background()

	if _, _, err := service.CreateDirectoryPathWithProjection(
		ctx, "source", metadata.WriteOptions{Origin: "page"},
	); err != nil {
		t.Fatal(err)
	}
	target, err := service.RenamePathWithProjection(
		ctx, "source", "destination", metadata.WriteOptions{Origin: "page"},
	)
	if err != nil {
		t.Fatal(err)
	}
	mountWrite := createTempFile(t, access.cacheRoot, "mount-child.txt", "mount")
	if err := access.stageLocalWrite("destination/existing.txt", mountWrite, int64(len("mount"))); err != nil {
		t.Fatal(err)
	}

	access.projectMetadataRename("source", target, true)
	if marker, ok := access.cache.localFile("destination/existing.txt"); !ok || marker.localPath != mountWrite {
		t.Fatalf("late directory projection cleared newer child marker: %+v ok=%t", marker, ok)
	}
}
