// Mount manager keeps the public lifecycle API stable while platform backends vary.
package mount

import (
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	storageconfig "remote-storage/go/config"
)

type manager struct {
	mu         sync.Mutex
	sessions   map[string]*mountSession
	lastProbes map[string]mountProbeSnapshot
}

var globalManager = &manager{
	sessions:   make(map[string]*mountSession),
	lastProbes: make(map[string]mountProbeSnapshot),
}

// MountBucket starts the platform mount backend for one bucket at a time.
func MountBucket(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (BucketMountStatus, error) {
	return globalManager.mountBucket(cfg, bucket, MountOptions{})
}

// MountBucketWithOptions lets non-desktop callers override mount details such
// as the Linux mountpoint while keeping the existing public desktop API stable.
func MountBucketWithOptions(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	options MountOptions,
) (BucketMountStatus, error) {
	return globalManager.mountBucket(cfg, bucket, options)
}

// UnmountBucket unmounts the requested bucket if it is currently mounted.
func UnmountBucket(bucket string) (BucketMountStatus, error) {
	return globalManager.unmountBucket(bucket, UnmountOptions{})
}

// UnmountBucketWithOptions lets the desktop UI explicitly clear a managed
// Cloud Files cache after the volume has been disconnected.
func UnmountBucketWithOptions(bucket string, options UnmountOptions) (BucketMountStatus, error) {
	return globalManager.unmountBucket(bucket, options)
}

// GetBucketMountStatus returns the current status for the requested bucket.
func GetBucketMountStatus(bucket string) (BucketMountStatus, error) {
	return globalManager.getBucketMountStatus(bucket)
}

// OpenBucketMount opens the mounted directory in the host file manager.
func OpenBucketMount(bucket string) (BucketMountStatus, error) {
	return globalManager.openBucketMount(bucket)
}

// CleanupMounts unmounts all active bucket volumes during app shutdown.
func CleanupMounts() error {
	return globalManager.cleanupMounts()
}

// ActiveMountCount returns the number of live in-process mount sessions.
func ActiveMountCount() int {
	return globalManager.activeMountCount()
}

func (m *manager) mountBucket(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	options MountOptions,
) (BucketMountStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	trimmedBucket := normalizeBucketName(bucket)
	if trimmedBucket == "" {
		trimmedBucket = normalizeBucketName(cfg.Bucket)
	}
	if trimmedBucket == "" {
		return BucketMountStatus{}, fmt.Errorf("missing bucket name")
	}
	log.Printf("[mount/manager] mount-start bucket=%q root_prefix=%q", trimmedBucket, normalizeRootPrefix(cfg.RootPrefix))

	if existing, ok := m.sessions[trimmedBucket]; ok {
		if m.syncSessionLocked(existing) {
			if mountSessionMatches(existing, cfg, trimmedBucket, options) {
				return existing.status(), nil
			}
		}
		// Do not replace a session that refused to stop: its durable writeback
		// queue is still attached to the old remote configuration.
		if err := m.unmountSessionLocked(existing); err != nil {
			return existing.status(), err
		}
		delete(m.sessions, trimmedBucket)
		delete(m.lastProbes, existing.mountTarget)
	}
	if cfg.BucketSettingsFor(trimmedBucket).ReadOnly {
		options.ReadOnly = true
	}

	session, err := newMountSession(cfg.Normalized(), trimmedBucket, options)
	if err != nil {
		return BucketMountStatus{}, err
	}
	log.Printf("[mount/manager] mount-session-ready bucket=%q mount_name=%q target=%q", session.bucket, session.mountName, session.mountTarget)
	if err := session.backend.CleanupStale(session); err != nil {
		log.Printf("[mount/manager] mount-cleanup-stale-error bucket=%q err=%v", session.bucket, err)
		return BucketMountStatus{}, err
	}
	log.Printf("[mount/manager] mount-cleanup-stale-done bucket=%q", session.bucket)
	if err := session.backend.Start(session); err != nil {
		log.Printf("[mount/manager] mount-start-error bucket=%q err=%v", session.bucket, err)
		_ = session.backend.Stop(session)
		return BucketMountStatus{}, err
	}
	session.remotePoller = newRemoteDirectoryPoller(session)
	session.remotePoller.Start()

	m.sessions[trimmedBucket] = session
	delete(m.lastProbes, session.mountTarget)
	log.Printf("[mount/manager] mount-done bucket=%q path=%q url=%q", session.bucket, session.mountPath, session.serverURL)
	return session.status(), nil
}

func (m *manager) unmountBucket(bucket string, options UnmountOptions) (BucketMountStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	trimmedBucket := normalizeBucketName(bucket)
	existing, ok := m.sessions[trimmedBucket]
	if !ok {
		return BucketMountStatus{Bucket: trimmedBucket}, nil
	}

	status := existing.status()
	existing.removeLocalCache = options.RemoveLocalCache
	if err := m.unmountSessionLocked(existing); err != nil {
		return status, err
	}
	status = existing.status()
	delete(m.sessions, trimmedBucket)
	delete(m.lastProbes, existing.mountTarget)
	status.Mounted = false
	return status, nil
}

func (m *manager) getBucketMountStatus(bucket string) (BucketMountStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	trimmedBucket := normalizeBucketName(bucket)
	existing, ok := m.sessions[trimmedBucket]
	if !ok {
		return BucketMountStatus{Bucket: trimmedBucket}, nil
	}
	if !m.syncSessionLocked(existing) {
		delete(m.sessions, trimmedBucket)
		delete(m.lastProbes, existing.mountTarget)
		return BucketMountStatus{Bucket: trimmedBucket}, nil
	}
	return existing.status(), nil
}

func (m *manager) openBucketMount(bucket string) (BucketMountStatus, error) {
	m.mu.Lock()
	trimmedBucket := normalizeBucketName(bucket)
	existing, ok := m.sessions[trimmedBucket]
	if !ok {
		m.mu.Unlock()
		return BucketMountStatus{Bucket: trimmedBucket}, fmt.Errorf("bucket is not mounted")
	}
	if !m.syncSessionLocked(existing) {
		delete(m.sessions, trimmedBucket)
		delete(m.lastProbes, existing.mountTarget)
		m.mu.Unlock()
		return BucketMountStatus{Bucket: trimmedBucket}, fmt.Errorf("bucket is not mounted")
	}
	session := existing
	m.mu.Unlock()

	openPath := session.mountPath
	if session.driveLetter != "" {
		openPath = session.driveLetter
	}
	if err := openMountPath(openPath); err != nil {
		return session.status(), err
	}
	return session.status(), nil
}

// syncSessionLocked checks whether a session is still usable. A failed Stop can
// deliberately leave a durable mount live, so callers must retain that session.
func (m *manager) syncSessionLocked(session *mountSession) bool {
	if session == nil || session.stopping {
		return false
	}
	active, err := m.cachedSessionActiveLocked(session)
	if err != nil {
		session.lastError = err.Error()
		if stopErr := session.backend.Stop(session); stopErr != nil {
			session.lastError = fmt.Sprintf("%s\n停止挂载失败: %v", session.lastError, stopErr)
			return session.mounted && !session.stopping
		}
		return false
	}
	if active {
		session.mounted = true
		return true
	}
	if stopErr := session.backend.Stop(session); stopErr != nil {
		session.lastError = stopErr.Error()
		return session.mounted && !session.stopping
	}
	return false
}

func (m *manager) cachedSessionActiveLocked(session *mountSession) (bool, error) {
	if session.stopping {
		return false, nil
	}
	target := session.mountTarget
	if probe, ok := m.lastProbes[target]; ok && !probe.checkedAt.IsZero() && time.Since(probe.checkedAt) < mountProbeCacheTTL {
		return probe.active, probe.err
	}
	active, err := session.backend.IsActive(session)
	m.lastProbes[target] = mountProbeSnapshot{
		checkedAt: time.Now(),
		active:    active,
		err:       err,
	}
	return active, err
}

func (m *manager) unmountSessionLocked(session *mountSession) error {
	if session == nil {
		return nil
	}
	session.stopping = true
	if session.remotePoller != nil {
		session.remotePoller.Stop()
		session.remotePoller = nil
	}
	log.Printf("[mount/manager] unmount-session bucket=%q target=%q", session.bucket, session.mountTarget)
	err := session.backend.Stop(session)
	if err != nil {
		// A backend can preserve a live mount by clearing stopping before it
		// returns the error; restore its poller so the session remains usable.
		if session.mounted && !session.stopping {
			session.remotePoller = newRemoteDirectoryPoller(session)
			session.remotePoller.Start()
		}
		log.Printf("[mount/manager] unmount-session-error bucket=%q err=%v", session.bucket, err)
		return err
	}
	log.Printf("[mount/manager] unmount-session-done bucket=%q", session.bucket)
	return nil
}

func (m *manager) cleanupMounts() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	log.Printf("[mount/manager] cleanup-start")
	var firstErr error
	for bucket, session := range m.sessions {
		if err := m.unmountSessionLocked(session); err != nil {
			log.Printf("[mount/manager] cleanup-session-error bucket=%q err=%v", bucket, err)
			if firstErr == nil {
				firstErr = fmt.Errorf("cleanup mount %q: %w", bucket, err)
			}
			continue
		}
		delete(m.lastProbes, session.mountTarget)
		delete(m.sessions, bucket)
	}
	if firstErr != nil {
		// A backend that deliberately kept its mount alive (for example after a
		// macOS writeback drain timeout) must remain retriable in this process.
		return firstErr
	}
	m.lastProbes = make(map[string]mountProbeSnapshot)
	if err := cleanupAllManagedMounts(); err != nil {
		log.Printf("[mount/manager] cleanup-managed-error err=%v", err)
		return err
	}
	log.Printf("[mount/manager] cleanup-done")
	return nil
}

