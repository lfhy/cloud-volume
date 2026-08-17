// External invalidation lets bridge/webapi mutations that bypass the mount
// (delete_object, rename_object, upload_file, …) keep mounted session caches in
// sync, so the file manager UI and the mount point never show ghost entries.
package mount

import (
	"log"

	storageconfig "remote-storage/go/config"
	"remote-storage/go/mount/metadata"
)

// notifyExternalMutation runs callback against the bucketAccess of the active
// session matching cfg+bucket. It mirrors the session lookup used by
// invalidateListCacheForPrefix so all NotifyExternal* entry points share one
// place for normalize/match/guard logic. When no session matches, the callback
// is never invoked, so callers pay zero cost when no mount is active.
func (m *manager) notifyExternalMutation(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	callback func(access *bucketAccess),
) {
	m.mu.Lock()
	defer m.mu.Unlock()

	trimmedBucket := normalizeBucketName(bucket)
	session, ok := m.sessions[trimmedBucket]
	if !ok || session.access == nil {
		return
	}
	if !mountSessionMatches(session, cfg, trimmedBucket, MountOptions{}) {
		return
	}
	callback(session.access)
}

// NotifyExternalDelete marks a path as deleted by an out-of-mount mutation
// (e.g. the file manager delete_object bridge method). It drops cached
// metadata, removes any staged local copy, and records a tombstone so the
// mount view and the file manager refresh both stop showing the entry.
func NotifyExternalDelete(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	virtualPath string,
	isDir bool,
) {
	ForgetPeerContent(cfg, bucket, virtualPath)
	globalManager.notifyExternalMutation(cfg, bucket, func(access *bucketAccess) {
		log.Printf("[mount/external] delete bucket=%q path=%q isDir=%v", bucket, virtualPath, isDir)
		access.MarkExternalDelete(virtualPath, isDir)
	})
}

// NotifyExternalUpload marks a path as created or overwritten by an
// out-of-mount mutation (upload_file, create_directory, copy_object target).
// It invalidates stale metadata and parent listings so the new entry is
// visible without waiting for the list TTL to expire.
func NotifyExternalUpload(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	virtualPath string,
	isDir bool,
) {
	globalManager.notifyExternalMutation(cfg, bucket, func(access *bucketAccess) {
		log.Printf("[mount/external] upload bucket=%q path=%q isDir=%v", bucket, virtualPath, isDir)
		access.InvalidateExternalUpload(virtualPath, isDir)
	})
}

// NotifyExternalRename covers rename_object and move_object, which both remove
// the source path and surface a new one. It is equivalent to a delete of the
// old path followed by an upload-style invalidation of the new path.
func NotifyExternalRename(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	oldPath,
	newPath string,
	isDir bool,
) {
	ForgetPeerContent(cfg, bucket, oldPath)
	globalManager.notifyExternalMutation(cfg, bucket, func(access *bucketAccess) {
		log.Printf("[mount/external] rename bucket=%q old=%q new=%q isDir=%v", bucket, oldPath, newPath, isDir)
		access.InvalidateExternalRename(oldPath, newPath, isDir)
	})
}

// ProjectMetadataDelete updates an active mount's local overlay after the
// shared metadata tree accepted a page-originated delete journal entry.
func ProjectMetadataDelete(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	projection metadata.PathProjection,
	isDir bool,
) {
	globalManager.notifyExternalMutation(cfg, bucket, func(access *bucketAccess) {
		access.projectMetadataDelete(projection, isDir)
	})
}

// ProjectMetadataUpload removes stale mount-local markers after metadata
// accepts a page-originated write or mkdir. It does not announce a remote
// mutation; the metadata worker owns remote confirmation.
func ProjectMetadataUpload(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	projection metadata.PathProjection,
	isDir bool,
) {
	globalManager.notifyExternalMutation(cfg, bucket, func(access *bucketAccess) {
		access.projectMetadataUpload(projection, isDir)
	})
}

// ProjectMetadataRename projects a Desired-tree rename into an active mount
// without using the remote-first invalidation or peer-broadcast paths.
func ProjectMetadataRename(
	cfg storageconfig.RemoteStorageConfig,
	bucket, oldPath string,
	projection metadata.PathProjection,
	isDir bool,
) {
	globalManager.notifyExternalMutation(cfg, bucket, func(access *bucketAccess) {
		access.projectMetadataRename(oldPath, projection, isDir)
	})
}
