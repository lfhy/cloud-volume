// Bucket access write helpers own create/delete/rename and local cache file utilities.
package mount

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/google/uuid"

	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) readOnlyError() error {
	if a != nil && a.readOnly {
		return fmt.Errorf("mount is read-only")
	}
	return nil
}

func (a *bucketAccess) registerLocalWrite(virtualPath, localPath string, size int64) {
	if a == nil || a.readOnly {
		return
	}
	a.writebackMu.Lock()
	defer a.writebackMu.Unlock()
	a.registerLocalWriteLocked(virtualPath, localPath, size)
}

// stageLocalWrite publishes the local marker and durable queue entry as one
// critical section so external invalidation cannot delete a newly staged file
// between those two steps.
func (a *bucketAccess) stageLocalWrite(virtualPath, localPath string, size int64) {
	if a == nil || a.readOnly {
		return
	}
	a.writebackMu.Lock()
	defer a.writebackMu.Unlock()
	a.registerLocalWriteLocked(virtualPath, localPath, size)
	a.scheduleUploadLocked(virtualPath, localPath)
}

func (a *bucketAccess) registerLocalWriteLocked(virtualPath, localPath string, size int64) {
	info := s3ops.ObjectInfo{
		Key:          cleanVirtualPath(virtualPath),
		Size:         size,
		LastModified: time.Now().Format("2006-01-02 15:04:05"),
		IsDir:        false,
	}
	a.cache.storeLocalFile(cleanVirtualPath(virtualPath), localPath, info)
}

func (a *bucketAccess) scheduleUpload(virtualPath, localPath string) {
	if a == nil || a.readOnly {
		return
	}
	a.writebackMu.Lock()
	defer a.writebackMu.Unlock()
	a.scheduleUploadLocked(virtualPath, localPath)
}

func (a *bucketAccess) scheduleUploadLocked(virtualPath, localPath string) {
	log.Printf(
		"[mount/writeback] enqueue-request bucket=%q path=%q local_path=%q size=%d",
		a.bucket,
		cleanVirtualPath(virtualPath),
		localPath,
		fileSize(localPath),
	)
	a.writeback.enqueue(cleanVirtualPath(virtualPath), localPath, fileSize(localPath))
}

func (a *bucketAccess) createDirectory(
	ctx context.Context,
	virtualPath string,
) error {
	clean := cleanVirtualPath(virtualPath)
	if err := a.readOnlyError(); err != nil {
		return err
	}
	if err := a.hiddenTrashError(clean); err != nil {
		return err
	}
	if a.overlay.handles(clean) {
		return a.overlay.mkdir(clean, 0o755)
	}
	if clean == "" {
		return fmt.Errorf("directory name is required")
	}
	a.stageLocalDirectory(clean, time.Now())
	return nil
}

func (a *bucketAccess) deletePath(
	ctx context.Context,
	virtualPath string,
	isDir bool,
) error {
	_ = ctx
	if err := a.readOnlyError(); err != nil {
		return err
	}
	if err := a.hiddenTrashError(virtualPath); err != nil {
		return err
	}
	clean := cleanVirtualPath(virtualPath)
	if a.overlay.handles(clean) {
		return a.overlay.removeAll(clean)
	}
	if !isDir {
		a.writeback.cancel(clean)
	} else {
		a.writeback.cancelAtOrBelow(clean, true)
	}
	a.cache.markDeleted(clean, isDir)
	a.cache.invalidatePath(clean)
	if a.deletes != nil {
		a.deletes.enqueue(clean, isDir, isLocalMetadataPath(clean))
	}
	return nil
}

