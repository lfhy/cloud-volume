// Directory sync tests verify that queued marker creates follow local directory renames.
package mount

import (
	"context"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestDirectoryCreateIsRebasedBeforeRename(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	backend.blockCreate = true
	access := newDirectorySyncTestAccess(t, backend)
	cleanupDirectoryTestBlock(t, backend.releaseCreate)

	access.dirSync.enqueue("worker-one")
	access.dirSync.enqueue("worker-two")
	waitForDirectoryCreateStarts(t, backend, 2)
	access.dirSync.enqueue("dispatcher-wait")
	waitForDirectoryEntryRunning(t, access.dirSync, "dispatcher-wait")
	access.dirSync.enqueue("New Folder")
	if err := access.enqueueRenamePath(
		"New Folder", "Reports", "", "", true,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}
	releaseDirectoryTestBlock(backend.releaseCreate)

	waitForDirectorySync(t, func() bool {
		return backend.hasDirectory("Reports")
	})
	if backend.hasDirectory("New Folder") {
		t.Fatalf("old directory marker remains: %v", backend.eventsSnapshot())
	}
	if len(backend.eventsSnapshot()) == 0 {
		t.Fatal("expected remote directory mutation events")
	}
	if backend.hasEventPrefix("create:New Folder") {
		t.Fatalf("queued create used the old path: %v", backend.eventsSnapshot())
	}
	if backend.hasEventPrefix("rename:New Folder:Reports") {
		t.Fatalf("missing queued source was sent to the strict backend: %v", backend.eventsSnapshot())
	}
}

func TestNestedDirectoryCreatesRebaseAsOneTree(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	backend.blockCreate = true
	access := newDirectorySyncTestAccess(t, backend)
	cleanupDirectoryTestBlock(t, backend.releaseCreate)

	access.dirSync.enqueue("worker-one")
	access.dirSync.enqueue("worker-two")
	waitForDirectoryCreateStarts(t, backend, 2)
	access.dirSync.enqueue("dispatcher-wait")
	waitForDirectoryEntryRunning(t, access.dirSync, "dispatcher-wait")
	access.dirSync.enqueue("New Folder")
	access.dirSync.enqueue("New Folder/sub")
	if err := access.enqueueRenamePath(
		"New Folder", "Reports", "", "", true,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}
	releaseDirectoryTestBlock(backend.releaseCreate)

	waitForDirectorySync(t, func() bool {
		return backend.hasDirectory("Reports") && backend.hasDirectory("Reports/sub")
	})
	if !backend.hasDirectory("Reports") || !backend.hasDirectory("Reports/sub") ||
		backend.hasEventPrefix("create:New Folder") {
		t.Fatalf("timed out waiting for directory sync: %v", backend.eventsSnapshot())
	}
	if backend.hasDirectory("New Folder") || backend.hasDirectory("New Folder/sub") {
		t.Fatalf("old directory tree remains: %v", backend.eventsSnapshot())
	}
	if backend.hasEventPrefix("create:New Folder") {
		t.Fatalf("queued tree used an old path: %v", backend.eventsSnapshot())
	}
	if backend.hasEventPrefix("rename:New Folder:Reports") {
		t.Fatalf("missing queued source was sent to the strict backend: %v", backend.eventsSnapshot())
	}
}

func TestLegacyRenameRebasesQueuedDirectoryMarker(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	backend.blockCreate = true
	access := newDirectorySyncTestAccess(t, backend)
	cleanupDirectoryTestBlock(t, backend.releaseCreate)

	access.dirSync.enqueue("worker-one")
	access.dirSync.enqueue("worker-two")
	waitForDirectoryCreateStarts(t, backend, 2)
	access.dirSync.enqueue("dispatcher-wait")
	waitForDirectoryEntryRunning(t, access.dirSync, "dispatcher-wait")
	access.dirSync.enqueue("New Folder")

	renameDone := make(chan error, 1)
	go func() {
		renameDone <- access.renamePath(
			context.Background(), "New Folder", "Reports", true,
		)
	}()
	waitForDirectorySync(t, func() bool {
		access.dirSync.mu.Lock()
		defer access.dirSync.mu.Unlock()
		_, rebased := access.dirSync.entries["Reports"]
		_, old := access.dirSync.entries["New Folder"]
		return rebased && !old
	})
	releaseDirectoryTestBlock(backend.releaseCreate)

	select {
	case err := <-renameDone:
		if err != nil {
			t.Fatalf("legacy rename: %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("legacy rename did not finish")
	}
	if !backend.hasDirectory("Reports") || backend.hasDirectory("New Folder") {
		t.Fatalf("unexpected marker state: %v", backend.eventsSnapshot())
	}
	if backend.hasEventPrefix("create:New Folder") ||
		backend.hasEventPrefix("rename:New Folder:Reports") {
		t.Fatalf("legacy rename used stale directory marker: %v", backend.eventsSnapshot())
	}
}

func TestDirectoryCreateFailureAppearsInMountStatus(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	backend.createFailures["Reports"] = 1
	access := newDirectorySyncTestAccess(t, backend)
	access.dirSync.enqueue("Reports")

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		status := (&mountSession{access: access}).status()
		if strings.Contains(status.LastError, "injected directory create failure") &&
			strings.Contains(status.LastError, "Reports") {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	status := (&mountSession{access: access}).status()
	if !strings.Contains(status.LastError, "[dir-sync]") ||
		!strings.Contains(status.LastError, "injected directory create failure") {
		t.Fatalf("directory failure missing from mount status: %q", status.LastError)
	}

	access.dirSync.enqueue("Reports")
	waitForDirectorySync(t, func() bool { return backend.hasDirectory("Reports") })
	if status := (&mountSession{access: access}).status(); strings.Contains(status.LastError, "[dir-sync]") {
		t.Fatalf("successful retry left stale directory failure: %q", status.LastError)
	}
}

func TestRebasedDirectoryCreateFailureEnsuresDestinationBeforeRenameCompletes(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	backend.blockCreate = true
	backend.createFailures["Reports"] = 1
	access := newDirectorySyncTestAccess(t, backend)
	cleanupDirectoryTestBlock(t, backend.releaseCreate)

	access.dirSync.enqueue("worker-one")
	access.dirSync.enqueue("worker-two")
	waitForDirectoryCreateStarts(t, backend, 2)
	access.dirSync.enqueue("dispatcher-wait")
	waitForDirectoryEntryRunning(t, access.dirSync, "dispatcher-wait")
	access.dirSync.enqueue("New Folder")
	if err := access.enqueueRenamePath(
		"New Folder", "Reports", "", "", true,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}
	releaseDirectoryTestBlock(backend.releaseCreate)

	waitForMutationCompletion(t, access, "mutation-", 5*time.Second)
	if !backend.hasDirectory("Reports") {
		t.Fatalf("rename completed without a destination marker: %v", backend.eventsSnapshot())
	}
	if backend.eventCount("create:Reports") < 2 {
		t.Fatalf("destination was not recreated after the rebased create failed: %v", backend.eventsSnapshot())
	}
	if backend.hasEventPrefix("rename:New Folder:Reports") {
		t.Fatalf("missing old source was sent to the strict backend: %v", backend.eventsSnapshot())
	}
}

func TestDirectoryQueueBackpressureDoesNotBlockRebase(t *testing.T) {
	queue := &dirSyncQueue{
		entries: make(map[string]*dirSyncEntry),
		queue:   make(chan *dirSyncEntry),
	}
	enqueueDone := make(chan struct{})
	go func() {
		queue.enqueue("overflow")
		close(enqueueDone)
	}()

	lockAvailable := false
	deadline := time.Now().Add(250 * time.Millisecond)
	for time.Now().Before(deadline) {
		if queue.mu.TryLock() {
			entryQueued := queue.entries["overflow"] != nil
			queue.mu.Unlock()
			if entryQueued {
				lockAvailable = true
				break
			}
		}
		runtime.Gosched()
	}
	go func() { <-queue.queue }()
	<-enqueueDone
	if !lockAvailable {
		t.Fatal("directory queue held its mutex while backpressured")
	}
}

func TestRunningDirectoryCollisionWaitsForExistingTarget(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	releaseOld := backend.blockPath("New Folder/sub")
	releaseTarget := backend.blockPath("Reports/sub")
	access := newDirectorySyncTestAccess(t, backend)
	cleanupDirectoryTestBlock(t, releaseOld)
	cleanupDirectoryTestBlock(t, releaseTarget)

	access.dirSync.enqueue("New Folder/sub")
	access.dirSync.enqueue("Reports/sub")
	waitForDirectoryCreateStarts(t, backend, 2)
	if err := access.enqueueRenamePath(
		"New Folder", "Reports", "", "", true,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}

	releaseDirectoryTestBlock(releaseOld)
	releaseDirectoryTestBlock(releaseTarget)
	select {
	case <-backend.renameStarted:
	case <-time.After(3 * time.Second):
		t.Fatal("rename did not start after both directory creates finished")
	}
	events := backend.eventsSnapshot()
	assertDirectoryEventBefore(
		t, events, "create-finished:New Folder/sub", "rename:New Folder:Reports",
	)
	assertDirectoryEventBefore(
		t, events, "create-finished:Reports/sub", "rename:New Folder:Reports",
	)
}

func TestRunningDirectoryCreateFinishesBeforeRename(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	backend.blockCreate = true
	access := newDirectorySyncTestAccess(t, backend)
	cleanupDirectoryTestBlock(t, backend.releaseCreate)

	access.dirSync.enqueue("New Folder")
	select {
	case <-backend.createStarted:
	case <-time.After(3 * time.Second):
		t.Fatal("directory create did not start")
	}
	if err := access.enqueueRenamePath(
		"New Folder", "Reports", "", "", true,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}

	releaseDirectoryTestBlock(backend.releaseCreate)
	select {
	case <-backend.renameStarted:
	case <-time.After(3 * time.Second):
		t.Fatal("rename did not start after the directory create finished")
	}
	if !backend.hasDirectory("Reports") || backend.hasDirectory("New Folder") {
		t.Fatalf("unexpected final remote state: %v", backend.eventsSnapshot())
	}
	assertDirectoryEventBefore(
		t,
		backend.eventsSnapshot(),
		"create-finished:New Folder",
		"rename:New Folder:Reports",
	)
}
