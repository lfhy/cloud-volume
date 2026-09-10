//go:build windows && cgo

// Windows Cloud Files watcher tests pin placeholder ignore behavior for nested writes.
package mount

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/fsnotify/fsnotify"

	"remote-storage/go/mount/metadata"
)

func TestWindowsPathStatePlaceholderIgnoreDoesNotHideChildren(t *testing.T) {
	t.Parallel()

	state := &windowsPathState{
		ignored:      map[string]windowsIgnoredPath{},
		hydrating:    map[string]bool{},
		kinds:        map[string]bool{},
		files:        map[string]windowsObservedFile{},
		placeholders: map[string]bool{},
	}

	placeholderDir := filepath.Join(`C:\sync-root`, `docs`)
	childFile := filepath.Join(placeholderDir, `draft.txt`)
	state.ignore(placeholderDir, time.Minute, false)

	if !state.shouldIgnore(placeholderDir) {
		t.Fatal("expected placeholder directory event to be ignored")
	}
	if state.shouldIgnore(childFile) {
		t.Fatal("expected child writes below placeholder directory to stay visible")
	}
}

func TestWindowsPathStateHydratingStillHidesChildren(t *testing.T) {
	t.Parallel()

	state := &windowsPathState{
		ignored:      map[string]windowsIgnoredPath{},
		hydrating:    map[string]bool{},
		kinds:        map[string]bool{},
		files:        map[string]windowsObservedFile{},
		placeholders: map[string]bool{},
	}

	hydratingDir := filepath.Join(`C:\sync-root`, `docs`)
	childFile := filepath.Join(hydratingDir, `draft.txt`)
	state.markHydrating(hydratingDir)

	if !state.shouldIgnore(childFile) {
		t.Fatal("expected hydrating subtree events to be ignored")
	}
}

func TestMarkRenameSourceLeavesRenamedChildrenWritable(t *testing.T) {
	t.Parallel()

	oldDir := filepath.Join(`C:\sync-root`, `old`)
	newDir := filepath.Join(`C:\sync-root`, `new`)
	oldChild := filepath.Join(oldDir, `draft.txt`)
	newChild := filepath.Join(newDir, `draft.txt`)
	watcher := &windowsSyncWatcher{state: &windowsPathState{
		ignored:      map[string]windowsIgnoredPath{},
		hydrating:    map[string]bool{},
		kinds:        map[string]bool{oldDir: true, oldChild: false},
		files:        map[string]windowsObservedFile{},
		placeholders: map[string]bool{},
	}}

	watcher.MarkRenameSource(oldDir, true)
	watcher.Rebase(oldDir, newDir, true)

	if !watcher.state.shouldIgnore(oldChild) {
		t.Fatal("expected stale source events to be suppressed briefly")
	}
	if watcher.state.shouldIgnore(newChild) {
		t.Fatal("expected renamed directory children to remain writable")
	}
	if len(watcher.state.hydrating) != 0 {
		t.Fatalf("rename must not leave permanent hydration markers: %v", watcher.state.hydrating)
	}
}