func (a *bucketAccess) renamePath(
	ctx context.Context,
	oldVirtualPath,
	newVirtualPath string,
	isDir bool,
) error {
	oldClean := cleanVirtualPath(oldVirtualPath)
	newClean := cleanVirtualPath(newVirtualPath)
	if err := a.readOnlyError(); err != nil {
		return err
	}
	if a.overlay.isTrashPath(newClean) {
		return a.deletePath(ctx, oldClean, isDir)
	}
	if err := a.hiddenTrashError(oldClean); err != nil {
		return err
	}
	if err := a.hiddenTrashError(newClean); err != nil {
		return err
	}
	if oldClean == "" || newClean == "" {
		return fmt.Errorf("source and target paths are required")
	}
	oldOverlay := a.overlay.handles(oldClean)
	newOverlay := a.overlay.handles(newClean)
	if oldOverlay || newOverlay {
		if oldOverlay && newOverlay {
			return a.overlay.rename(oldClean, newClean)
		}
		return a.renameAcrossBoundary(ctx, oldClean, newClean, isDir)
	}
	var dirBarrier *dirSyncBarrier
	if a.dirSync != nil {
		dirBarrier = a.dirSync.rebaseAndFence(oldClean, newClean, isDir)
	}
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	if a.dirSync != nil {
		if err := a.dirSync.wait(timeoutCtx, dirBarrier); err != nil {
			return fmt.Errorf("wait for directory marker rename: %w", err)
		}
	}
	hadPendingWriteback := a.writeback.rename(oldClean, newClean, isDir)
	if isDir && dirBarrier != nil && dirBarrier.rebasedCreate {
		exists, err := a.probeRemotePath(timeoutCtx, oldClean, true)
		if err != nil {
			return err
		}
		if !exists {
			exists, err = a.probeRemotePath(timeoutCtx, newClean, true)
			if err != nil {
				return err
			}
			if !exists {
				return fmt.Errorf("directory %q is absent after marker rebase", newClean)
			}
			if !hadPendingWriteback {
				a.applyRenamedLocalState(oldClean, newClean, true)
			}
			return nil
		}
	}
	if hadPendingWriteback {
		exists, err := a.probeRemotePath(timeoutCtx, oldClean, isDir)
		if err != nil {
			return err
		}
		if !exists {
			return nil
		}
	}
	taskID := "mount-move-" + uuid.NewString()
	if err := a.backend.MoveObject(
		timeoutCtx,
		a.bucket,
		a.remoteKeyForMutation(oldClean, isDir),
		a.remoteKeyForMutation(newClean, isDir),
		isDir,
		taskID,
	); err != nil {
		return err
	}
	a.applyRenamedLocalState(oldClean, newClean, isDir)
	ForgetPeerContent(a.config, a.bucket, oldClean)
	if hook := PeerBroadcastHook(); hook != nil {
		hook(BroadcastPayload{Config: a.config, Bucket: a.bucket, VirtualPath: newClean, OldPath: oldClean, IsDir: isDir, Operation: "rename"})
	}
	return nil
}

// applyRenamedLocalState keeps local staging and lookup caches aligned once a
// rename has either reached the provider or been satisfied by a rebased marker.
func (a *bucketAccess) applyRenamedLocalState(oldClean, newClean string, isDir bool) {
	a.cache.renameLocalFile(oldClean, newClean, isDir, a.cacheRoot)
	a.cache.invalidatePath(oldClean)
	a.cache.invalidatePath(newClean)
}

