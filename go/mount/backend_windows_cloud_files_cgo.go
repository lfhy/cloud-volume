//go:build windows && cgo

// Windows Cloud Files backends keep the Explorer shell native while the read path stays configurable.
package mount

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type windowsCloudFilesBackend struct {
	mode      string
	provider  *cloudFilesProvider
	hydrator  *cloudFilesHydrator
	watcher   *windowsSyncWatcher
	namespace *windowsShellNamespace
	healthMu  sync.Mutex
	lastCheck time.Time
	lastError string
}

func newWindowsCloudFilesBackend(mode string) (mountBackend, error) {
	return &windowsCloudFilesBackend{mode: mode}, nil
}

func (b *windowsCloudFilesBackend) Initialize(session *mountSession) error {
	session.mountName = session.bucket
	mountPath, err := windowsCloudFilesMountPath(session.bucket)
	if err != nil {
		return err
	}
	if session.requestedPath != "" {
		mountPath = session.requestedPath
	} else {
		session.managedPath = true
	}
	session.mountPath = mountPath
	session.mountTarget = session.mountPath
	return nil
}

func (b *windowsCloudFilesBackend) Start(session *mountSession) error {
	log.Printf(
		"[mount/cloud-files] start bucket=%q mode=%q path=%q",
		session.bucket,
		b.mode,
		session.mountPath,
	)
	// CFAPI reports deletes and renames after Explorer has already accepted the
	// local operation. Returning early from those callbacks only suppresses
	// writeback; it cannot provide a strict read-only filesystem. The UI routes
	// read-only requests to WinFsp, and this guard protects direct bridge calls.
	if session.readOnly {
		return fmt.Errorf("Cloud Files does not support strict read-only mounts; use the WinFsp engine")
	}
	if err := os.MkdirAll(session.mountPath, 0o755); err != nil {
		return fmt.Errorf("create sync-root directory: %w", err)
	}

	reader, err := newCloudFilesReader(b.mode, session.access)
	if err != nil {
		return err
	}
	watcher, err := newWindowsSyncWatcher(session.mountPath, session.access)
	if err != nil {
		return fmt.Errorf("create sync-root watcher: %w", err)
	}
	provider := newCloudFilesProvider(
		session.mountPath,
		windowsCFProviderID,
		windowsCloudFilesDisplayName(session.bucket, b.mode),
	)
	_ = provider.Deregister()
	if err := provider.Register(); err != nil {
		_ = watcher.Close()
		return err
	}

	hydrator := newCloudFilesHydrator(
		session.mountPath,
		session.access,
		provider,
		watcher,
		reader,
	)
	if err := provider.Connect(cloudFilesCallbacks{
		OnFetchData:         hydrator.OnFetchData,
		OnCancelFetch:       hydrator.OnCancelFetch,
		OnFetchPlaceholders: hydrator.OnFetchPlaceholders,
		OnDeleteCompletion:  b.handleDelete(session, watcher),
		OnRenameCompletion:  b.handleRename(session, watcher),
	}); err != nil {
		_ = provider.Deregister()
		_ = watcher.Close()
		return err
	}
	if err := watcher.Start(); err != nil {
		_ = provider.Disconnect()
		_ = provider.Deregister()
		_ = watcher.Close()
		return err
	}
	if err := hydrator.OnFetchPlaceholders(session.mountPath); err != nil {
		_ = watcher.Close()
		_ = provider.Disconnect()
		_ = provider.Deregister()
		return err
	}
	if session.config.WindowsThisPcEntryEnabled {
		namespace := newWindowsShellNamespace(session.bucket, session.mountPath)
		if err := namespace.Register(); err != nil {
			_ = watcher.Close()
			_ = provider.Disconnect()
			_ = provider.Deregister()
			return err
		}
		b.namespace = namespace
	}
	session.access.syncState = newCloudFilesSyncStateProjector(
		session.mountPath,
		provider,
	)

	b.provider = provider
	b.hydrator = hydrator
	b.watcher = watcher
	session.access.externalDelete = func(virtualPath string, isDir bool) error {
		return b.removeExternalPlaceholder(session, watcher, virtualPath, isDir)
	}
	session.access.externalUpload = func(virtualPath string, isDir bool) error {
		return b.createExternalPlaceholder(session, watcher, provider, virtualPath, isDir)
	}
	session.access.externalDirectoryRefresh = func(
		virtualPrefix string,
		items []s3ops.ObjectInfo,
	) error {
		return hydrator.RefreshPlaceholders(virtualPrefix, items)
	}
	session.access.externalMetadataDirectoryRefresh = func(
		virtualPrefix string,
		items []metadataMountObject,
	) error {
		return hydrator.RefreshMetadataPlaceholders(virtualPrefix, items)
	}
	b.resetHealthState()
	if err := b.checkHealthy(session, true); err != nil {
		log.Printf(
			"[mount/cloud-files] start-health-check bucket=%q mode=%q error=%v",
			session.bucket,
			b.mode,
			err,
		)
		return err
	}
	if session.requestedDriveLetter != "" {
		driveLetter, err := assignWindowsDriveLetter(
			session.mountPath,
			session.requestedDriveLetter,
		)
		if err != nil {
			return fmt.Errorf("assign Cloud Files drive letter: %w", err)
		}
		session.driveLetter = driveLetter
		log.Printf(
			"[mount/cloud-files] drive-mapped bucket=%q drive=%q path=%q",
			session.bucket,
			session.driveLetter,
			session.mountPath,
		)
	}
	session.mounted = true
	log.Printf(
		"[mount/cloud-files] start-done bucket=%q mode=%q path=%q",
		session.bucket,
		b.mode,
		session.mountPath,
	)
	return nil
}

