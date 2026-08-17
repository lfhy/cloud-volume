// Writeback queue tests verify canceling mount uploads clears local staged state.
package mount

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

type syncStateCall struct {
	virtualPath string
	inSync      bool
}

type recordingSyncStateProjector struct {
	calls []syncStateCall
}

func (p *recordingSyncStateProjector) UpdateSyncState(virtualPath string, inSync bool) error {
	p.calls = append(p.calls, syncStateCall{
		virtualPath: cleanVirtualPath(virtualPath),
		inSync:      inSync,
	})
	return nil
}

func TestCancelQueuedTransferRemovesLocalCacheState(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	virtualPath := "archive/output.zip"
	localPath := filepath.Join(access.cacheRoot, "archive", "output.zip")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir local path: %v", err)
	}
	if err := os.WriteFile(localPath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write staged file: %v", err)
	}
	access.registerLocalWrite(virtualPath, localPath, 7)
	access.writeback.enqueue(virtualPath, localPath, 7)

	var taskID string
	for _, entry := range access.writeback.entries {
		taskID = entry.taskID
	}
	if taskID == "" {
		t.Fatal("expected queued writeback task")
	}

	if ok := access.writeback.cancelTask(taskID); !ok {
		t.Fatal("expected queued task cancel to succeed")
	}
	if _, ok := access.cache.localFile(virtualPath); ok {
		t.Fatal("expected local file marker removal after cancel")
	}
	if _, err := os.Stat(localPath); !os.IsNotExist(err) {
		t.Fatalf("expected staged file removal, got %v", err)
	}
}

func TestCancelRunningTransferRemovesLocalCacheState(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	virtualPath := "archive/output.zip"
	localPath := filepath.Join(access.cacheRoot, "archive", "output.zip")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir local path: %v", err)
	}
	if err := os.WriteFile(localPath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write staged file: %v", err)
	}
	access.registerLocalWrite(virtualPath, localPath, 7)
	access.writeback.running["task-running"] = &pendingWriteback{
		taskID:      "task-running",
		virtualPath: virtualPath,
		localPath:   localPath,
		size:        7,
	}

	if ok := access.writeback.cancelTask("task-running"); !ok {
		t.Fatal("expected running task cancel to succeed")
	}
	if _, ok := access.cache.localFile(virtualPath); ok {
		t.Fatal("expected local file marker removal after running cancel")
	}
	if _, err := os.Stat(localPath); !os.IsNotExist(err) {
		t.Fatalf("expected staged file removal, got %v", err)
	}
}

func TestHasPendingAtOrBelowIncludesRunningWriteback(t *testing.T) {
	access := newTestBucketAccess(t)
	access.writeback.running["task-running"] = &pendingWriteback{
		taskID:      "task-running",
		virtualPath: "docs/report.txt",
	}
	if !access.writeback.hasPendingAtOrBelow("docs/report.txt", false) {
		t.Fatal("expected running file writeback to block remote replacement")
	}
	if !access.writeback.hasPendingAtOrBelow("docs", true) {
		t.Fatal("expected running descendant writeback to block remote directory removal")
	}
}

func TestEnqueueProjectsNotInSyncState(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	projector := &recordingSyncStateProjector{}
	access.syncState = projector

	access.writeback.enqueue(
		"archive/output.zip",
		filepath.Join(access.cacheRoot, "archive", "output.zip"),
		7,
	)

	if len(projector.calls) != 1 {
		t.Fatalf("expected 1 sync-state call, got %d", len(projector.calls))
	}
	if projector.calls[0].virtualPath != "archive/output.zip" ||
		projector.calls[0].inSync {
		t.Fatalf("unexpected sync-state call: %+v", projector.calls[0])
	}
}

func TestRenameQueuedTransferProjectsNewPathNotInSync(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	projector := &recordingSyncStateProjector{}
	access.syncState = projector

	access.writeback.enqueue(
		"archive/output.zip",
		filepath.Join(access.cacheRoot, "archive", "output.zip"),
		7,
	)
	projector.calls = nil

	if ok, err := access.writeback.rename("archive/output.zip", "archive/final.zip", false); err != nil || !ok {
		t.Fatal("expected queued writeback rename to succeed")
	}
	if len(projector.calls) != 1 {
		t.Fatalf("expected 1 sync-state call after rename, got %d", len(projector.calls))
	}
	if projector.calls[0].virtualPath != "archive/final.zip" ||
		projector.calls[0].inSync {
		t.Fatalf("unexpected sync-state call after rename: %+v", projector.calls[0])
	}
}

