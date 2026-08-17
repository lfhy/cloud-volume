// Persistent writeback storage keeps mounted uploads resumable without a single shared DB lock.
package mount

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/panjf2000/ants/v2"

	storageconfig "remote-storage/go/config"
)

var globalWritebackRegistry = &writebackRegistry{
	queues: map[string]*writebackQueue{},
}

const writebackStoreDirName = "writeback"

type writebackRegistry struct {
	mu     sync.Mutex
	queues map[string]*writebackQueue
}

type writebackStore struct {
	dirPath  string
	filePath string
	scope    string
}

type writebackRecord struct {
	Scope           string `json:"scope"`
	TaskID          string `json:"taskId"`
	VirtualPath     string `json:"virtualPath"`
	LocalPath       string `json:"localPath"`
	Size            int64  `json:"size"`
	ModTimeUnixNano int64  `json:"modTimeUnixNano"`
	DueAtUnixNano   int64  `json:"dueAtUnixNano"`
	RetryCount      int    `json:"retryCount"`
	Generation      uint64 `json:"generation,omitempty"`
}

func acquireWritebackQueue(access *bucketAccess) (*writebackQueue, error) {
	storeDir := filepath.Join(access.sessionRoot, writebackStoreDirName)
	scope := writebackScope(access.config, access.bucket)

	globalWritebackRegistry.mu.Lock()
	if existing, ok := globalWritebackRegistry.queues[storeDir]; ok {
		globalWritebackRegistry.mu.Unlock()
		if existing.scope != scope {
			return nil, fmt.Errorf("writeback queue scope changed; unmount the active bucket before remounting")
		}
		existing.attach(access)
		return existing, nil
	}
	globalWritebackRegistry.mu.Unlock()

	store, err := openWritebackStore(storeDir, scope)
	if err != nil {
		return nil, err
	}
	mutations, err := openMutationStore(filepath.Join(access.sessionRoot, mutationStoreDirName))
	if err != nil {
		_ = store.close()
		return nil, err
	}
	pool, err := ants.NewPool(access.config.WindowsWritebackConcurrency)
	if err != nil {
		_ = mutations.Close()
		_ = store.close()
		return nil, fmt.Errorf("create writeback worker pool: %w", err)
	}
	q := &writebackQueue{
		store:       store,
		mutations:   mutations,
		storeKey:    storeDir,
		scope:       scope,
		entries:     map[string]*pendingWriteback{},
		running:     map[string]*pendingWriteback{},
		queue:       make(chan *pendingWriteback, 512),
		renameQueue: make(chan *queuedWritebackRename, 64),
		stop:        make(chan struct{}),
		pool:        pool,
	}
	q.attach(access)
	if err := q.restorePersistedEntries(); err != nil {
		q.closeResources()
		return nil, err
	}
	if err := q.restorePersistedMutations(); err != nil {
		q.closeResources()
		return nil, err
	}
	q.wg.Add(1)
	go q.dispatch()
	q.renameWG.Add(1)
	go q.dispatchRenames()

	globalWritebackRegistry.mu.Lock()
	globalWritebackRegistry.queues[storeDir] = q
	globalWritebackRegistry.mu.Unlock()
	return q, nil
}

// writebackScope binds persisted local content to one account, endpoint, and
// view root. A same-named bucket must never replay an old queue into another
// remote account after configuration changes.
func writebackScope(config storageconfig.RemoteStorageConfig, bucket string) string {
	normalized := config.Normalized()
	raw := strings.Join([]string{
		normalized.ProfileID,
		normalized.StorageType,
		normalized.Endpoint,
		normalized.Bucket,
		normalized.RootPrefix,
		normalized.AccessKeyID,
		normalizeBucketName(bucket),
	}, "\x00")
	sum := sha256.Sum256([]byte(raw))
	return fmt.Sprintf("%x", sum[:])
}

