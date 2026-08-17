//go:build windows && cgo

// The sync-root watcher turns local Explorer edits into the existing bucket writeback flows.
package mount

import (
	"context"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

type windowsPathState struct {
	mu              sync.Mutex
	ignored         map[string]windowsIgnoredPath
	hydrating       map[string]bool
	kinds           map[string]bool
	files           map[string]windowsObservedFile
	placeholders    map[string]bool
	providerDeletes map[string]windowsProviderDelete
}

type windowsIgnoredPath struct {
	until             time.Time
	ignoreDescendants bool
}

type windowsObservedFile struct {
	size    int64
	modTime int64
}

type windowsSyncWatcher struct {
	root   string
	access *bucketAccess
	raw    *fsnotify.Watcher
	state  *windowsPathState
	done   chan struct{}
	wg     sync.WaitGroup

	rawMu        sync.Mutex
	rawClosed    bool
	watched      map[string]bool
	watchPending map[string]bool
	watchWanted  map[string]bool

	harvestMu      sync.Mutex
	activeHarvests map[string]time.Time
	closeOnce      sync.Once
}

func newWindowsSyncWatcher(root string, access *bucketAccess) (*windowsSyncWatcher, error) {
	rawWatcher, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}
	return &windowsSyncWatcher{
		root:   filepath.Clean(root),
		access: access,
		raw:    rawWatcher,
		state: &windowsPathState{
			ignored:         map[string]windowsIgnoredPath{},
			hydrating:       map[string]bool{},
			kinds:           map[string]bool{},
			files:           map[string]windowsObservedFile{},
			placeholders:    map[string]bool{},
			providerDeletes: map[string]windowsProviderDelete{},
		},
		done:           make(chan struct{}),
		watched:        map[string]bool{},
		watchPending:   map[string]bool{},
		watchWanted:    map[string]bool{},
		activeHarvests: map[string]time.Time{},
	}, nil
}

func (w *windowsSyncWatcher) Start() error {
	w.wg.Add(1)
	go w.run()
	if err := w.rescanDirectories(); err != nil {
		w.signalStop()
		_ = w.closeRaw()
		w.wg.Wait()
		return err
	}
	return nil
}

func (w *windowsSyncWatcher) Close() error {
	w.signalStop()
	closeErr := w.closeRaw()
	w.wg.Wait()
	return closeErr
}

func (w *windowsSyncWatcher) RememberPlaceholders(baseDir string, items []cloudPlaceholderInfo) {
	for _, item := range items {
		fullPath := filepath.Join(baseDir, filepath.FromSlash(item.RelativePath))
		w.state.remember(fullPath, item.IsDirectory)
		w.state.markPlaceholder(fullPath)
		// Ignore only the placeholder path itself so a freshly opened child
		// directory can still surface immediate user writes below it.
		w.state.ignore(fullPath, windowsCFEventIgnoreTTL, false)
	}
}

func (w *windowsSyncWatcher) MarkHydrating(localPath string) {
	w.state.markHydrating(localPath)
}

func (w *windowsSyncWatcher) MarkHydrated(localPath string) {
	w.state.markHydrated(localPath)
}

// MarkRenameSource suppresses stale old-path events while leaving the renamed tree writable.
func (w *windowsSyncWatcher) MarkRenameSource(localPath string, isDir bool) {
	w.state.ignore(localPath, windowsCFEventIgnoreTTL, isDir)
}

func (w *windowsSyncWatcher) IsDir(localPath string) bool {
	if info, err := os.Stat(localPath); err == nil {
		return info.IsDir()
	}
	return w.state.isDir(localPath)
}

func (w *windowsSyncWatcher) Forget(localPath string) {
	w.state.forget(localPath)
	w.removeWatchTree(localPath)
}

func (w *windowsSyncWatcher) Rebase(oldPath, newPath string, isDir bool) {
	w.state.rebase(oldPath, newPath, isDir)
}