func (a *bucketAccess) enqueueRenamePath(
	oldVirtualPath,
	newVirtualPath,
	oldLocalPath,
	newLocalPath string,
	isDir bool,
) error {
	oldClean := cleanVirtualPath(oldVirtualPath)
	newClean := cleanVirtualPath(newVirtualPath)
	if err := a.readOnlyError(); err != nil {
		return err
	}
	if oldClean == "" || newClean == "" {
		return fmt.Errorf("source and target paths are required")
	}
	if a.overlay.handles(oldClean) || a.overlay.handles(newClean) || a.overlay.isTrashPath(newClean) {
		return fmt.Errorf("queued rename requires two mounted bucket paths")
	}
	if err := a.hiddenTrashError(oldClean); err != nil {
		return err
	}
	if err := a.hiddenTrashError(newClean); err != nil {
		return err
	}
	var dirBarrier *dirSyncBarrier
	if a.dirSync != nil {
		dirBarrier = a.dirSync.rebaseAndFence(oldClean, newClean, isDir)
	}
	// Capture a stable task ID for the persisted mutation record; retries
	// across restarts reuse it so the transfer monitor stays consistent.
	taskID := "mount-move-" + uuid.NewString()
	return a.writeback.enqueueMutation(
		mutationRecord{
			Version:          mutationRecordVersion,
			ID:               newMutationID(),
			TaskID:           taskID,
			Kind:             mutationKindRename,
			OldVirtualPath:   oldClean,
			NewVirtualPath:   newClean,
			OldLocalPath:     oldLocalPath,
			NewLocalPath:     newLocalPath,
			IsDirectory:      isDir,
			UploadGeneration: 0, // enqueueMutation assigns the barrier generation
			UpdatedAtUnixNs:  time.Now().UnixNano(),
		},
		oldLocalPath,
		newLocalPath,
		func() error {
			if isDir && dirBarrier != nil && dirBarrier.rebasedCreate {
				ctx, cancel := a.withTimeout(context.Background())
				defer cancel()
				exists, err := a.probeRemotePath(ctx, oldClean, true)
				if err != nil {
					return err
				}
				if !exists {
					if err := a.createRemoteDirectory(ctx, newClean); err != nil {
						return err
					}
					exists, err = a.probeRemotePath(ctx, newClean, true)
					if err != nil {
						return err
					}
					if !exists {
						return fmt.Errorf(
							"directory %q is absent after create",
							newClean,
						)
					}
					a.cache.renameLocalFile(oldClean, newClean, true, a.cacheRoot)
					a.cache.invalidatePath(oldClean)
					a.cache.invalidatePath(newClean)
					return nil
				}
			}
			return a.renamePath(context.Background(), oldClean, newClean, isDir)
		},
		dirBarrier,
	)
}

func (a *bucketAccess) probeRemotePath(
	ctx context.Context,
	virtualPath string,
	isDir bool,
) (bool, error) {
	key := a.remoteKey(virtualPath)
	if isDir {
		key = a.remoteKeyForMutation(virtualPath, true)
	}
	if _, err := a.backend.HeadObject(ctx, a.bucket, key); err == nil {
		return true, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return false, err
	}
	if !isDir {
		return false, nil
	}
	page, err := a.backend.ListObjectsPage(ctx, a.bucket, a.remotePrefix(virtualPath), "", 1)
	if err != nil {
		return false, err
	}
	return len(page.Items) > 0, nil
}

func (a *bucketAccess) stagePathFor(virtualPath string) string {
	return pathForVirtualKey(a.stageRoot, virtualPath)
}

func (a *bucketAccess) cachePathFor(virtualPath string) string {
	return pathForVirtualKey(a.cacheRoot, virtualPath)
}

func pathForVirtualKey(root, virtualPath string) string {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return filepath.Join(root, "_root")
	}
	sum := sha1.Sum([]byte(clean))
	encoded := hex.EncodeToString(sum[:])
	return filepath.Join(root, encoded[:2], encoded[2:])
}

func copyFile(dstPath, srcPath string) error {
	src, err := os.Open(srcPath)
	if err != nil {
		return err
	}
	defer src.Close()

	if err := os.MkdirAll(filepath.Dir(dstPath), 0o755); err != nil {
		return err
	}
	dst, err := os.Create(dstPath)
	if err != nil {
		return err
	}
	defer dst.Close()

	_, err = io.Copy(dst, src)
	return err
}

func fileSize(localPath string) int64 {
	info, err := os.Stat(localPath)
	if err != nil {
		return 0
	}
	return info.Size()
}