func openWritebackStore(dirPath, scope string) (*writebackStore, error) {
	if err := os.MkdirAll(dirPath, 0o755); err != nil {
		return nil, fmt.Errorf("create writeback store dir: %w", err)
	}
	filePath := filepath.Join(dirPath, fmt.Sprintf("queue-%d.json", os.Getpid()))
	store := &writebackStore{
		dirPath:  dirPath,
		filePath: filePath,
		scope:    scope,
	}
	if err := store.ensureFile(); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *writebackStore) ensureFile() error {
	if s == nil {
		return nil
	}
	if _, err := os.Stat(s.filePath); err == nil {
		return nil
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("stat writeback store %q: %w", s.filePath, err)
	}
	if err := os.WriteFile(s.filePath, []byte("{}\n"), 0o600); err != nil {
		return fmt.Errorf("create writeback store %q: %w", s.filePath, err)
	}
	return nil
}

func (q *writebackQueue) attach(access *bucketAccess) {
	if access == nil {
		return
	}
	q.setQuietPeriod(access.config)
	q.accessMu.Lock()
	q.access = access
	q.accessMu.Unlock()

	paths := q.pendingPaths()
	for _, path := range paths {
		access.projectSyncState(path, false)
	}
}

func (q *writebackQueue) currentAccess() *bucketAccess {
	q.accessMu.RLock()
	defer q.accessMu.RUnlock()
	return q.access
}

func (q *writebackQueue) unregister() {
	globalWritebackRegistry.mu.Lock()
	defer globalWritebackRegistry.mu.Unlock()
	delete(globalWritebackRegistry.queues, q.storeKey)
}

func (q *writebackQueue) closeResources() {
	if q.pool != nil {
		q.pool.Release()
	}
	if q.mutations != nil {
		_ = q.mutations.Close()
	}
	if q.store != nil {
		_ = q.store.close()
	}
	q.unregister()
}

func (s *writebackStore) upsert(entry *pendingWriteback) error {
	if s == nil || entry == nil {
		return nil
	}
	records, err := s.readOwnRecords()
	if err != nil {
		return err
	}
	scope := entry.scope
	if scope == "" {
		scope = s.scope
	}
	records[writebackRecordKey(scope, entry.virtualPath)] = writebackRecord{
		Scope:           scope,
		TaskID:          entry.taskID,
		VirtualPath:     entry.virtualPath,
		LocalPath:       entry.localPath,
		Size:            entry.size,
		ModTimeUnixNano: entry.modTimeUnixNano,
		DueAtUnixNano:   entry.dueAt.UnixNano(),
		RetryCount:      entry.retryCount,
		Generation:      entry.generation,
	}
	return s.writeOwnRecords(records)
}

func (s *writebackStore) delete(virtualPath string) error {
	if s == nil || virtualPath == "" {
		return nil
	}
	records, err := s.readOwnRecords()
	if err != nil {
		return err
	}
	delete(records, writebackRecordKey(s.scope, virtualPath))
	return s.writeOwnRecords(records)
}

// writebackRecordKey keeps same-named paths from independent account scopes
// separate while they share the historical per-bucket queue directory.
func writebackRecordKey(scope, virtualPath string) string {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return ""
	}
	return scope + ":" + clean
}

func (s *writebackStore) list() ([]writebackRecord, error) {
	if s == nil {
		return nil, nil
	}
	files, err := filepath.Glob(filepath.Join(s.dirPath, "queue-*.json"))
	if err != nil {
		return nil, fmt.Errorf("glob writeback stores: %w", err)
	}
	sort.Strings(files)
	merged := map[string]writebackRecord{}
	for _, filePath := range files {
		records, err := readWritebackRecordsFile(filePath)
		if err != nil {
			return nil, err
		}
		for _, record := range records {
			key := writebackRecordKey(record.Scope, record.VirtualPath)
			if key == "" {
				continue
			}
			existing, ok := merged[key]
			if !ok || record.ModTimeUnixNano >= existing.ModTimeUnixNano {
				merged[key] = record
			}
		}
	}
	records := make([]writebackRecord, 0, len(merged))
	for _, record := range merged {
		records = append(records, record)
	}
	sort.Slice(records, func(i, j int) bool {
		if records[i].DueAtUnixNano == records[j].DueAtUnixNano {
			if records[i].VirtualPath == records[j].VirtualPath {
				return records[i].Scope < records[j].Scope
			}
			return records[i].VirtualPath < records[j].VirtualPath
		}
		return records[i].DueAtUnixNano < records[j].DueAtUnixNano
	})
	return records, nil
}