func (b *windowsCloudFilesBackend) Stop(session *mountSession) error {
	log.Printf(
		"[mount/cloud-files] stop bucket=%q mode=%q path=%q",
		session.bucket,
		b.mode,
		session.mountPath,
	)
	session.mounted = false
	if session.access != nil {
		session.access.externalDelete = nil
		session.access.externalUpload = nil
	}

	var firstErr error
	if session.driveLetter != "" {
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=drive-unmap-start drive=%q", session.bucket, session.driveLetter)
		if err := removeWindowsDriveLetter(session.driveLetter, session.mountPath); err != nil {
			firstErr = err
		} else {
			session.driveLetter = ""
		}
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=drive-unmap-done err=%v", session.bucket, firstErr)
	}
	if b.provider != nil {
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=provider-disconnect-start", session.bucket)
		if err := b.provider.Disconnect(); err != nil && firstErr == nil {
			firstErr = err
		}
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=provider-disconnect-done err=%v", session.bucket, firstErr)
	}
	if b.watcher != nil {
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=watcher-close-start", session.bucket)
		if err := b.watcher.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=watcher-close-done err=%v", session.bucket, firstErr)
	}
	if b.provider != nil {
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=provider-deregister-start", session.bucket)
		if err := b.provider.Deregister(); err != nil && firstErr == nil {
			firstErr = err
		}
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=provider-deregister-done err=%v", session.bucket, firstErr)
	}
	if b.namespace != nil {
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=namespace-unregister-start", session.bucket)
		if err := b.namespace.Unregister(); err != nil && firstErr == nil {
			firstErr = err
		}
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=namespace-unregister-done err=%v", session.bucket, firstErr)
	}
	if session.access != nil {
		session.access.syncState = nil
		session.access.externalDirectoryRefresh = nil
		session.access.externalMetadataDirectoryRefresh = nil
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=access-close-start", session.bucket)
		session.access.release()
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=access-close-done err=%v", session.bucket, firstErr)
	}
	if session.removeLocalCache && session.managedPath {
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=cache-remove-start", session.bucket)
		if err := os.RemoveAll(session.mountPath); err != nil {
			// The mount is already safely disconnected. Keep it unmounted even
			// when another process still has a cached file open; surface the
			// actionable cleanup error through the returned status instead.
			session.lastError = fmt.Sprintf("本地缓存未删除，请先关闭占用文件后重试：%v", err)
		}
		log.Printf("[mount/cloud-files] stop-phase bucket=%q step=cache-remove-done err=%v", session.bucket, session.lastError)
	}

	b.provider = nil
	b.hydrator = nil
	b.watcher = nil
	b.namespace = nil
	b.resetHealthState()
	if firstErr != nil {
		log.Printf("[mount/cloud-files] stop-error bucket=%q error=%v", session.bucket, firstErr)
		return firstErr
	}
	log.Printf("[mount/cloud-files] stop-done bucket=%q", session.bucket)
	return firstErr
}

