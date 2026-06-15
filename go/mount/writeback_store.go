// Persistent writeback storage keeps mounted uploads resumable without a single shared DB lock.
package mount

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/panjf2000/ants/v2"
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
}

type writebackRecord struct {
	TaskID          string `json:"taskId"`
	VirtualPath     string `json:"virtualPath"`
	LocalPath       string `json:"localPath"`
	Size            int64  `json:"size"`
	ModTimeUnixNano int64  `json:"modTimeUnixNano"`
	DueAtUnixNano   int64  `json:"dueAtUnixNano"`
	RetryCount      int    `json:"retryCount"`
}

func acquireWritebackQueue(access *bucketAccess) (*writebackQueue, error) {
	storeDir := filepath.Join(access.sessionRoot, writebackStoreDirName)

	globalWritebackRegistry.mu.Lock()
	if existing, ok := globalWritebackRegistry.queues[storeDir]; ok {
		globalWritebackRegistry.mu.Unlock()
		existing.attach(access)
		return existing, nil
	}
	globalWritebackRegistry.mu.Unlock()

	store, err := openWritebackStore(storeDir)
	if err != nil {
		return nil, err
	}
	pool, err := ants.NewPool(access.config.WindowsWritebackConcurrency)
	if err != nil {
		_ = store.close()
		return nil, fmt.Errorf("create writeback worker pool: %w", err)
	}
	q := &writebackQueue{
		store:    store,
		storeKey: storeDir,
		entries:  map[string]*pendingWriteback{},
		running:  map[string]*pendingWriteback{},
		queue:    make(chan *pendingWriteback, 512),
		pool:     pool,
	}
	q.attach(access)
	if err := q.restorePersistedEntries(); err != nil {
		q.closeResources()
		return nil, err
	}
	q.wg.Add(1)
	go q.dispatch()

	globalWritebackRegistry.mu.Lock()
	globalWritebackRegistry.queues[storeDir] = q
	globalWritebackRegistry.mu.Unlock()
	return q, nil
}

func openWritebackStore(dirPath string) (*writebackStore, error) {
	if err := os.MkdirAll(dirPath, 0o755); err != nil {
		return nil, fmt.Errorf("create writeback store dir: %w", err)
	}
	filePath := filepath.Join(dirPath, fmt.Sprintf("queue-%d.json", os.Getpid()))
	store := &writebackStore{
		dirPath:  dirPath,
		filePath: filePath,
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

func (q *writebackQueue) restorePersistedEntries() error {
	records, err := q.store.list()
	if err != nil {
		return err
	}
	records = q.filterRestorableRecords(records)
	if err := q.store.replaceWithMerged(records); err != nil {
		return err
	}
	now := time.Now()
	for _, record := range records {
		entry := record.toPendingWriteback()
		if entry.virtualPath == "" || entry.taskID == "" {
			continue
		}
		q.entries[entry.virtualPath] = entry
		s3opsQueueTransferForEntry(q.currentAccess(), entry)
		delay := time.Until(entry.dueAt)
		if entry.dueAt.IsZero() || delay < 0 {
			delay = 0
			entry.dueAt = now
		}
		q.armTimerLocked(entry, delay)
	}
	return nil
}

func (q *writebackQueue) filterRestorableRecords(
	records []writebackRecord,
) []writebackRecord {
	access := q.currentAccess()
	if access == nil {
		return records
	}
	filtered := make([]writebackRecord, 0, len(records))
	for _, record := range records {
		if !q.canRestoreRecord(access, record) {
			continue
		}
		filtered = append(filtered, record)
	}
	return filtered
}

func (q *writebackQueue) canRestoreRecord(
	access *bucketAccess,
	record writebackRecord,
) bool {
	localPath := filepath.Clean(record.LocalPath)
	if localPath == "." || localPath == "" {
		return false
	}
	sessionRoot := filepath.Clean(access.sessionRoot)
	if !isPathWithin(localPath, sessionRoot) {
		return false
	}
	info, err := os.Stat(localPath)
	if err != nil || info.IsDir() {
		return false
	}
	return true
}

func isPathWithin(path, root string) bool {
	cleanPath := filepath.Clean(path)
	cleanRoot := filepath.Clean(root)
	if cleanPath == cleanRoot {
		return true
	}
	return strings.HasPrefix(cleanPath, cleanRoot+string(os.PathSeparator))
}

func (q *writebackQueue) pendingPaths() []string {
	q.mu.Lock()
	defer q.mu.Unlock()

	paths := make([]string, 0, len(q.entries)+len(q.running))
	for path := range q.entries {
		paths = append(paths, path)
	}
	for _, entry := range q.running {
		paths = append(paths, entry.virtualPath)
	}
	return paths
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
	records[cleanVirtualPath(entry.virtualPath)] = writebackRecord{
		TaskID:          entry.taskID,
		VirtualPath:     entry.virtualPath,
		LocalPath:       entry.localPath,
		Size:            entry.size,
		ModTimeUnixNano: entry.modTimeUnixNano,
		DueAtUnixNano:   entry.dueAt.UnixNano(),
		RetryCount:      entry.retryCount,
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
	delete(records, cleanVirtualPath(virtualPath))
	return s.writeOwnRecords(records)
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
		for key, record := range records {
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
		key := cleanVirtualPath(record.VirtualPath)
		if key == "" {
			continue
		}
		record.VirtualPath = key
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
		taskID:          r.TaskID,
		virtualPath:     cleanVirtualPath(r.VirtualPath),
		localPath:       r.LocalPath,
		size:            r.Size,
		modTimeUnixNano: r.ModTimeUnixNano,
		dueAt:           time.Unix(0, r.DueAtUnixNano),
		retryCount:      r.RetryCount,
	}
}
