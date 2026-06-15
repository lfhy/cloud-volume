//go:build windows && cgo

// Windows Cloud Files watcher tests pin placeholder ignore behavior for nested writes.
package mount

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/fsnotify/fsnotify"
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

func TestTouchActiveHarvestAncestorsRefreshesParentScans(t *testing.T) {
	t.Parallel()

	root := filepath.Join(`C:\sync-root`, `bucket`)
	childDir := filepath.Join(root, `backup`, `flow2api`)
	childFile := filepath.Join(childDir, `main.py`)
	old := time.Now().Add(-time.Minute)

	watcher := &windowsSyncWatcher{
		root: root,
		activeHarvests: map[string]time.Time{
			root:     old,
			childDir: old,
		},
	}

	watcher.touchActiveHarvestAncestors(childFile)

	if !watcher.activeHarvests[root].After(old) {
		t.Fatal("expected descendant activity to refresh root harvest")
	}
	if !watcher.activeHarvests[childDir].After(old) {
		t.Fatal("expected descendant activity to refresh child harvest")
	}
}

func TestHandleCreateRefreshesAncestorHarvestsForChildDirectory(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	parentDir := filepath.Join(root, "backup")
	childDir := filepath.Join(parentDir, "flow2api")
	if err := os.MkdirAll(childDir, 0o755); err != nil {
		t.Fatalf("mkdir child dir: %v", err)
	}

	rawWatcher, err := fsnotify.NewWatcher()
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	defer rawWatcher.Close()

	old := time.Now().Add(-time.Minute)
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
		activeHarvests: map[string]time.Time{
			parentDir: old,
		},
	}

	watcher.handleCreate(childDir, "backup/flow2api")

	if !watcher.activeHarvests[parentDir].After(old) {
		t.Fatal("expected child directory creation to refresh parent harvest")
	}
}

func TestPlaceholderDirectoryWatchesEnableNestedCopies(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	parentDir := filepath.Join(root, "bakcuptest", "test")
	childDir := filepath.Join(parentDir, "test2")
	copyDir := filepath.Join(childDir, "flow2api")
	copyFile := filepath.Join(copyDir, "main.py")
	if err := os.MkdirAll(parentDir, 0o755); err != nil {
		t.Fatalf("mkdir parent tree: %v", err)
	}

	watcher, err := newWindowsSyncWatcher(root, access)
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	if err := watcher.Start(); err != nil {
		t.Fatalf("start watcher: %v", err)
	}
	defer func() {
		if err := watcher.Close(); err != nil {
			t.Fatalf("close watcher: %v", err)
		}
	}()

	placeholders := []cloudPlaceholderInfo{{
		RelativePath: "test2",
		IsDirectory:  true,
	}}
	watcher.RememberPlaceholders(parentDir, placeholders)
	if err := os.MkdirAll(childDir, 0o755); err != nil {
		t.Fatalf("mkdir placeholder dir: %v", err)
	}
	watcher.watchPlaceholderDirectories(parentDir, placeholders)
	if err := os.MkdirAll(copyDir, 0o755); err != nil {
		t.Fatalf("mkdir copied subtree: %v", err)
	}
	if err := os.WriteFile(copyFile, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write copied file: %v", err)
	}

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if _, ok := access.cache.localFile("bakcuptest/test/test2/flow2api/main.py"); ok &&
			access.writeback.hasPendingAtOrBelow("bakcuptest/test/test2/flow2api", true) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}

	t.Fatal("expected placeholder directory watch to capture nested copied files")
}