func (b *windowsCloudFilesBackend) IsActive(session *mountSession) (bool, error) {
	if b.provider == nil {
		return false, nil
	}
	if _, err := os.Stat(session.mountPath); err != nil {
		return false, nil
	}
	if !b.provider.IsConnected() {
		return false, nil
	}
	return true, nil
}

// CleanupStale only removes stale Cloud Files artifacts for the specific bucket
// being mounted. Previous implementations cleaned ALL buckets under the root,
// which broke concurrent multi-bucket mounts by tearing down other active sessions.
func (b *windowsCloudFilesBackend) CleanupStale(session *mountSession) error {
	if err := cleanupWindowsDriveMappingsForPath(session.mountPath); err != nil {
		return err
	}
	if err := cleanupManagedWindowsCloudFilesForBucket(session.bucket); err != nil {
		return err
	}
	return cleanupManagedWindowsWebDAVMountForBucket(session.bucket)
}

// cleanupManagedWindowsCloudFilesForBucket removes only the Cloud Files sync-root
// directory for the given bucket, deregistering its provider first.
func cleanupManagedWindowsCloudFilesForBucket(bucket string) error {
	mountPath, err := windowsCloudFilesMountPath(bucket)
	if err != nil {
		return err
	}
	if err := cleanupWindowsDriveMappingsForPath(mountPath); err != nil {
		return err
	}
	if _, statErr := os.Stat(mountPath); os.IsNotExist(statErr) {
		return nil
	}
	provider := newCloudFilesProvider(mountPath, windowsCFProviderID, "")
	if err := provider.Deregister(); err != nil {
		log.Printf("[mount/cloud-files] cleanup-bucket-deregister bucket=%q path=%q error=%v", bucket, mountPath, err)
	} else {
		log.Printf("[mount/cloud-files] cleanup-bucket-deregister bucket=%q path=%q", bucket, mountPath)
	}
	if err := os.RemoveAll(mountPath); err != nil && !os.IsNotExist(err) {
		// A disconnected Cloud Files root can retain a hydrated file opened by
		// Explorer or another application. The provider is already deregistered,
		// so retain that cache and let Start reuse the stable managed root.
		log.Printf("[mount/cloud-files] cleanup-bucket-retain bucket=%q path=%q error=%v", bucket, mountPath, err)
		return nil
	}
	log.Printf("[mount/cloud-files] cleanup-bucket-remove bucket=%q path=%q", bucket, mountPath)
	return nil
}