func TestWindowsWatcherPairsNormalFileRenameIntoMetadata(t *testing.T) {
	// A newly created normal NTFS file can produce only fsnotify Rename(old)
	// plus Create(new), so verify that it still becomes one metadata rename.
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	manager, handle := attachMetadataWriteService(t, access, backend)
	root := t.TempDir()
	oldPath := filepath.Join(root, "alpha.txt")
	newPath := filepath.Join(root, "renamed.txt")
	if err := os.WriteFile(oldPath, []byte("pending payload"), 0o644); err != nil {
		t.Fatalf("write source: %v", err)
	}
	watcher := &windowsSyncWatcher{
		root:   root,
		access: access,
		state: &windowsPathState{
			ignored:      map[string]windowsIgnoredPath{},
			hydrating:    map[string]bool{},
			kinds:        map[string]bool{},
			files:        map[string]windowsObservedFile{},
			placeholders: map[string]bool{},
		},
	}

	oldInfo, err := os.Stat(oldPath)
	if err != nil {
		t.Fatalf("stat source: %v", err)
	}
	watcher.state.remember(oldPath, false)
	if !watcher.state.shouldQueueFile(oldPath, oldInfo.Size(), oldInfo.ModTime(), false) {
		t.Fatal("expected initial normal file to enter the watcher state")
	}
	if err := access.stageLocalWrite("alpha.txt", oldPath, oldInfo.Size()); err != nil {
		t.Fatalf("stage source: %v", err)
	}
	if err := os.Rename(oldPath, newPath); err != nil {
		t.Fatalf("rename normal local file: %v", err)
	}
	watcher.handleRenameSource(oldPath, "alpha.txt")
	info, err := os.Stat(newPath)
	if err != nil {
		t.Fatalf("stat renamed file: %v", err)
	}
	if !watcher.completePendingFileRename(newPath, "renamed.txt", info) {
		t.Fatal("expected Rename(old)+Create(new) pair to become a metadata rename")
	}
	beforeGroups, err := manager.ListTaskGroups()
	if err != nil {
		t.Fatalf("list task groups before late callback: %v", err)
	}
	beforeTasks, beforeEvents := countMetadataTaskProjection(beforeGroups)
	session := &mountSession{mountPath: root, access: access}
	(&windowsCloudFilesBackend{}).handleRename(session, watcher)(oldPath, newPath)
	if session.lastError != "" {
		t.Fatalf("late CFAPI completion reported an error: %q", session.lastError)
	}
	afterGroups, err := manager.ListTaskGroups()
	if err != nil {
		t.Fatalf("list task groups after late callback: %v", err)
	}
	afterTasks, afterEvents := countMetadataTaskProjection(afterGroups)
	if beforeTasks != afterTasks || beforeEvents != afterEvents {
		t.Fatalf(
			"late callback changed task projection: before=%d/%d after=%d/%d",
			beforeTasks,
			beforeEvents,
			afterTasks,
			afterEvents,
		)
	}

	ctx := context.Background()
	if _, err := handle.Service.StatPath(ctx, "alpha.txt"); err == nil {
		t.Fatal("source remained in the Desired metadata view")
	}
	if _, err := handle.Service.StatPath(ctx, "renamed.txt"); err != nil {
		t.Fatalf("renamed target missing from Desired metadata view: %v", err)
	}
	if err := manager.DrainAll(ctx); err != nil {
		t.Fatalf("drain metadata worker: %v", err)
	}
	backend.mu.Lock()
	_, oldExists := backend.objects["alpha.txt"]
	_, newExists := backend.objects["renamed.txt"]
	backend.mu.Unlock()
	if oldExists || !newExists {
		t.Fatalf("remote rename convergence old=%t new=%t", oldExists, newExists)
	}
}

func countMetadataTaskProjection(groups []metadata.TaskGroup) (tasks, events int) {
	for _, group := range groups {
		tasks += len(group.Tasks)
		for _, task := range group.Tasks {
			events += len(task.Events)
		}
	}
	return tasks, events
}

func TestWindowsPathStateRejectsAmbiguousRenamePair(t *testing.T) {
	t.Parallel()

	first := filepath.Join(`C:\sync-root`, `first.txt`)
	second := filepath.Join(`C:\sync-root`, `second.txt`)
	target := filepath.Join(`C:\sync-root`, `renamed.txt`)
	observed := windowsObservedFile{size: 24, modTime: 42}
	state := &windowsPathState{
		kinds: map[string]bool{first: false, second: false},
		files: map[string]windowsObservedFile{first: observed, second: observed},
	}
	if !state.beginPendingFileRename(first) || !state.beginPendingFileRename(second) {
		t.Fatal("expected both staged sources to become pending rename candidates")
	}
	if oldPath, ok := state.claimPendingFileRename(target, observed.size, time.Unix(0, observed.modTime)); ok || oldPath != "" {
		t.Fatalf("ambiguous candidates paired as old=%q ok=%t", oldPath, ok)
	}
}

func TestWindowsPathStateProviderDeleteCoversDirectoryCallbacks(t *testing.T) {
	t.Parallel()

	state := &windowsPathState{
		ignored:         map[string]windowsIgnoredPath{},
		providerDeletes: map[string]windowsProviderDelete{},
	}
	directory := filepath.Join(`C:\sync-root`, `docs`)
	child := filepath.Join(directory, `draft.txt`)
	state.markProviderDelete(directory, true)

	if !state.isProviderDelete(directory) || !state.isProviderDelete(child) {
		t.Fatal("expected provider directory deletion to cover descendant callbacks")
	}
	if !state.shouldIgnore(child) {
		t.Fatal("expected provider directory deletion to suppress fsnotify descendants")
	}
	state.clearProviderDelete(directory)
	if state.isProviderDelete(directory) || state.shouldIgnore(child) {
		t.Fatal("expected clearing provider deletion to re-enable local events")
	}
}

