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
	mu           sync.Mutex
	session      *mountSession
	lastProbe    mountProbeSnapshot
	lastProbeFor string
}

var globalManager = &manager{}

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

// UnmountBucket unmounts the current mount when it matches the provided bucket.
func UnmountBucket(bucket string) (BucketMountStatus, error) {
	return globalManager.unmountBucket(bucket)
}

// GetBucketMountStatus returns the current status for the requested bucket.
func GetBucketMountStatus(bucket string) (BucketMountStatus, error) {
	return globalManager.getBucketMountStatus(bucket)
}

// OpenBucketMount opens the mounted directory in the host file manager.
func OpenBucketMount(bucket string) (BucketMountStatus, error) {
	return globalManager.openBucketMount(bucket)
}

// CleanupMounts unmounts any active bucket volume during app shutdown.
func CleanupMounts() error {
	return globalManager.cleanupMounts()
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

	if err := m.syncSessionLocked(); err != nil {
		return BucketMountStatus{}, err
	}
	if m.session != nil && m.session.bucket == trimmedBucket {
		if mountSessionMatches(m.session, cfg, trimmedBucket, options) {
			return m.session.status(), nil
		}
		if err := m.unmountCurrentLocked(); err != nil {
			return BucketMountStatus{}, err
		}
	}
	if m.session != nil {
		if err := m.unmountCurrentLocked(); err != nil {
			return BucketMountStatus{}, err
		}
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

	m.session = session
	m.lastProbe = mountProbeSnapshot{}
	m.lastProbeFor = ""
	log.Printf("[mount/manager] mount-done bucket=%q path=%q url=%q", session.bucket, session.mountPath, session.serverURL)
	return session.status(), nil
}

func (m *manager) unmountBucket(bucket string) (BucketMountStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if err := m.syncSessionLocked(); err != nil {
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, err
	}
	if m.session == nil {
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, nil
	}
	if trimmed := normalizeBucketName(bucket); trimmed != "" && trimmed != m.session.bucket {
		return BucketMountStatus{Bucket: trimmed}, nil
	}

	status := m.session.status()
	if err := m.unmountCurrentLocked(); err != nil {
		return status, err
	}
	status.Mounted = false
	return status, nil
}

func (m *manager) getBucketMountStatus(bucket string) (BucketMountStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if err := m.syncSessionLocked(); err != nil {
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, err
	}
	if m.session == nil {
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, nil
	}
	if trimmed := normalizeBucketName(bucket); trimmed != "" && trimmed != m.session.bucket {
		return BucketMountStatus{Bucket: trimmed}, nil
	}
	return m.session.status(), nil
}

func (m *manager) openBucketMount(bucket string) (BucketMountStatus, error) {
	m.mu.Lock()
	if err := m.syncSessionLocked(); err != nil {
		m.mu.Unlock()
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, err
	}
	session := m.session
	m.mu.Unlock()

	if session == nil {
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, fmt.Errorf("bucket is not mounted")
	}
	if trimmed := normalizeBucketName(bucket); trimmed != "" && trimmed != session.bucket {
		return BucketMountStatus{Bucket: trimmed}, fmt.Errorf("bucket %q is not mounted", trimmed)
	}
	if err := openMountPath(session.mountPath); err != nil {
		return session.status(), err
	}
	return session.status(), nil
}

func (m *manager) syncSessionLocked() error {
	if m.session == nil {
		m.lastProbe = mountProbeSnapshot{}
		m.lastProbeFor = ""
		return nil
	}
	if m.session.stopping {
		return nil
	}
	active, err := m.cachedSessionActiveLocked(m.session)
	if err != nil {
		m.session.lastError = err.Error()
		return err
	}
	if active {
		m.session.mounted = true
		return nil
	}
	_ = m.session.backend.Stop(m.session)
	m.session = nil
	m.lastProbe = mountProbeSnapshot{}
	m.lastProbeFor = ""
	return nil
}

func (m *manager) cachedSessionActiveLocked(session *mountSession) (bool, error) {
	if session == nil {
		return false, nil
	}
	if session.stopping {
		return false, nil
	}
	if m.lastProbeFor == session.mountTarget &&
		!m.lastProbe.checkedAt.IsZero() &&
		time.Since(m.lastProbe.checkedAt) < mountProbeCacheTTL {
		return m.lastProbe.active, m.lastProbe.err
	}
	active, err := session.backend.IsActive(session)
	m.lastProbe = mountProbeSnapshot{
		checkedAt: time.Now(),
		active:    active,
		err:       err,
	}
	m.lastProbeFor = session.mountTarget
	return active, err
}

func (m *manager) unmountCurrentLocked() error {
	if m.session == nil {
		return nil
	}
	m.session.stopping = true
	log.Printf("[mount/manager] unmount-current bucket=%q target=%q", m.session.bucket, m.session.mountTarget)
	err := m.session.backend.Stop(m.session)
	m.session = nil
	m.lastProbe = mountProbeSnapshot{}
	m.lastProbeFor = ""
	if err != nil {
		log.Printf("[mount/manager] unmount-current-error err=%v", err)
		return err
	}
	log.Printf("[mount/manager] unmount-current-done")
	return nil
}

func (m *manager) cleanupMounts() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	log.Printf("[mount/manager] cleanup-start")
	if err := m.unmountCurrentLocked(); err != nil {
		log.Printf("[mount/manager] cleanup-current-error err=%v", err)
		return err
	}
	if err := cleanupAllManagedMounts(); err != nil {
		log.Printf("[mount/manager] cleanup-managed-error err=%v", err)
		return err
	}
	log.Printf("[mount/manager] cleanup-done")
	return nil
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
		config:        cfg,
		bucket:        bucket,
		rootPrefix:    normalizeRootPrefix(cfg.RootPrefix),
		requestedPath: normalizeMountPath(options.MountPath),
		readOnly:      options.ReadOnly,
		autoSync:      options.AutoSync,
		uploadWorkers: options.UploadWorkers,
		mountTarget:   normalizeMountPath(options.MountPath),
		access:        access,
		backend:       backend,
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