// cleanupManagedWindowsCloudFilesArtifacts removes ALL Cloud Files sync-root
// directories under the managed root. Used only during full cleanup/shutdown.
func cleanupManagedWindowsCloudFilesArtifacts() error {
	if err := cleanupManagedWindowsCloudFilesDriveMappings(); err != nil {
		return err
	}
	if err := cleanupLegacyWindowsShellNamespaces(); err != nil {
		return err
	}
	rootPath, err := windowsCloudFilesRootPath()
	if err != nil {
		return err
	}
	entries, err := os.ReadDir(rootPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("list Cloud Files root %q: %w", rootPath, err)
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		localPath := filepath.Join(rootPath, entry.Name())
		provider := newCloudFilesProvider(localPath, windowsCFProviderID, "")
		if err := provider.Deregister(); err != nil {
			log.Printf("[mount/cloud-files] cleanup-deregister path=%q error=%v", localPath, err)
		} else {
			log.Printf("[mount/cloud-files] cleanup-deregister path=%q", localPath)
		}
		if err := os.RemoveAll(localPath); err != nil {
			log.Printf("[mount/cloud-files] cleanup-remove path=%q error=%v", localPath, err)
			continue
		}
		log.Printf("[mount/cloud-files] cleanup-remove path=%q", localPath)
	}
	_ = os.Remove(rootPath)
	return nil
}

func (b *windowsCloudFilesBackend) handleDelete(
	session *mountSession,
	watcher *windowsSyncWatcher,
) func(localPath string) {
	return func(localPath string) {
		if watcher.IsProviderDelete(localPath) {
			watcher.Forget(localPath)
			return
		}
		if session.readOnly {
			return
		}
		virtualPath := cloudFilesLocalPathToVirtual(session.mountPath, localPath)
		if isWindowsLocalOnlyPath(virtualPath) {
			return
		}
		isDir := watcher.IsDir(localPath)
		watcher.Forget(localPath)
		if err := session.access.deletePath(context.Background(), virtualPath, isDir); err != nil {
			session.lastError = err.Error()
		}
	}
}

func (b *windowsCloudFilesBackend) handleRename(
	session *mountSession,
	watcher *windowsSyncWatcher,
) func(oldPath, newPath string) {
	return func(oldPath, newPath string) {
		if session.readOnly {
			return
		}
		oldVirtual := cloudFilesLocalPathToVirtual(session.mountPath, oldPath)
		newVirtual := cloudFilesLocalPathToVirtual(session.mountPath, newPath)
		if isWindowsLocalOnlyPath(oldVirtual) || isWindowsLocalOnlyPath(newVirtual) {
			return
		}
		isDir := watcher.IsDir(newPath)
		watcher.MarkRenameSource(oldPath, isDir)
		watcher.Rebase(oldPath, newPath, isDir)
		if err := session.access.enqueueRenamePath(
			oldVirtual,
			newVirtual,
			oldPath,
			newPath,
			isDir,
		); err != nil {
			session.lastError = err.Error()
		}
	}
}

func windowsCloudFilesDisplayName(bucket, mode string) string {
	switch mode {
	case storageconfig.WindowsMountModeCloudFilesDirect:
		return "Cloud Volume " + bucket + " (Direct)"
	default:
		return "Cloud Volume " + bucket
	}
}

func (b *windowsCloudFilesBackend) checkHealthy(
	session *mountSession,
	force bool,
) error {
	b.healthMu.Lock()
	if !force && time.Since(b.lastCheck) < windowsCloudFilesHealthCacheTTL {
		lastError := b.lastError
		b.healthMu.Unlock()
		if lastError != "" {
			return fmt.Errorf("%s", lastError)
		}
		return nil
	}
	b.healthMu.Unlock()

	if err := windowsCloudFilesWriteProbe(session.mountPath); err != nil {
		b.healthMu.Lock()
		b.lastCheck = time.Now()
		b.lastError = err.Error()
		b.healthMu.Unlock()
		return err
	}

	b.healthMu.Lock()
	b.lastCheck = time.Now()
	b.lastError = ""
	b.healthMu.Unlock()
	return nil
}

func (b *windowsCloudFilesBackend) resetHealthState() {
	b.healthMu.Lock()
	defer b.healthMu.Unlock()
	b.lastCheck = time.Time{}
	b.lastError = ""
}