func TestRemoveExternalPlaceholderDeletesLocalProjection(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	localPath := filepath.Join(root, "docs", "draft.txt")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir placeholder parent: %v", err)
	}
	if err := os.WriteFile(localPath, []byte("remote"), 0o644); err != nil {
		t.Fatalf("write placeholder: %v", err)
	}
	watcher := &windowsSyncWatcher{
		state: &windowsPathState{
			ignored:         map[string]windowsIgnoredPath{},
			providerDeletes: map[string]windowsProviderDelete{},
			kinds:           map[string]bool{localPath: false},
			files:           map[string]windowsObservedFile{},
			placeholders:    map[string]bool{localPath: true},
			hydrating:       map[string]bool{},
		},
	}
	session := &mountSession{mountPath: root}
	backend := &windowsCloudFilesBackend{}

	if err := backend.removeExternalPlaceholder(session, watcher, "docs/draft.txt", false); err != nil {
		t.Fatalf("remove external placeholder: %v", err)
	}
	if _, err := os.Lstat(localPath); !os.IsNotExist(err) {
		t.Fatalf("expected placeholder removed, stat error=%v", err)
	}
	if !watcher.IsProviderDelete(localPath) {
		t.Fatal("expected delete-completion callback to remain suppressed")
	}
}

func TestMarkHydratedIgnoresImmediateSystemWritebackEvent(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	filePath := filepath.Join(root, "docs", "draft.txt")
	if err := os.MkdirAll(filepath.Dir(filePath), 0o755); err != nil {
		t.Fatalf("mkdir tree: %v", err)
	}
	if err := os.WriteFile(filePath, []byte("remote"), 0o644); err != nil {
		t.Fatalf("write hydrated file: %v", err)
	}
	info, err := os.Stat(filePath)
	if err != nil {
		t.Fatalf("stat hydrated file: %v", err)
	}

	state := &windowsPathState{
		ignored:      map[string]windowsIgnoredPath{},
		hydrating:    map[string]bool{},
		kinds:        map[string]bool{},
		files:        map[string]windowsObservedFile{},
		placeholders: map[string]bool{},
	}
	state.markHydrating(filePath)
	state.markPlaceholder(filePath)

	state.markHydrated(filePath)

	if !state.shouldIgnore(filePath) {
		t.Fatal("expected hydrated file write event to be ignored briefly")
	}
	if state.shouldQueueFile(filePath, info.Size(), info.ModTime(), false) {
		t.Fatal("expected hydrated file metadata to be remembered without queueing upload")
	}
}

func TestIngestDirectoryTreeQueuesExistingNestedFiles(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	dirPath := filepath.Join(root, "parent", "nested")
	filePath := filepath.Join(dirPath, "draft.txt")
	if err := os.MkdirAll(dirPath, 0o755); err != nil {
		t.Fatalf("mkdir tree: %v", err)
	}
	if err := os.WriteFile(filePath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write nested file: %v", err)
	}

	rawWatcher, err := fsnotify.NewWatcher()
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	defer rawWatcher.Close()

	watcher := &windowsSyncWatcher{
		root:   root,
		access: access,
		raw:    rawWatcher,
		state: &windowsPathState{
			ignored:      map[string]windowsIgnoredPath{},
			hydrating:    map[string]bool{},
			kinds:        map[string]bool{},
			files:        map[string]windowsObservedFile{},
			placeholders: map[string]bool{},
		},
		done: make(chan struct{}),
	}

	if _, _, err := watcher.ingestDirectoryTree(filepath.Join(root, "parent")); err != nil {
		t.Fatalf("ingest directory tree: %v", err)
	}

	if _, ok := access.cache.cachedObject("parent/nested"); !ok {
		t.Fatal("expected nested directory to be staged locally")
	}
	if _, ok := access.cache.localFile("parent/nested/draft.txt"); !ok {
		t.Fatal("expected nested file to be registered for local-first upload")
	}
	if !access.writeback.hasPendingAtOrBelow("parent", true) {
		t.Fatal("expected delayed writeback entry for nested file")
	}
}

