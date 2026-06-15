// Bucket access write helpers own create/delete/rename and local cache file utilities.
package mount

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
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
	if a != nil && a.readOnly {
		return
	}
	info := s3ops.ObjectInfo{
		Key:          cleanVirtualPath(virtualPath),
		Size:         size,
		LastModified: time.Now().Format("2006-01-02 15:04:05"),
		IsDir:        false,
	}
	a.cache.storeLocalFile(cleanVirtualPath(virtualPath), localPath, info)
}

func (a *bucketAccess) scheduleUpload(virtualPath, localPath string) {
	if a != nil && a.readOnly {
		return
	}
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
	hadPendingWriteback := a.writeback.rename(oldClean, newClean, isDir)
	if hadPendingWriteback {
		a.cache.renameLocalFile(oldClean, newClean, isDir, a.cacheRoot)
		a.cache.invalidatePath(oldClean)
		a.cache.invalidatePath(newClean)
		if !a.remotePathExists(ctx, oldClean, isDir) {
			return nil
		}
	}
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
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
	a.cache.renameLocalFile(oldClean, newClean, isDir, a.cacheRoot)
	a.cache.invalidatePath(oldClean)
	a.cache.invalidatePath(newClean)
	return nil
}

func (a *bucketAccess) remoteFileExists(ctx context.Context, virtualPath string) bool {
	_, err := a.backend.HeadObject(ctx, a.bucket, a.remoteKey(virtualPath))
	return err == nil
}

func (a *bucketAccess) remotePathExists(ctx context.Context, virtualPath string, isDir bool) bool {
	if !isDir {
		return a.remoteFileExists(ctx, virtualPath)
	}
	if _, err := a.backend.HeadObject(ctx, a.bucket, a.remoteKeyForMutation(virtualPath, true)); err == nil {
		return true
	}
	page, err := a.backend.ListObjectsPage(ctx, a.bucket, a.remotePrefix(virtualPath), "", 1)
	return err == nil && len(page.Items) > 0
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
