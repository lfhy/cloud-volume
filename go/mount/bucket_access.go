// Bucket access holds shared mount session state used by read/write helper files.
package mount

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/panjf2000/ants/v2"
	"golang.org/x/sync/singleflight"

	storageconfig "remote-storage/go/config"
	"remote-storage/go/mount/metadata"
	s3ops "remote-storage/go/s3"
	storageops "remote-storage/go/storage"
)

type bucketAccess struct {
	config          storageconfig.RemoteStorageConfig
	backend         storageops.Backend
	bucket          string
	rootPrefix      string
	sessionRoot     string
	cacheRoot       string
	stageRoot       string
	requestTimeout  time.Duration
	transferTimeout time.Duration
	listTTL         time.Duration
	prefetchTTL     time.Duration
	allowPrefetch   bool
	allowRemotePoll bool
	autoSync        bool
	readOnly        bool
	uploadWorkers   int
	quotaProvider   storageops.BucketQuotaProvider
	quotaMu         sync.Mutex
	writebackMu     sync.Mutex
	// mutationMu serializes remote path mutations after writebackMu has fixed
	// their local ordering, so a queued delete cannot overtake a rename move.
	mutationMu    sync.Mutex
	quotaCachedAt time.Time
	quotaTotal    int64
	quotaUsed     int64
	quotaKnown    bool
	quotaLoading  bool

	group singleflight.Group

	cache     *bucketCache
	pageViews *mountedDirectoryPageSnapshots
	overlay   *localMountOverlay
	dirSync   *dirSyncQueue
	writeback *writebackQueue
	deletes   *deleteQueue
	syncState syncStateProjector
	// metadataHandle keeps the shared namespace alive for the actual mount
	// lifetime, rather than letting short-lived page reads close its worker/DB.
	metadataHandle *metadata.AcquireHandle

	// externalDelete projects remote-first deletions into platform mount state.
	// It is installed by backends that expose a real sync root (Windows Cloud Files).
	externalDelete func(virtualPath string, isDir bool) error
	// externalUpload projects remote-first creates/overwrites into that sync root.
	externalUpload func(virtualPath string, isDir bool) error
	// externalDirectoryRefresh lets a platform projection materialize entries
	// found by the P0 remote-polling path without treating them as local writes.
	externalDirectoryRefresh func(virtualPrefix string, items []s3ops.ObjectInfo) error
	// externalMetadataDirectoryRefresh preserves metadata OIDs for platform
	// projections that can encode a stable object identity (Cloud Files).
	externalMetadataDirectoryRefresh func(virtualPrefix string, items []metadataMountObject) error
	directoryActivity                *directoryActivityTracker
}

