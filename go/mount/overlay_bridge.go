// Overlay bridge moves macOS volume-private temp content back into the remote bucket tree.
package mount

import (
	"context"
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) renameAcrossBoundary(
	ctx context.Context,
	oldVirtualPath,
	newVirtualPath string,
	isDir bool,
) error {
	oldOverlay := a.overlay.handles(oldVirtualPath)
	newOverlay := a.overlay.handles(newVirtualPath)
	log.Printf(
		"[mount/trash] renameAcrossBoundary old=%q new=%q isDir=%t oldOverlay=%t newOverlay=%t",
		oldVirtualPath,
		newVirtualPath,
		isDir,
		oldOverlay,
		newOverlay,
	)
	switch {
	case oldOverlay && !newOverlay:
		return a.moveOverlayPathToRemote(ctx, oldVirtualPath, newVirtualPath)
	case !oldOverlay && newOverlay:
		return a.handleRemoteMoveIntoOverlay(ctx, oldVirtualPath, newVirtualPath, isDir)
	default:
		return fmt.Errorf("unsupported mount rename between %q and %q", oldVirtualPath, newVirtualPath)
	}
}

func (a *bucketAccess) handleRemoteMoveIntoOverlay(
	ctx context.Context,
	oldVirtualPath,
	newVirtualPath string,
	isDir bool,
) error {
	if a.overlay.isTrashPath(newVirtualPath) {
		log.Printf(
			"[mount/trash] treating move into trash as delete old=%q new=%q isDir=%t",
			oldVirtualPath,
			newVirtualPath,
			isDir,
		)
		return a.deletePath(ctx, oldVirtualPath, isDir)
	}
	log.Printf(
		"[mount/trash] unsupported move into overlay old=%q new=%q isDir=%t",
		oldVirtualPath,
		newVirtualPath,
		isDir,
	)
	return fmt.Errorf("moving remote objects into system temporary mount folders is not supported")
}

func (a *bucketAccess) moveOverlayPathToRemote(
	_ context.Context,
	oldVirtualPath,
	newVirtualPath string,
) error {
	info, err := a.overlay.statPath(oldVirtualPath)
	if err != nil {
		return err
	}
	if info.IsDir() {
		if err := a.stageOverlayDirectory(oldVirtualPath, newVirtualPath); err != nil {
			return err
		}
	} else {
		if err := a.stageOverlayFile(oldVirtualPath, newVirtualPath); err != nil {
			return err
		}
	}
	if err := a.overlay.removeAll(oldVirtualPath); err != nil {
		return err
	}
	a.cache.invalidatePath(oldVirtualPath)
	a.cache.invalidatePath(newVirtualPath)
	return nil
}

func (a *bucketAccess) stageOverlayDirectory(oldVirtualPath, newVirtualPath string) error {
	localRoot := a.overlay.localPath(oldVirtualPath)
	if err := a.stageLocalDirectory(newVirtualPath, time.Now()); err != nil {
		return err
	}
	return filepath.WalkDir(localRoot, func(current string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if current == localRoot {
			return nil
		}
		relative, err := filepath.Rel(localRoot, current)
		if err != nil {
			return err
		}
		virtualRelative := filepath.ToSlash(relative)
		targetVirtualPath := joinVirtualPath(newVirtualPath, virtualRelative)
		if entry.IsDir() {
			info, err := entry.Info()
			if err != nil {
				return err
			}
			return a.stageLocalDirectory(targetVirtualPath, info.ModTime())
		}
		sourceVirtualPath := joinVirtualPath(oldVirtualPath, virtualRelative)
		return a.stageOverlayFile(sourceVirtualPath, targetVirtualPath)
	})
}

func (a *bucketAccess) stageOverlayFile(oldVirtualPath, newVirtualPath string) error {
	localPath := a.overlay.localPath(oldVirtualPath)
	info, err := os.Stat(localPath)
	if err != nil {
		return err
	}
	cachePath := a.cachePathFor(newVirtualPath)
	if err := copyFile(cachePath, localPath); err != nil {
		return err
	}
	return a.stageLocalWrite(newVirtualPath, cachePath, info.Size())
}

func joinVirtualPath(basePath, relativePath string) string {
	base := cleanVirtualPath(basePath)
	relative := cleanVirtualPath(relativePath)
	switch {
	case base == "":
		return relative
	case relative == "":
		return base
	default:
		return base + "/" + relative
	}
}

func (a *bucketAccess) stageLocalDirectory(virtualPath string, modTime time.Time) error {
	if a == nil {
		return nil
	}
	if a.usesMetadataWritePath() {
		return a.createMetadataDirectory(context.Background(), virtualPath)
	}
	a.writebackMu.Lock()
	defer a.writebackMu.Unlock()
	a.stageLocalDirectoryLocked(virtualPath, modTime)
	return nil
}

func (a *bucketAccess) stageLocalDirectoryLocked(virtualPath string, modTime time.Time) {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return
	}
	a.cache.storeLocalDirectory(clean, s3ops.ObjectInfo{
		Key:          ensureDirSuffix(clean),
		LastModified: modTime.Format("2006-01-02 15:04:05"),
		IsDir:        true,
	})
	a.cache.invalidatePath(clean)
	a.queueRemoteDirectory(clean)
}

func (a *bucketAccess) queueRemoteDirectory(virtualPath string) {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" || a.dirSync == nil {
		return
	}
	a.dirSync.enqueue(clean)
}

func (a *bucketAccess) createRemoteDirectory(
	ctx context.Context,
	virtualPath string,
) error {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return nil
	}
	parent := parentVirtualPrefix(clean)
	name := baseName(clean)
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	err := a.backend.CreateDirectory(timeoutCtx, a.bucket, a.remotePrefix(parent), name)
	if err != nil && !strings.Contains(strings.ToLower(err.Error()), "exists") {
		return err
	}
	return nil
}