func TestEnqueueSupersedesRunningTransferForSamePath(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	localPath := filepath.Join(access.cacheRoot, "archive", "output.zip")
	access.writeback.running["task-running"] = &pendingWriteback{
		taskID:      "task-running",
		virtualPath: "archive/output.zip",
		localPath:   localPath,
		size:        7,
	}

	access.writeback.enqueue("archive/output.zip", localPath, 9)

	running := access.writeback.running["task-running"]
	if running == nil || !running.discard {
		t.Fatalf("expected running task to be marked discard, got %+v", running)
	}
	queued := access.writeback.entries["archive/output.zip"]
	if queued == nil {
		t.Fatal("expected replacement queued entry")
	}
	if queued.size != 9 {
		t.Fatalf("expected replacement size 9, got %d", queued.size)
	}
}

func TestWritebackQueueUsesConfiguredConcurrency(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	_ = access.writeback.shutdown()
	access.config.WindowsWritebackConcurrency = 2
	writeback, err := newWritebackQueue(access)
	if err != nil {
		t.Fatalf("newWritebackQueue: %v", err)
	}
	access.writeback = writeback
	defer func() {
		_ = access.writeback.shutdown()
	}()

	if got := access.writeback.pool.Cap(); got != 2 {
		t.Fatalf("expected writeback pool capacity 2, got %d", got)
	}
}

func TestWritebackQueueUsesConfiguredQuietSeconds(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	access.config.WritebackQuietSeconds = 3
	access.writeback.setQuietPeriod(access.config)
	localPath := filepath.Join(access.cacheRoot, "archive", "output.zip")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir local path: %v", err)
	}
	if err := os.WriteFile(localPath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write staged file: %v", err)
	}

	startedAt := time.Now()
	access.writeback.enqueue("archive/output.zip", localPath, 7)
	entry := access.writeback.entries["archive/output.zip"]
	if entry == nil {
		t.Fatal("expected queued writeback entry")
	}
	delay := entry.dueAt.Sub(startedAt)
	if delay < 2500*time.Millisecond || delay > 4*time.Second {
		t.Fatalf("expected due time near 3s, got %v", delay)
	}
}

func TestWritebackQueueDefaultsQuietSecondsToTen(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	if got := access.writeback.quietPeriod(); got != 10*time.Second {
		t.Fatalf("expected default quiet period 10s, got %v", got)
	}
}

func TestWritebackQueueRestoresPersistedEntries(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	virtualPath := "archive/output.zip"
	localPath := filepath.Join(access.cacheRoot, "archive", "output.zip")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir local path: %v", err)
	}
	if err := os.WriteFile(localPath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write staged file: %v", err)
	}

	access.writeback.enqueue(virtualPath, localPath, 7)
	entry := access.writeback.entries[virtualPath]
	if entry == nil {
		t.Fatal("expected queued writeback entry before restart")
	}
	originalTaskID := entry.taskID

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

	reloaded := access.writeback.entries[virtualPath]
	if reloaded == nil {
		t.Fatal("expected persisted writeback entry after restart")
	}
	if reloaded.taskID != originalTaskID {
		t.Fatalf("expected task %q after restore, got %q", originalTaskID, reloaded.taskID)
	}
}

func TestFlushNowReschedulesModifiedRunningEntry(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	virtualPath := "archive/output.zip"
	localPath := filepath.Join(access.cacheRoot, "archive", "output.zip")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir local path: %v", err)
	}
	if err := os.WriteFile(localPath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write staged file: %v", err)
	}
	info, err := os.Stat(localPath)
	if err != nil {
		t.Fatalf("stat staged file: %v", err)
	}
	entry := &pendingWriteback{
		taskID:          "task-running",
		virtualPath:     virtualPath,
		localPath:       localPath,
		size:            info.Size(),
		modTimeUnixNano: info.ModTime().UnixNano() - 1,
	}
	access.writeback.running[entry.taskID] = entry

	if err := access.writeback.flushNow(entry); err != nil {
		t.Fatalf("flushNow should reschedule modified entry before upload, got %v", err)
	}

	refreshed := access.writeback.entries[virtualPath]
	if refreshed == nil {
		t.Fatal("expected modified entry to be rescheduled")
	}
	if refreshed.modTimeUnixNano != info.ModTime().UnixNano() {
		t.Fatalf("expected refreshed modtime %d, got %d", info.ModTime().UnixNano(), refreshed.modTimeUnixNano)
	}
	if refreshed.dueAt.Before(time.Now()) {
		t.Fatalf("expected refreshed entry due in the future, got %v", refreshed.dueAt)
	}
}

func TestDrainFlushesQueuedEntriesBeforeShutdown(t *testing.T) {
	access := newTestBucketAccess(t)
	virtualPath := "archive/output.zip"
	localPath := filepath.Join(access.cacheRoot, "archive", "output.zip")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir local path: %v", err)
	}
	payload := []byte("payload")
	if err := os.WriteFile(localPath, payload, 0o644); err != nil {
		t.Fatalf("write staged file: %v", err)
	}

	t.Setenv("AWS_EC2_METADATA_DISABLED", "true")
	access.config.Endpoint = "http://127.0.0.1:1"
	access.config.AccessKeyID = "ak"
	access.config.SecretAccessKey = "sk"
	access.transferTimeout = 100 * time.Millisecond
	access.backend = storageops.ForConfig(access.config)

	access.writeback.enqueue(virtualPath, localPath, int64(len(payload)))
	if err := access.writeback.drain(); err == nil {
		t.Fatal("expected drain upload failure against invalid endpoint")
	}
	if entry := access.writeback.entries[virtualPath]; entry == nil {
		t.Fatal("expected failed drain to keep queued entry for retry")
	}
	if len(access.writeback.running) != 0 {
		t.Fatalf("expected no running entries after drain failure, got %d", len(access.writeback.running))
	}
}