func (w *windowsSyncWatcher) run() {
	defer w.wg.Done()
	for {
		select {
		case <-w.done:
			return
		case event, ok := <-w.raw.Events:
			if !ok {
				return
			}
			w.handleEvent(event)
		case err, ok := <-w.raw.Errors:
			if !ok {
				return
			}
			log.Printf("[mount/cloud-files] watcher error: %v", err)
		}
	}
}

func (w *windowsSyncWatcher) rescanDirectories() error {
	return filepath.WalkDir(w.root, func(current string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return nil
		}
		if !entry.IsDir() {
			return nil
		}
		w.state.remember(current, true)
		w.addWatch(current)
		return nil
	})
}

func (w *windowsSyncWatcher) handleEvent(event fsnotify.Event) {
	localPath := filepath.Clean(event.Name)
	if isResumableUploadStatePath(localPath) {
		log.Printf("[mount/cloud-files] watcher-ignore-state path=%q", localPath)
		return
	}
	if w.state.shouldIgnore(localPath) {
		log.Printf("[mount/cloud-files] watcher-ignore event=%s path=%q", event.Op.String(), localPath)
		return
	}
	virtualPath := cloudFilesLocalPathToVirtual(w.root, localPath)
	if isWindowsLocalOnlyPath(virtualPath) {
		log.Printf("[mount/cloud-files] watcher-local-only event=%s path=%q", event.Op.String(), localPath)
		return
	}
	log.Printf(
		"[mount/cloud-files] watcher-event event=%s path=%q virtual=%q",
		event.Op.String(),
		localPath,
		virtualPath,
	)

	if event.Has(fsnotify.Create) {
		w.handleCreate(localPath, virtualPath)
	}
	if event.Has(fsnotify.Write) {
		w.handleWrite(localPath, virtualPath)
	}
	if event.Has(fsnotify.Remove) || event.Has(fsnotify.Rename) {
		w.cancelPendingUpload(localPath, virtualPath)
		w.Forget(localPath)
	}
}

func (w *windowsSyncWatcher) handleCreate(localPath, virtualPath string) {
	w.touchActiveHarvestAncestors(localPath)
	info, err := os.Stat(localPath)
	if err == nil && info.IsDir() {
		w.state.remember(localPath, true)
		w.state.clearPlaceholdersUnder(localPath)
		w.addWatch(localPath)
		if err := w.access.createDirectory(context.Background(), virtualPath); err != nil {
			log.Printf("[mount/cloud-files] create directory %q: %v", virtualPath, err)
		}
		w.harvestDirectoryTree(filepath.Dir(localPath))
		w.harvestDirectoryTree(localPath)
		return
	}
	if err != nil {
		w.harvestDirectoryTree(filepath.Dir(localPath))
		return
	}
	w.state.remember(localPath, false)
	w.scheduleUpload(localPath, virtualPath, false)
	w.harvestDirectoryTree(filepath.Dir(localPath))
}

func (w *windowsSyncWatcher) handleWrite(localPath, virtualPath string) {
	w.touchActiveHarvestAncestors(localPath)
	if w.IsDir(localPath) {
		w.state.clearPlaceholdersUnder(localPath)
		w.harvestDirectoryTree(localPath)
		return
	}
	w.state.remember(localPath, false)
	w.scheduleUpload(localPath, virtualPath, false)
}

func (w *windowsSyncWatcher) scheduleUpload(
	localPath,
	virtualPath string,
	fromHarvest bool,
) bool {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" || strings.HasSuffix(clean, "/") {
		return false
	}
	info, err := os.Stat(localPath)
	if err != nil || info.IsDir() {
		return false
	}
	if !w.state.shouldQueueFile(localPath, info.Size(), info.ModTime(), fromHarvest) {
		return false
	}
	log.Printf(
		"[mount/cloud-files] queue-upload virtual=%q local=%q size=%d",
		clean,
		localPath,
		info.Size(),
	)
	if err := w.access.stageLocalWrite(clean, localPath, info.Size()); err != nil {
		log.Printf("[mount/cloud-files] stage metadata write %q: %v", clean, err)
		return false
	}
	return true
}