func TestDirectoryWriteTriggersHarvest(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	parentDir := filepath.Join(root, "parent")
	nestedDir := filepath.Join(parentDir, "nested")
	nestedFile := filepath.Join(nestedDir, "draft.txt")
	if err := os.MkdirAll(nestedDir, 0o755); err != nil {
		t.Fatalf("mkdir tree: %v", err)
	}
	if err := os.WriteFile(nestedFile, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write nested file: %v", err)
	}

	rawWatcher, err := fsnotify.NewWatcher()
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	defer rawWatcher.Close()

	watcher := &windowsSyncWatcher{
		root:   root,
		access: access,
		raw:    rawWatcher,
		state: &windowsPathState{
			ignored:      map[string]windowsIgnoredPath{},
			hydrating:    map[string]bool{},
			kinds:        map[string]bool{},
			files:        map[string]windowsObservedFile{},
			placeholders: map[string]bool{},
		},
		done:           make(chan struct{}),
		activeHarvests: map[string]time.Time{},
	}

	watcher.handleWrite(parentDir, "parent")

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if _, ok := access.cache.localFile("parent/nested/draft.txt"); ok &&
			access.writeback.hasPendingAtOrBelow("parent", true) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}

	t.Fatal("expected directory write to trigger recursive harvest and queue nested file")
}

func TestHarvestSkipsKnownPlaceholderFiles(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	parentDir := filepath.Join(root, "test")
	placeholderFile := filepath.Join(parentDir, "manifest.json")
	if err := os.MkdirAll(parentDir, 0o755); err != nil {
		t.Fatalf("mkdir tree: %v", err)
	}
	if err := os.WriteFile(placeholderFile, []byte("remote"), 0o644); err != nil {
		t.Fatalf("write placeholder file: %v", err)
	}

	rawWatcher, err := fsnotify.NewWatcher()
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	defer rawWatcher.Close()

	watcher := &windowsSyncWatcher{
		root:   root,
		access: access,
		raw:    rawWatcher,
		state: &windowsPathState{
			ignored:      map[string]windowsIgnoredPath{},
			hydrating:    map[string]bool{},
			kinds:        map[string]bool{},
			files:        map[string]windowsObservedFile{},
			placeholders: map[string]bool{},
		},
		done:           make(chan struct{}),
		activeHarvests: map[string]time.Time{},
	}
	watcher.state.markPlaceholder(placeholderFile)

	if _, queuedFiles, err := watcher.ingestDirectoryTree(parentDir); err != nil {
		t.Fatalf("ingest directory tree: %v", err)
	} else if queuedFiles != 0 {
		t.Fatalf("expected placeholder file to be skipped, queuedFiles=%d", queuedFiles)
	}
	if access.writeback.hasPendingAtOrBelow("test", true) {
		t.Fatal("expected no writeback tasks for known placeholder file")
	}
}

func TestDirectoryWriteClearsPlaceholderMarkersForDescendants(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	parentDir := filepath.Join(root, "flow2api")
	childDir := filepath.Join(parentDir, ".git")
	childFile := filepath.Join(childDir, "config")
	if err := os.MkdirAll(childDir, 0o755); err != nil {
		t.Fatalf("mkdir tree: %v", err)
	}
	if err := os.WriteFile(childFile, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write nested file: %v", err)
	}

	rawWatcher, err := fsnotify.NewWatcher()
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	defer rawWatcher.Close()

	watcher := &windowsSyncWatcher{
		root:   root,
		access: access,
		raw:    rawWatcher,
		state: &windowsPathState{
			ignored:      map[string]windowsIgnoredPath{},
			hydrating:    map[string]bool{},
			kinds:        map[string]bool{},
			files:        map[string]windowsObservedFile{},
			placeholders: map[string]bool{},
		},
		done:           make(chan struct{}),
		activeHarvests: map[string]time.Time{},
	}
	watcher.state.markPlaceholder(childFile)

	watcher.handleWrite(parentDir, "flow2api")

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if _, ok := access.cache.localFile("flow2api/.git/config"); ok &&
			access.writeback.hasPendingAtOrBelow("flow2api", true) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}

	t.Fatal("expected directory write to clear descendant placeholders and queue nested file")
}
