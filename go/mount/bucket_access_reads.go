// Bucket access read helpers serve WebDAV list/stat/open requests from cache plus remote state.
package mount

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"

	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) listDirectory(
	ctx context.Context,
	virtualPrefix string,
) ([]s3ops.ObjectInfo, error) {
	return a.listDirectoryWithPrefetch(ctx, virtualPrefix, true)
}

func (a *bucketAccess) listDirectoryWithPrefetch(
	ctx context.Context,
	virtualPrefix string,
	allowPrefetch bool,
) ([]s3ops.ObjectInfo, error) {
	a.noteDirectoryActivity(virtualPrefix)
	if err := a.hiddenTrashError(virtualPrefix); err != nil {
		return nil, err
	}
	if a.overlay.handles(virtualPrefix) {
		return a.overlay.listDirectory(virtualPrefix)
	}
	if items, ok := a.cache.cachedList(cleanVirtualPath(virtualPrefix)); ok {
		merged := a.filterTrashItems(
			a.mergeOverlayItems(virtualPrefix, a.cache.mergeLocalFiles(virtualPrefix, items)),
		)
		if allowPrefetch {
			a.prefetchChildren(merged)
		}
		return cloneObjects(merged), nil
	}

	flightKey := "list:" + cleanVirtualPath(virtualPrefix)
	value, err, _ := a.group.Do(flightKey, func() (any, error) {
		items, err := a.fetchDirectory(ctx, virtualPrefix)
		if err != nil {
			return nil, err
		}
		a.cache.storeList(virtualPrefix, items)
		return a.filterTrashItems(
			a.mergeOverlayItems(virtualPrefix, a.cache.mergeLocalFiles(virtualPrefix, items)),
		), nil
	})
	if err != nil {
		return nil, err
	}
	items, _ := value.([]s3ops.ObjectInfo)
	if allowPrefetch {
		a.prefetchChildren(items)
	}
	return cloneObjects(items), nil
}

func (a *bucketAccess) statPath(
	ctx context.Context,
	virtualPath string,
) (s3ops.ObjectInfo, error) {
	clean := cleanVirtualPath(virtualPath)
	if err := a.hiddenTrashError(clean); err != nil {
		return s3ops.ObjectInfo{}, err
	}
	if clean == "" {
		return s3ops.ObjectInfo{Key: "", IsDir: true}, nil
	}
	if a.overlay.handles(clean) {
		info, err := a.overlay.statObject(clean)
		if err != nil {
			return s3ops.ObjectInfo{}, err
		}
		return info, nil
	}
	if item, ok := a.cache.localFile(clean); ok {
		return item.info, nil
	}
	if item, ok := a.cache.cachedObject(clean); ok {
		return item, nil
	}
	if a.cache.isMarkedDeleted(clean) {
		return s3ops.ObjectInfo{}, os.ErrNotExist
	}

	parentPrefix := parentVirtualPrefix(clean)
	if items, ok := a.cache.cachedList(parentPrefix); ok {
		for _, item := range a.cache.mergeLocalFiles(parentPrefix, items) {
			if item.Key == clean || item.Key == ensureDirSuffix(clean) {
				a.cache.storeObject(clean, item)
				return item, nil
			}
		}
		// A fresh directory listing is an authoritative negative lookup too.
		// Finder probes every destination before PUT; falling through here would
		// turn a many-small-file copy into one upstream Stat call per file.
		return s3ops.ObjectInfo{}, os.ErrNotExist
	}
	if a.cache.isLocalDirectory(parentPrefix) {
		// Children of a directory created in this mount are represented by the
		// local overlay until writeback catches up, so an absent child is local.
		return s3ops.ObjectInfo{}, os.ErrNotExist
	}

	flightKey := "stat:" + clean
	value, err, _ := a.group.Do(flightKey, func() (any, error) {
		info, err := a.fetchStat(ctx, clean)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				// Remote file was deleted: clear any stale metadata so subsequent
				// accesses do not keep returning cached info for a ghost file.
				a.cache.invalidatePath(clean)
			}
			return nil, err
		}
		a.cache.storeObject(clean, info)
		return info, nil
	})
	if err != nil {
		return s3ops.ObjectInfo{}, err
	}
	info, _ := value.(s3ops.ObjectInfo)
	return info, nil
}

func (a *bucketAccess) ensureLocalFile(
	ctx context.Context,
	virtualPath string,
) (string, s3ops.ObjectInfo, error) {
	clean := cleanVirtualPath(virtualPath)
	if a.overlay.handles(clean) {
		info, err := a.overlay.statObject(clean)
		if err != nil {
			return "", s3ops.ObjectInfo{}, err
		}
		return a.overlay.localPath(clean), info, nil
	}
	if item, ok := a.cache.localFile(clean); ok {
		if isUsableLocalFile(item.localPath, item.info.Size) {
			return item.localPath, item.info, nil
		}
	}

	info, err := a.fetchStat(ctx, clean)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			a.cache.invalidatePath(clean)
		}
		return "", s3ops.ObjectInfo{}, err
	}
	a.cache.storeObject(clean, info)
	if info.IsDir {
		return "", s3ops.ObjectInfo{}, fmt.Errorf("%s is a directory", clean)
	}

	localPath := a.cachePathFor(clean)
	reconcileDownloadArtifacts(localPath, info)
	if isCompleteDownloadUsable(localPath, info) {
		return localPath, info, nil
	}

	flightKey := "download:" + clean
	value, err, _ := a.group.Do(flightKey, func() (any, error) {
		return a.downloadToCache(ctx, clean, info, localPath)
	})
	if err != nil {
		return "", s3ops.ObjectInfo{}, err
	}
	pathValue, _ := value.(string)
	return pathValue, info, nil
}

