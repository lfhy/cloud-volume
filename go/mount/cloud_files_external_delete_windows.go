//go:build windows && cgo

// Windows external deletion projects remote mutations into the Cloud Files sync root.
package mount

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	s3ops "remote-storage/go/s3"
)

func (b *windowsCloudFilesBackend) removeExternalPlaceholder(
	session *mountSession,
	watcher *windowsSyncWatcher,
	virtualPath string,
	isDir bool,
) error {
	if session == nil || watcher == nil {
		return nil
	}
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return fmt.Errorf("refusing to remove Cloud Files sync root")
	}

	localPath := cloudFilesVirtualPathToLocal(session.mountPath, clean)
	if !isLocalPathWithinRoot(session.mountPath, localPath) {
		return fmt.Errorf("placeholder path escapes sync root: %q", clean)
	}
	info, err := os.Lstat(localPath)
	if err != nil {
		if os.IsNotExist(err) {
			watcher.Forget(localPath)
			return nil
		}
		return fmt.Errorf("stat external delete placeholder: %w", err)
	}

	removeTree := isDir || info.IsDir()
	watcher.MarkProviderDelete(localPath, removeTree)
	if removeTree {
		err = os.RemoveAll(localPath)
	} else {
		err = os.Remove(localPath)
	}
	if err != nil {
		watcher.ClearProviderDelete(localPath)
		return fmt.Errorf("remove external delete placeholder: %w", err)
	}
	watcher.Forget(localPath)
	log.Printf(
		"[mount/cloud-files] external-delete-local path=%q virtual=%q isDir=%t",
		localPath,
		clean,
		removeTree,
	)
	return nil
}

func (b *windowsCloudFilesBackend) createExternalPlaceholder(
	session *mountSession,
	watcher *windowsSyncWatcher,
	provider *cloudFilesProvider,
	virtualPath string,
	isDir bool,
) error {
	if session == nil || watcher == nil || provider == nil {
		return nil
	}
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return fmt.Errorf("refusing to create a placeholder for the sync root")
	}
	localPath := cloudFilesVirtualPathToLocal(session.mountPath, clean)
	if !isLocalPathWithinRoot(session.mountPath, localPath) {
		return fmt.Errorf("placeholder path escapes sync root: %q", clean)
	}

	info, err := session.access.statRemotePath(context.Background(), clean)
	if err != nil {
		// The remote mutation already succeeded. Keep enough metadata to make the
		// entry visible; a later fetch can refresh size/mtime if the backend omits HEAD.
		info = s3ops.ObjectInfo{Key: clean, IsDir: isDir, LastModified: time.Now().Format("2006-01-02 15:04:05")}
	}
	info.Key = clean
	info.IsDir = isDir || info.IsDir

	if _, err := os.Stat(localPath); err == nil {
		if err := b.removeExternalPlaceholder(session, watcher, clean, info.IsDir); err != nil {
			return err
		}
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("stat upload placeholder target: %w", err)
	}

	baseDir := filepath.Dir(localPath)
	if _, err := os.Stat(baseDir); err != nil {
		if os.IsNotExist(err) {
			// Do not materialize unknown parents as ordinary NTFS directories. The
			// next Cloud Files fetch-placeholders callback will create the tree.
			return nil
		}
		return fmt.Errorf("stat upload placeholder parent: %w", err)
	}
	item := cloudFilesPlaceholderInfo(info)
	if metadataItem, metadataErr := session.access.metadataStat(context.Background(), clean); metadataErr == nil {
		item = cloudFilesMetadataPlaceholderInfo(metadataItem, session.access.metadataNamespaceID())
	}
	item.RelativePath = filepath.Base(localPath)
	watcher.RememberPlaceholders(baseDir, []cloudPlaceholderInfo{item})
	if err := provider.CreatePlaceholders(baseDir, []cloudPlaceholderInfo{item}); err != nil {
		watcher.ClearProviderDelete(localPath)
		return err
	}
	watcher.watchPlaceholderDirectories(baseDir, []cloudPlaceholderInfo{item})
	log.Printf(
		"[mount/cloud-files] external-upload-local path=%q virtual=%q isDir=%t",
		localPath,
		clean,
		info.IsDir,
	)
	return nil
}

func isLocalPathWithinRoot(rootPath, localPath string) bool {
	root := filepath.Clean(rootPath)
	current := filepath.Clean(localPath)
	return current != root &&
		strings.HasPrefix(strings.ToLower(current), strings.ToLower(root)+string(os.PathSeparator))
}

func (w *windowsSyncWatcher) MarkProviderDelete(localPath string, isDir bool) {
	w.state.markProviderDelete(localPath, isDir)
}

func (w *windowsSyncWatcher) ClearProviderDelete(localPath string) {
	w.state.clearProviderDelete(localPath)
}

func (w *windowsSyncWatcher) IsProviderDelete(localPath string) bool {
	return w.state.isProviderDelete(localPath)
}
