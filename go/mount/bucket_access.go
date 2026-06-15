// Bucket access holds shared mount session state used by read/write helper files.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/panjf2000/ants/v2"
	"golang.org/x/sync/singleflight"

	storageconfig "remote-storage/go/config"
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
	autoSync        bool
	readOnly        bool
	uploadWorkers   int

	group singleflight.Group

	cache     *bucketCache
	overlay   *localMountOverlay
	dirSync   *dirSyncQueue
	writeback *writebackQueue
	deletes   *deleteQueue
	syncState syncStateProjector
}

func newBucketAccess(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (*bucketAccess, error) {
	cfg = cfg.Normalized()
	backend := storageops.ForConfig(cfg)
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

	access := &bucketAccess{
		config:          cfg,
		backend:         backend,
		bucket:          bucket,
		rootPrefix:      normalizeRootPrefix(cfg.RootPrefix),
		sessionRoot:     sessionRoot,
		cacheRoot:       cacheRoot,
		stageRoot:       stageRoot,
		requestTimeout:  defaultRequestTimeout * time.Second,
		transferTimeout: defaultTransferTimeout * time.Second,
		listTTL:         metadataCacheTTL,
		prefetchTTL:     prefetchTTL,
		allowPrefetch:   allowPrefetch,
		cache:           newBucketCache(metadataCacheTTL, prefetchTTL),
		overlay:         overlay,
	}
	access.dirSync = newDirSyncQueue(access)
	writeback, err := newWritebackQueue(access)
	if err != nil {
		access.dirSync.shutdown()
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
	if a == nil || a.writeback == nil {
		return nil
	}
	return a.writeback.drain()
}

func (a *bucketAccess) release() {
	if a == nil {
		return
	}
	a.syncState = nil
	if a.dirSync != nil {
		a.dirSync.shutdown()
		a.dirSync = nil
	}
}

type writebackQueue struct {
	accessMu sync.RWMutex
	access   *bucketAccess
	store    *writebackStore
	storeKey string
	mu       sync.Mutex
	entries  map[string]*pendingWriteback
	running  map[string]*pendingWriteback
	closed   bool
	draining bool
	drainErr error
	queue    chan *pendingWriteback
	pool     *ants.Pool
	quiet    time.Duration
	wg       sync.WaitGroup
}

type pendingWriteback struct {
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