func (w *windowsSyncWatcher) cancelPendingUpload(localPath, virtualPath string) {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return
	}
	isDir := w.IsDir(localPath) || strings.HasSuffix(clean, "/")
	if isDir {
		w.access.writeback.cancelAtOrBelow(clean, true)
		return
	}
	w.access.writeback.cancel(clean)
}

func (w *windowsSyncWatcher) harvestDirectoryTree(localPath string) {
	if w.shouldStop() {
		return
	}
	root := filepath.Clean(localPath)
	now := time.Now()
	w.harvestMu.Lock()
	if w.activeHarvests == nil {
		w.activeHarvests = map[string]time.Time{}
	}
	if _, ok := w.activeHarvests[root]; ok {
		w.activeHarvests[root] = now
		w.harvestMu.Unlock()
		return
	}
	w.activeHarvests[root] = now
	w.harvestMu.Unlock()

	w.wg.Add(1)
	go func(root string) {
		defer w.wg.Done()
		log.Printf("[mount/cloud-files] harvest-start path=%q", root)
		defer func() {
			w.harvestMu.Lock()
			delete(w.activeHarvests, root)
			w.harvestMu.Unlock()
			log.Printf("[mount/cloud-files] harvest-stop path=%q", root)
		}()

		// Large Explorer directory copies can keep materializing files for
		// several seconds after the parent directory CREATE event arrives.
		ticker := time.NewTicker(windowsCFDirectoryHarvestInterval)
		defer ticker.Stop()

		for {
			if w.shouldStop() {
				return
			}
			directoryCount, queuedFileCount, err := w.ingestDirectoryTree(root)
			if err != nil {
				log.Printf("[mount/cloud-files] harvest-directory path=%q error=%v", root, err)
			} else if queuedFileCount > 0 {
				log.Printf(
					"[mount/cloud-files] harvest-scan path=%q directories=%d queued_files=%d",
					root,
					directoryCount,
					queuedFileCount,
				)
			}
			select {
			case <-w.done:
				return
			case <-ticker.C:
				w.harvestMu.Lock()
				lastActivity, ok := w.activeHarvests[root]
				w.harvestMu.Unlock()
				if !ok || time.Since(lastActivity) >= windowsCFDirectoryHarvestWindow {
					return
				}
			}
		}
	}(root)
}

func (w *windowsSyncWatcher) ingestDirectoryTree(localRoot string) (int, int, error) {
	root := filepath.Clean(localRoot)
	directoryCount := 0
	queuedFileCount := 0
	err := filepath.WalkDir(root, func(current string, entry os.DirEntry, walkErr error) error {
		if w.shouldStop() {
			return fs.SkipAll
		}
		if walkErr != nil {
			return nil
		}
		if current == root {
			return nil
		}

		virtualPath := cloudFilesLocalPathToVirtual(w.root, current)
		if virtualPath == "" || isResumableUploadStatePath(current) {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if isWindowsLocalOnlyPath(virtualPath) {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}

		w.state.remember(current, entry.IsDir())
		w.touchActiveHarvestAncestors(current)
		if entry.IsDir() {
			w.addWatch(current)
			directoryCount++
			if err := w.access.createDirectory(context.Background(), virtualPath); err != nil {
				log.Printf("[mount/cloud-files] create directory %q: %v", virtualPath, err)
			}
			return nil
		}

		if w.scheduleUpload(current, virtualPath, true) {
			queuedFileCount++
		}
		return nil
	})
	if err == fs.SkipAll {
		return directoryCount, queuedFileCount, nil
	}
	return directoryCount, queuedFileCount, err
}