func TestDrainWaitsForRunningEntries(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	entry := &pendingWriteback{
		taskID:      "task-running",
		virtualPath: "archive/output.zip",
		localPath:   filepath.Join(access.cacheRoot, "archive", "output.zip"),
	}
	access.writeback.mu.Lock()
	access.writeback.running[entry.taskID] = entry
	access.writeback.mu.Unlock()

	done := make(chan error, 1)
	go func() {
		done <- access.writeback.drain()
	}()

	select {
	case err := <-done:
		t.Fatalf("drain returned before running task completed: %v", err)
	case <-time.After(150 * time.Millisecond):
	}

	access.writeback.mu.Lock()
	delete(access.writeback.running, entry.taskID)
	access.writeback.mu.Unlock()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("drain returned error after running task cleared: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("drain did not finish after running task cleared")
	}
}

func TestDrainContextReturnsDeadlineWithoutDiscardingPendingWork(t *testing.T) {
	access := newTestBucketAccess(t)
	entry := &pendingWriteback{
		taskID:      "task-running",
		virtualPath: "archive/output.zip",
		localPath:   filepath.Join(access.cacheRoot, "archive", "output.zip"),
	}
	access.writeback.mu.Lock()
	access.writeback.running[entry.taskID] = entry
	access.writeback.mu.Unlock()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	if err := access.writeback.drainContext(ctx); err != context.DeadlineExceeded {
		t.Fatalf("drain context error = %v, want deadline exceeded", err)
	}
	access.writeback.mu.Lock()
	_, stillRunning := access.writeback.running[entry.taskID]
	access.writeback.mu.Unlock()
	if !stillRunning {
		t.Fatal("deadline discarded the running writeback entry")
	}
}

func TestDrainContextRestoresEveryUnsentEntryAfterQueueBackpressure(t *testing.T) {
	first := &pendingWriteback{taskID: "first", virtualPath: "first.txt"}
	second := &pendingWriteback{taskID: "second", virtualPath: "second.txt"}
	queue := &writebackQueue{
		entries: map[string]*pendingWriteback{
			"first.txt":  first,
			"second.txt": second,
		},
		running: map[string]*pendingWriteback{},
		queue:   make(chan *pendingWriteback, 1),
		stop:    make(chan struct{}),
	}
	// No dispatcher drains this sentinel, so drainContext must hit its deadline
	// while trying to enqueue the first ready entry.
	queue.queue <- &pendingWriteback{taskID: "sentinel", virtualPath: "sentinel"}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	if err := queue.drainContext(ctx); err != context.DeadlineExceeded {
		t.Fatalf("drain context error = %v, want deadline exceeded", err)
	}
	// Releasing the saturated dispatcher must let the canceled drain's due work
	// enter the ordinary timer path again without another explicit drain call.
	<-queue.queue
	seen := map[string]bool{}
	deadline := time.NewTimer(time.Second)
	defer deadline.Stop()
	for len(seen) < 2 {
		select {
		case entry := <-queue.queue:
			if entry != nil {
				seen[entry.virtualPath] = true
			}
		case <-deadline.C:
			t.Fatalf("canceled drain did not resume entries: %+v", seen)
		}
	}
	if !seen["first.txt"] || !seen["second.txt"] {
		t.Fatalf("canceled drain resumed the wrong entries: %+v", seen)
	}
}

func TestRenameDrainsPendingEntryBeforeRemoteMove(t *testing.T) {
	access := newTestBucketAccess(t)
	oldPath := createTempFile(t, access.cacheRoot, "old.txt", "payload")
	access.stageLocalWrite("old.txt", oldPath, int64(len("payload")))

	if err := access.renamePath(context.Background(), "old.txt", "new.txt", false); err != nil {
		t.Fatalf("rename local-only pending write: %v", err)
	}
	if access.writeback.entries["old.txt"] != nil || access.writeback.entries["new.txt"] != nil {
		t.Fatalf("rename left a pending upload after draining source: %+v", access.writeback.entries)
	}
	if _, ok := access.cache.localFile("old.txt"); ok {
		t.Fatal("drained source retained its local write marker")
	}
	if _, ok := access.cache.localFile("new.txt"); ok {
		t.Fatal("rename recreated a local write marker after source drain")
	}
	if _, err := os.Stat(oldPath); err != nil {
		t.Fatalf("drained cache bytes were unexpectedly removed: %v", err)
	}
}
