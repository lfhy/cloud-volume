// Writeback store tests cover per-process journal recovery and merge behavior.
package mount

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestWritebackStoreMergesLatestEntryAcrossQueueFiles(t *testing.T) {
	t.Parallel()

	storeDir := filepath.Join(t.TempDir(), writebackStoreDirName)
	if err := os.MkdirAll(storeDir, 0o755); err != nil {
		t.Fatalf("mkdir store dir: %v", err)
	}
	writeWritebackQueueFile(t, filepath.Join(storeDir, "queue-100.json"), map[string]writebackRecord{
		"folder/file.txt": {
			TaskID:          "task-old",
			VirtualPath:     "folder/file.txt",
			LocalPath:       "C:/old.txt",
			Size:            1,
			ModTimeUnixNano: 100,
			DueAtUnixNano:   200,
			RetryCount:      1,
		},
	})
	writeWritebackQueueFile(t, filepath.Join(storeDir, "queue-101.json"), map[string]writebackRecord{
		"folder/file.txt": {
			TaskID:          "task-new",
			VirtualPath:     "folder/file.txt",
			LocalPath:       "C:/new.txt",
			Size:            2,
			ModTimeUnixNano: 300,
			DueAtUnixNano:   400,
			RetryCount:      0,
		},
	})

	store, err := openWritebackStore(storeDir)
	if err != nil {
		t.Fatalf("openWritebackStore: %v", err)
	}
	records, err := store.list()
	if err != nil {
		t.Fatalf("store.list: %v", err)
	}
	if len(records) != 1 {
		t.Fatalf("expected 1 merged record, got %d", len(records))
	}
	if records[0].TaskID != "task-new" || records[0].LocalPath != "C:/new.txt" {
		t.Fatalf("expected newest merged record, got %+v", records[0])
	}
}

func TestWritebackStoreDeleteRemovesOnlyCurrentProcessEntry(t *testing.T) {
	t.Parallel()

	storeDir := filepath.Join(t.TempDir(), writebackStoreDirName)
	store, err := openWritebackStore(storeDir)
	if err != nil {
		t.Fatalf("openWritebackStore: %v", err)
	}
	otherPath := filepath.Join(storeDir, "queue-999.json")
	writeWritebackQueueFile(t, otherPath, map[string]writebackRecord{
		"other/file.txt": {
			TaskID:          "task-other",
			VirtualPath:     "other/file.txt",
			LocalPath:       "C:/other.txt",
			Size:            3,
			ModTimeUnixNano: 300,
			DueAtUnixNano:   400,
		},
	})

	entry := &pendingWriteback{
		taskID:          "task-local",
		virtualPath:     "local/file.txt",
		localPath:       "C:/local.txt",
		size:            4,
		modTimeUnixNano: 500,
	}
	if err := store.upsert(entry); err != nil {
		t.Fatalf("store.upsert: %v", err)
	}
	if err := store.delete(entry.virtualPath); err != nil {
		t.Fatalf("store.delete: %v", err)
	}

	records, err := store.list()
	if err != nil {
		t.Fatalf("store.list: %v", err)
	}
	if len(records) != 1 {
		t.Fatalf("expected only other process entry to remain, got %d", len(records))
	}
	if records[0].VirtualPath != "other/file.txt" {
		t.Fatalf("unexpected remaining record %+v", records[0])
	}
}

func TestWritebackStoreReplaceWithMergedCompactsOldQueueFiles(t *testing.T) {
	t.Parallel()

	storeDir := filepath.Join(t.TempDir(), writebackStoreDirName)
	store, err := openWritebackStore(storeDir)
	if err != nil {
		t.Fatalf("openWritebackStore: %v", err)
	}
	writeWritebackQueueFile(t, filepath.Join(storeDir, "queue-100.json"), map[string]writebackRecord{
		"folder/a.txt": {
			TaskID:          "task-a",
			VirtualPath:     "folder/a.txt",
			LocalPath:       "C:/a.txt",
			Size:            1,
			ModTimeUnixNano: 100,
			DueAtUnixNano:   200,
		},
	})
	writeWritebackQueueFile(t, filepath.Join(storeDir, "queue-101.json"), map[string]writebackRecord{
		"folder/b.txt": {
			TaskID:          "task-b",
			VirtualPath:     "folder/b.txt",
			LocalPath:       "C:/b.txt",
			Size:            2,
			ModTimeUnixNano: 200,
			DueAtUnixNano:   300,
		},
	})

	records, err := store.list()
	if err != nil {
		t.Fatalf("store.list: %v", err)
	}
	if err := store.replaceWithMerged(records); err != nil {
		t.Fatalf("store.replaceWithMerged: %v", err)
	}

	files, err := filepath.Glob(filepath.Join(storeDir, "queue-*.json"))
	if err != nil {
		t.Fatalf("glob queue files: %v", err)
	}
	if len(files) != 1 {
		t.Fatalf("expected compacted store to leave 1 queue file, got %d", len(files))
	}
}

