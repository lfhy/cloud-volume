// Metadata write adapters make mounted mutations durable before returning success.
package mount

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"remote-storage/go/mount/metadata"
	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) usesMetadataWritePath() bool {
	return a != nil && a.metadataService() != nil
}

func (a *bucketAccess) stageMetadataWrite(virtualPath, localPath string, _ int64) error {
	service := a.metadataService()
	if service == nil {
		return fmt.Errorf("metadata write path is unavailable")
	}
	file, err := os.Open(localPath)
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	if info.IsDir() {
		return fmt.Errorf("metadata write source is a directory: %s", localPath)
	}

	// Cache markers must change in the same mount-local order as Desired paths.
	// The metadata facade has its own durable path order across all adapters.
	a.writebackMu.Lock()
	defer a.writebackMu.Unlock()
	inode, ref, err := service.WritePath(context.Background(), cleanVirtualPath(virtualPath), file, info.Size(), metadata.WriteOptions{
		Origin: "mount",
		MTime:  info.ModTime().Format("2006-01-02 15:04:05"),
	})
	if err != nil {
		return err
	}
	a.registerLocalWriteLocked(virtualPath, localPath, info.Size())
	if filepath.Clean(localPath) == filepath.Clean(a.cachePathFor(cleanVirtualPath(virtualPath))) {
		stampInfo := s3ops.ObjectInfo{
			Size: info.Size(), LastModified: info.ModTime().Format("2006-01-02 15:04:05"),
		}
		if stampErr := writePendingDownloadStamp(localPath, stampInfo, inode, ref.Generation); stampErr != nil {
			// Journal admission already succeeded; a stamp is only a cache hint.
			log.Printf("[mount/metadata] pending-cache-stamp path=%q error=%v", localPath, stampErr)
		}
	}
	return nil
}

func (a *bucketAccess) createMetadataDirectory(ctx context.Context, virtualPath string) error {
	service := a.metadataService()
	if service == nil {
		return fmt.Errorf("metadata write path is unavailable")
	}
	a.writebackMu.Lock()
	defer a.writebackMu.Unlock()
	if _, err := service.CreateDirectoryPath(ctx, cleanVirtualPath(virtualPath), metadata.WriteOptions{Origin: "mount"}); err != nil {
		return err
	}
	a.cache.invalidatePath(virtualPath)
	return nil
}

func (a *bucketAccess) deleteMetadataPath(ctx context.Context, virtualPath string, isDir bool) error {
	service := a.metadataService()
	if service == nil {
		return fmt.Errorf("metadata write path is unavailable")
	}
	clean := cleanVirtualPath(virtualPath)
	a.writebackMu.Lock()
	defer a.writebackMu.Unlock()
	if err := service.DeletePath(ctx, clean, metadata.WriteOptions{Origin: "mount"}); err != nil {
		return err
	}
	a.cache.removeLocalPath(clean, isDir)
	a.cache.invalidatePath(clean)
	ForgetPeerContent(a.config, a.bucket, clean)
	return nil
}

func (a *bucketAccess) renameMetadataPath(ctx context.Context, oldPath, newPath string, isDir bool) error {
	service := a.metadataService()
	if service == nil {
		return fmt.Errorf("metadata write path is unavailable")
	}
	oldClean, newClean := cleanVirtualPath(oldPath), cleanVirtualPath(newPath)
	a.writebackMu.Lock()
	defer a.writebackMu.Unlock()
	if err := a.cache.renameLocalFile(oldClean, newClean, isDir, a.cacheRoot); err != nil {
		return err
	}
	if err := service.RenamePath(ctx, oldClean, newClean, metadata.WriteOptions{Origin: "mount"}); err != nil {
		if rollbackErr := a.cache.renameLocalFile(newClean, oldClean, isDir, a.cacheRoot); rollbackErr != nil {
			return fmt.Errorf("%w; cache rename rollback: %v", err, rollbackErr)
		}
		return err
	}
	a.cache.invalidatePath(oldClean)
	a.cache.invalidatePath(newClean)
	ForgetPeerContent(a.config, a.bucket, oldClean)
	return nil
}

// renameMetadataPathAfterExternalMove records a Cloud Files rename after the
// provider callback has already moved its sync-root bytes.
func (a *bucketAccess) renameMetadataPathAfterExternalMove(
	ctx context.Context, oldPath, newPath, oldLocalPath, newLocalPath string, isDir bool,
) error {
	service := a.metadataService()
	if service == nil {
		return fmt.Errorf("metadata write path is unavailable")
	}
	oldClean, newClean := cleanVirtualPath(oldPath), cleanVirtualPath(newPath)
	a.writebackMu.Lock()
	defer a.writebackMu.Unlock()
	if err := service.RenamePath(ctx, oldClean, newClean, metadata.WriteOptions{Origin: "mount"}); err != nil {
		return err
	}
	// Explorer already performed the physical move. Rebinding only the cache
	// marker avoids a second os.Rename of the now-absent source path.
	a.cache.rebaseLocalFileAfterExternalMove(oldClean, newClean, oldLocalPath, newLocalPath, isDir)
	a.cache.invalidatePath(oldClean)
	a.cache.invalidatePath(newClean)
	ForgetPeerContent(a.config, a.bucket, oldClean)
	return nil
}