func (a *bucketAccess) mergeOverlayItems(
	virtualPrefix string,
	items []s3ops.ObjectInfo,
) []s3ops.ObjectInfo {
	overlayItems, err := a.overlay.listRootEntries()
	if cleanVirtualPath(virtualPrefix) != "" {
		overlayItems, err = a.overlay.listDirectory(virtualPrefix)
	}
	if err != nil || len(overlayItems) == 0 {
		return items
	}
	byKey := make(map[string]s3ops.ObjectInfo, len(items)+len(overlayItems))
	for _, item := range items {
		byKey[item.Key] = item
	}
	for _, item := range overlayItems {
		byKey[item.Key] = item
	}
	merged := make([]s3ops.ObjectInfo, 0, len(byKey))
	for _, item := range byKey {
		merged = append(merged, item)
	}
	return merged
}

func (a *bucketAccess) localReadablePath(
	virtualPath string,
	info s3ops.ObjectInfo,
) (string, bool) {
	if item, ok := a.cache.localFile(virtualPath); ok && isUsableLocalFile(item.localPath, info.Size) {
		return item.localPath, true
	}
	localPath := a.cachePathFor(cleanVirtualPath(virtualPath))
	reconcileDownloadArtifacts(localPath, info)
	if isCompleteDownloadUsable(localPath, info) {
		return localPath, true
	}
	return "", false
}

func (a *bucketAccess) readRemoteRange(
	ctx context.Context,
	virtualPath string,
	offset,
	length int64,
) ([]byte, error) {
	timeoutCtx, cancel := a.withTransferTimeout(ctx)
	defer cancel()
	data, err := a.backend.ReadObjectRange(timeoutCtx, a.bucket, a.remoteKey(virtualPath), offset, length)
	if err != nil && errors.Is(err, os.ErrNotExist) {
		// Remote file was deleted while the metadata cache was still stale.
		// Invalidate the cached entries so subsequent access re-fetches from remote.
		a.cache.invalidatePath(virtualPath)
	}
	return data, err
}

// InvalidateListCache drops cached directory listings for the given prefix so
// the next listDirectory call fetches fresh data from the remote backend.
func (a *bucketAccess) InvalidateListCache(prefix string) {
	a.cache.invalidateListCache(prefix)
}

// MarkExternalDelete records that an out-of-mount caller deleted the given
// virtual path. It reuses the same tombstone + local-staging cleanup that a
// mount-side delete performs, then also drops the object metadata cache so a
// subsequent stat/list cannot resurrect the removed entry.
func (a *bucketAccess) MarkExternalDelete(virtualPath string, isDir bool) {
	clean := cleanVirtualPath(virtualPath)
	if a.writeback != nil {
		if isDir {
			a.writeback.cancelAtOrBelow(clean, true)
		} else {
			a.writeback.cancel(clean)
		}
	}
	a.cache.markDeleted(virtualPath, isDir)
	a.cache.invalidatePath(virtualPath)
	if a.externalDelete != nil {
		if err := a.externalDelete(clean, isDir); err != nil {
			log.Printf("[mount/external] local-delete-projection path=%q isDir=%t error=%v", clean, isDir, err)
		}
	}
}

// InvalidateExternalUpload records that an out-of-mount caller created or
// overwrote the given virtual path (upload/copy/create directory). It clears
// any stale local staging entries and tombstones for the path and invalidates
// the path plus its parent listings so the new entry becomes visible on the
// next read without waiting for the list TTL.
func (a *bucketAccess) InvalidateExternalUpload(virtualPath string, isDir bool) {
	clean := cleanVirtualPath(virtualPath)
	if a.writeback == nil || !a.writeback.hasPendingAtOrBelow(clean, isDir) {
		a.cache.removeLocalPath(clean, isDir)
	} else {
		log.Printf(
			"[mount/external] preserve-pending-local path=%q is_dir=%t",
			clean,
			isDir,
		)
	}
	a.cache.invalidatePath(clean)
	a.cache.invalidatePath(parentVirtualPrefix(clean))
	if a.externalUpload != nil {
		if err := a.externalUpload(clean, isDir); err != nil {
			log.Printf("[mount/external] local-upload-projection path=%q isDir=%t error=%v", clean, isDir, err)
		}
	}
}

// InvalidateExternalRename covers rename/move: the source path is treated as
// deleted while the destination is treated as freshly uploaded.
func (a *bucketAccess) InvalidateExternalRename(oldPath, newPath string, isDir bool) {
	a.MarkExternalDelete(oldPath, isDir)
	a.InvalidateExternalUpload(newPath, isDir)
}