func TestRestorePersistedEntriesDropsMissingLocalPaths(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	storeDir := filepath.Join(access.sessionRoot, writebackStoreDirName)
	missingPath := filepath.Join(
		t.TempDir(),
		"stale-mount",
		"folder",
		"file.txt",
	)
	writeWritebackQueueFile(t, filepath.Join(storeDir, "queue-100.json"), map[string]writebackRecord{
		"folder/file.txt": {
			TaskID:          "task-stale",
			VirtualPath:     "folder/file.txt",
			LocalPath:       missingPath,
			Size:            12,
			ModTimeUnixNano: 100,
			DueAtUnixNano:   200,
		},
	})

	if err := access.writeback.shutdown(); err != nil {
		t.Fatalf("shutdown writeback queue: %v", err)
	}

	restored, err := newWritebackQueue(access)
	if err != nil {
		t.Fatalf("restore writeback queue: %v", err)
	}
	t.Cleanup(func() {
		_ = restored.shutdown()
	})
	access.writeback = restored

	if len(restored.entries) != 0 {
		t.Fatalf("expected stale persisted entries to be dropped, got %d", len(restored.entries))
	}
	records, err := restored.store.list()
	if err != nil {
		t.Fatalf("read compacted store: %v", err)
	}
	if len(records) != 0 {
		t.Fatalf("expected stale persisted records to be removed, got %d", len(records))
	}
}

func TestRestorePersistedEntriesKeepsCacheRootFiles(t *testing.T) {
	access := newTestBucketAccess(t)
	cacheRoot := t.TempDir()
	access.cacheRoot = cacheRoot
	localPath := filepath.Join(cacheRoot, "archive", "output.zip")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir cache path: %v", err)
	}
	if err := os.WriteFile(localPath, []byte("payload"), 0o600); err != nil {
		t.Fatalf("write cache file: %v", err)
	}

	storeDir := filepath.Join(access.sessionRoot, writebackStoreDirName)
	writeWritebackQueueFile(t, filepath.Join(storeDir, "queue-100.json"), map[string]writebackRecord{
		"archive/output.zip": {
			TaskID:          "task-cache-root",
			VirtualPath:     "archive/output.zip",
			LocalPath:       localPath,
			Size:            int64(len("payload")),
			ModTimeUnixNano: time.Now().UnixNano(),
			DueAtUnixNano:   time.Now().Add(time.Hour).UnixNano(),
		},
	})

	if err := access.writeback.shutdown(); err != nil {
		t.Fatalf("shutdown writeback queue: %v", err)
	}
	restored, err := newWritebackQueue(access)
	if err != nil {
		t.Fatalf("restore writeback queue: %v", err)
	}
	access.writeback = restored

	entry := restored.entries["archive/output.zip"]
	if entry == nil || entry.localPath != localPath {
		t.Fatalf("cache-root record was not restored: %+v", entry)
	}
}

func writeWritebackQueueFile(
	t *testing.T,
	filePath string,
	records map[string]writebackRecord,
) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(filePath), 0o755); err != nil {
		t.Fatalf("mkdir parent dir: %v", err)
	}
	payload, err := json.Marshal(records)
	if err != nil {
		t.Fatalf("marshal records: %v", err)
	}
	if err := os.WriteFile(filePath, payload, 0o600); err != nil {
		t.Fatalf("write queue file: %v", err)
	}
}