func (s *writebackStore) replaceWithMerged(records []writebackRecord) error {
	if s == nil {
		return nil
	}
	merged := map[string]writebackRecord{}
	for _, record := range records {
		key := writebackRecordKey(record.Scope, record.VirtualPath)
		if key == "" {
			continue
		}
		record.VirtualPath = cleanVirtualPath(record.VirtualPath)
		merged[key] = record
	}
	if err := s.writeOwnRecords(merged); err != nil {
		return err
	}
	files, err := filepath.Glob(filepath.Join(s.dirPath, "queue-*.json"))
	if err != nil {
		return fmt.Errorf("glob writeback stores for cleanup: %w", err)
	}
	for _, filePath := range files {
		if filepath.Clean(filePath) == filepath.Clean(s.filePath) {
			continue
		}
		if err := os.Remove(filePath); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("remove stale writeback store %q: %w", filePath, err)
		}
	}
	return nil
}

func (s *writebackStore) readOwnRecords() (map[string]writebackRecord, error) {
	if s == nil {
		return map[string]writebackRecord{}, nil
	}
	return readWritebackRecordsFile(s.filePath)
}

func readWritebackRecordsFile(filePath string) (map[string]writebackRecord, error) {
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		return map[string]writebackRecord{}, nil
	} else if err != nil {
		return nil, fmt.Errorf("stat writeback store %q: %w", filePath, err)
	}
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("read writeback store %q: %w", filePath, err)
	}
	trimmed := strings.TrimSpace(string(data))
	if trimmed == "" {
		return map[string]writebackRecord{}, nil
	}
	records := map[string]writebackRecord{}
	if err := json.Unmarshal([]byte(trimmed), &records); err != nil {
		return nil, fmt.Errorf("decode writeback store %q: %w", filePath, err)
	}
	return records, nil
}

func (s *writebackStore) writeOwnRecords(records map[string]writebackRecord) error {
	if s == nil {
		return nil
	}
	if records == nil {
		records = map[string]writebackRecord{}
	}
	payload, err := json.MarshalIndent(records, "", "  ")
	if err != nil {
		return fmt.Errorf("encode writeback store %q: %w", s.filePath, err)
	}
	if err := os.WriteFile(s.filePath, append(payload, '\n'), 0o600); err != nil {
		return fmt.Errorf("write writeback store %q: %w", s.filePath, err)
	}
	return nil
}

func (s *writebackStore) close() error {
	if s == nil {
		return nil
	}
	return nil
}

func (r writebackRecord) toPendingWriteback() *pendingWriteback {
	return &pendingWriteback{
		scope:           r.Scope,
		taskID:          r.TaskID,
		virtualPath:     cleanVirtualPath(r.VirtualPath),
		localPath:       r.LocalPath,
		size:            r.Size,
		modTimeUnixNano: r.ModTimeUnixNano,
		dueAt:           time.Unix(0, r.DueAtUnixNano),
		retryCount:      r.RetryCount,
		generation:      r.Generation,
	}
}

// restorePersistedMutations rebuilds upload barriers and local source rebases
// from persisted mutation records before either dispatcher starts. The
// invariant preserved across restart: uploads captured before a move finish
// before it, while uploads created after the move stay blocked until it
// reaches a verified terminal state. The next queue generation must exceed
// every restored generation so later work sorts after the fence.