func (m *manager) activeMountCount() int {
	m.mu.Lock()
	defer m.mu.Unlock()

	count := 0
	for _, session := range m.sessions {
		if session != nil && session.mounted && !session.stopping {
			count++
		}
	}
	return count
}

func newMountSession(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	options MountOptions,
) (*mountSession, error) {
	access, err := newBucketAccess(cfg, bucket)
	if err != nil {
		return nil, err
	}
	backend, err := newPlatformMountBackend(cfg)
	if err != nil {
		_ = access.close()
		return nil, err
	}
	session := &mountSession{
		config:               cfg,
		bucket:               bucket,
		rootPrefix:           normalizeRootPrefix(cfg.RootPrefix),
		requestedPath:        normalizeMountPath(options.MountPath),
		readOnly:             options.ReadOnly,
		requestedDriveLetter: strings.ToUpper(strings.TrimSpace(options.DriveLetter)),
		autoSync:             options.AutoSync,
		uploadWorkers:        options.UploadWorkers,
		mountTarget:          normalizeMountPath(options.MountPath),
		access:               access,
		backend:              backend,
	}
	if err := backend.Initialize(session); err != nil {
		_ = access.close()
		return nil, err
	}
	access.autoSync = session.autoSync
	access.readOnly = session.readOnly
	access.uploadWorkers = session.uploadWorkers
	return session, nil
}

func normalizeBucketName(value string) string {
	return strings.TrimSpace(value)
}