func TestFetchPlaceholderCallbackRearmsOpenedDirectoryWatch(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	parentDir := filepath.Join(root, "bakcuptest", "test")
	childDir := filepath.Join(parentDir, "test2")
	copyDir := filepath.Join(childDir, "flow2api")
	copyFile := filepath.Join(copyDir, "main.py")
	if err := os.MkdirAll(parentDir, 0o755); err != nil {
		t.Fatalf("mkdir parent tree: %v", err)
	}

	watcher, err := newWindowsSyncWatcher(root, access)
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	if err := watcher.Start(); err != nil {
		t.Fatalf("start watcher: %v", err)
	}
	defer func() {
		if err := watcher.Close(); err != nil {
			t.Fatalf("close watcher: %v", err)
		}
	}()

	// Placeholder materialization can create the child directory without
	// leaving a usable watch behind when the CREATE event is ignored.
	watcher.state.ignore(childDir, time.Minute, false)
	if err := os.MkdirAll(childDir, 0o755); err != nil {
		t.Fatalf("mkdir child dir: %v", err)
	}
	time.Sleep(200 * time.Millisecond)

	// Opening the child directory should re-arm the watch for that directory
	// before any subsequent local copy starts writing beneath it.
	watcher.watchPlaceholderDirectories(childDir, nil)
	if err := os.MkdirAll(copyDir, 0o755); err != nil {
		t.Fatalf("mkdir copied subtree: %v", err)
	}
	if err := os.WriteFile(copyFile, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write copied file: %v", err)
	}

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if _, ok := access.cache.localFile("bakcuptest/test/test2/flow2api/main.py"); ok &&
			access.writeback.hasPendingAtOrBelow("bakcuptest/test/test2/flow2api", true) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}

	t.Fatal("expected opening placeholder directory to restore nested copy watches")
}

func TestWindowsSyncWatcherCloseReturnsDuringHarvest(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	parentDir := filepath.Join(root, "backup")
	childDir := filepath.Join(parentDir, "flow2api")
	childFile := filepath.Join(childDir, "main.py")
	if err := os.MkdirAll(childDir, 0o755); err != nil {
		t.Fatalf("mkdir tree: %v", err)
	}
	if err := os.WriteFile(childFile, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write child file: %v", err)
	}

	watcher, err := newWindowsSyncWatcher(root, access)
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	if err := watcher.Start(); err != nil {
		t.Fatalf("start watcher: %v", err)
	}

	watcher.harvestDirectoryTree(parentDir)

	done := make(chan error, 1)
	go func() {
		done <- watcher.Close()
	}()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("close watcher: %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("expected watcher close to finish while harvest goroutines are active")
	}
}

func TestWindowsSyncWatcherRemoveCancelsPendingUpload(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	filePath := filepath.Join(root, "docs", "draft.txt")
	if err := os.MkdirAll(filepath.Dir(filePath), 0o755); err != nil {
		t.Fatalf("mkdir tree: %v", err)
	}
	if err := os.WriteFile(filePath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write file: %v", err)
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

	watcher.handleCreate(filePath, "docs/draft.txt")
	if !access.writeback.hasPendingAtOrBelow("docs/draft.txt", false) {
		t.Fatal("expected pending upload after create")
	}

	if err := os.Remove(filePath); err != nil {
		t.Fatalf("remove file: %v", err)
	}
	watcher.handleEvent(fsnotify.Event{Name: filePath, Op: fsnotify.Remove})

	if access.writeback.hasPendingAtOrBelow("docs/draft.txt", false) {
		t.Fatal("expected remove event to cancel pending upload")
	}
}

func TestWindowsLocalOnlyPathTreatsOfficeTempFilesAsEphemeral(t *testing.T) {
	t.Parallel()

	cases := []string{
		"docs/~$report.docx",
		"docs/~wrf1234.tmp",
		"docs/~wrl4321.tmp",
		"docs/~dfa12b.tmp",
	}
	for _, virtualPath := range cases {
		if !isWindowsLocalOnlyPath(virtualPath) {
			t.Fatalf("expected %q to stay local-only", virtualPath)
		}
	}
	if isWindowsLocalOnlyPath("docs/report.docx") {
		t.Fatal("expected normal document to stay syncable")
	}
}