func newBucketAccess(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (*bucketAccess, error) {
	cfg = cfg.Normalized()
	// The mount layer translates between virtual paths and provider keys using
	// its own rootPrefix below. Storage's scopedBackend would apply the same
	// prefix a second time, so build the backend from a config with RootPrefix
	// cleared and let bucketAccess own all prefix translation.
	backendCfg := cfg
	backendCfg.RootPrefix = ""
	backend := storageops.ForConfig(backendCfg)
	quotaBackend := storageops.ForConfig(cfg)
	quotaProvider, _ := quotaBackend.(storageops.BucketQuotaProvider)
	metadataCacheTTL := time.Duration(cfg.MountMetadataCacheSeconds) * time.Second
	if cfg.MountMetadataCacheSeconds < 0 {
		metadataCacheTTL = 0
	}
	allowPrefetch := metadataCacheTTL > 0 && storageops.SupportsMountPrefetch(backend)
	prefetchTTL := time.Duration(0)
	if allowPrefetch {
		prefetchTTL = metadataCacheTTL
	}
	mountRoot, err := storageconfig.MountRuntimeDir()
	if err != nil {
		return nil, err
	}
	cacheBase, err := storageconfig.ResolveCacheDir(cfg)
	if err != nil {
		return nil, err
	}
	sessionRoot := filepath.Join(mountRoot, safeSegment(bucket))
	cacheRoot := filepath.Join(cacheBase, "mounts", safeSegment(bucket))
	stageRoot := filepath.Join(sessionRoot, "staging")
	overlayRoot := filepath.Join(sessionRoot, "overlay")
	if err := os.MkdirAll(sessionRoot, 0o755); err != nil {
		return nil, fmt.Errorf("create mount session dir: %w", err)
	}
	if err := os.MkdirAll(cacheRoot, 0o755); err != nil {
		return nil, fmt.Errorf("create mount cache dir: %w", err)
	}
	if err := os.MkdirAll(stageRoot, 0o755); err != nil {
		return nil, fmt.Errorf("create mount staging dir: %w", err)
	}
	overlay, err := newLocalMountOverlay(overlayRoot)
	if err != nil {
		return nil, fmt.Errorf("create mount overlay dir: %w", err)
	}
	var metadataHandle *metadata.AcquireHandle
	if cfg.ProfileID != "" {
		manager, err := metadata.DefaultManager()
		if err != nil {
			return nil, fmt.Errorf("open mount metadata manager: %w", err)
		}
		metadataHandle, err = manager.Acquire(cfg, bucket)
		if err != nil {
			return nil, fmt.Errorf("acquire mount metadata: %w", err)
		}
	}

	access := &bucketAccess{
		config:            cfg,
		backend:           backend,
		bucket:            bucket,
		rootPrefix:        normalizeRootPrefix(cfg.RootPrefix),
		sessionRoot:       sessionRoot,
		cacheRoot:         cacheRoot,
		stageRoot:         stageRoot,
		requestTimeout:    defaultRequestTimeout * time.Second,
		transferTimeout:   defaultTransferTimeout * time.Second,
		listTTL:           metadataCacheTTL,
		prefetchTTL:       prefetchTTL,
		allowPrefetch:     allowPrefetch,
		allowRemotePoll:   storageops.SupportsMountRemotePolling(backend),
		quotaProvider:     quotaProvider,
		cache:             newBucketCache(metadataCacheTTL, prefetchTTL),
		pageViews:         newMountedDirectoryPageSnapshots(),
		overlay:           overlay,
		directoryActivity: newDirectoryActivityTracker(),
		metadataHandle:    metadataHandle,
	}
	if quota, fresh, ok := storageops.CachedBucketQuotaForMount(cfg, bucket); ok {
		if fresh {
			access.seedWebDAVQuota(quota.QuotaBytes, quota.UsedBytes, quota.QuotaKnown)
		} else {
			access.seedStaleWebDAVQuota(quota.QuotaBytes, quota.UsedBytes, quota.QuotaKnown)
		}
		log.Printf(
			"[mount/quota] seeded bucket=%q fresh=%t known=%t total_bytes=%d used_bytes=%d",
			bucket,
			fresh,
			quota.QuotaKnown,
			quota.QuotaBytes,
			quota.UsedBytes,
		)
	} else {
		log.Printf("[mount/quota] cache-miss bucket=%q", bucket)
	}
	access.dirSync = newDirSyncQueue(access)
	writeback, err := newWritebackQueue(access)
	if err != nil {
		access.dirSync.shutdown()
		access.releaseMetadata()
		return nil, err
	}
	access.writeback = writeback
	access.deletes = newDeleteQueue(access)
	return access, nil
}

func (a *bucketAccess) close() error {
	if a == nil {
		return nil
	}
	defer a.releaseMetadata()
	if a.dirSync != nil {
		a.dirSync.shutdown()
	}
	if a.writeback != nil {
		if err := a.writeback.shutdown(); err != nil {
			return err
		}
	}
	if a.deletes != nil {
		a.deletes.shutdown()
	}
	return nil
}

func (a *bucketAccess) drainWriteback() error {
	return a.drainWritebackContext(context.Background())
}

// drainWritebackContext lets lifecycle callers bound their own wait while the
// durable queue remains available for a later retry.
func (a *bucketAccess) drainWritebackContext(ctx context.Context) error {
	if a == nil || a.writeback == nil {
		return nil
	}
	return a.writeback.drainContext(ctx)
}

func (a *bucketAccess) release() {
	if a == nil {
		return
	}
	a.releaseMetadata()
	a.syncState = nil
	if a.dirSync != nil {
		a.dirSync.shutdown()
		a.dirSync = nil
	}
}

// releaseMetadata is safe for every platform stop path because the handle
// itself balances only its first Release call.
func (a *bucketAccess) releaseMetadata() {
	if a != nil && a.metadataHandle != nil {
		a.metadataHandle.Release()
	}
}

type writebackQueue struct {
	accessMu      sync.RWMutex
	access        *bucketAccess
	store         *writebackStore
	mutations     *mutationStore
	storeKey      string
	scope         string
	mu            sync.Mutex
	entries       map[string]*pendingWriteback
	running       map[string]*pendingWriteback
	generation    uint64
	barriers      []*writebackBarrier
	sourceRebases []writebackSourceRebase
	mutationErr   string
	closed        bool
	draining      bool
	drainErr      error
	queue         chan *pendingWriteback
	renameQueue   chan *queuedWritebackRename
	stop          chan struct{}
	pool          *ants.Pool
	quiet         time.Duration
	wg            sync.WaitGroup
	renameWG      sync.WaitGroup
}

type pendingWriteback struct {
	scope           string
	taskID          string
	virtualPath     string
	localPath       string
	size            int64
	modTimeUnixNano int64
	dueAt           time.Time
	timer           *time.Timer
	discard         bool
	queued          bool
	retryCount      int
	generation      uint64
}

func newWritebackQueue(access *bucketAccess) (*writebackQueue, error) {
	q, err := acquireWritebackQueue(access)
	if err != nil {
		return nil, fmt.Errorf("create writeback queue: %w", err)
	}
	return q, nil
}

type syncStateProjector interface {
	UpdateSyncState(virtualPath string, inSync bool) error
}
