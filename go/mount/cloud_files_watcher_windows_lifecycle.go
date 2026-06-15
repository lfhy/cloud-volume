//go:build windows && cgo

// Watcher lifecycle helpers keep Cloud Files shutdown and harvest bookkeeping
// out of the main event-routing file.
package mount

import (
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func (w *windowsSyncWatcher) signalStop() {
	w.closeOnce.Do(func() {
		close(w.done)
	})
}

func (w *windowsSyncWatcher) shouldStop() bool {
	select {
	case <-w.done:
		return true
	default:
		return false
	}
}

func (w *windowsSyncWatcher) addWatch(localPath string) {
	if w.shouldStop() {
		return
	}
	clean := filepath.Clean(localPath)
	info, err := os.Stat(clean)
	if err != nil || !info.IsDir() {
		return
	}
	w.rawMu.Lock()
	if w.rawClosed || w.raw == nil {
		w.rawMu.Unlock()
		return
	}
	if w.watchWanted == nil {
		w.watchWanted = map[string]bool{}
	}
	if w.watchPending == nil {
		w.watchPending = map[string]bool{}
	}
	w.watchWanted[clean] = true
	if w.watched[clean] || w.watchPending[clean] {
		w.rawMu.Unlock()
		return
	}
	raw := w.raw
	w.watchPending[clean] = true
	w.rawMu.Unlock()

	w.wg.Add(1)
	go func() {
		defer w.wg.Done()

		err := raw.Add(clean)

		w.rawMu.Lock()
		if w.watchPending != nil {
			delete(w.watchPending, clean)
		}
		wanted := w.watchWanted[clean]
		closed := w.rawClosed || w.raw == nil
		w.rawMu.Unlock()

		if err != nil {
			log.Printf("[mount/cloud-files] watcher-add path=%q error=%v", clean, err)
			return
		}
		if closed || !wanted {
			_ = raw.Remove(clean)
			return
		}
		if info, statErr := os.Stat(clean); statErr != nil || !info.IsDir() {
			_ = raw.Remove(clean)
			return
		}

		w.rawMu.Lock()
		if w.rawClosed || w.raw == nil || !w.watchWanted[clean] {
			w.rawMu.Unlock()
			_ = raw.Remove(clean)
			return
		}
		if w.watched == nil {
			w.watched = map[string]bool{}
		}
		w.watched[clean] = true
		w.rawMu.Unlock()
	}()
}

func (w *windowsSyncWatcher) watchPlaceholderDirectories(baseDir string, items []cloudPlaceholderInfo) {
	// Fetch-placeholder callbacks may arrive after a directory was opened
	// through Explorer but before an earlier placeholder watch ever stuck.
	// Re-arming the current directory here makes nested local writes visible.
	w.addWatch(baseDir)
	for _, item := range items {
		if !item.IsDirectory {
			continue
		}
		fullPath := filepath.Join(baseDir, filepath.FromSlash(item.RelativePath))
		w.addWatch(fullPath)
	}
}

func (w *windowsSyncWatcher) removeWatchTree(localPath string) {
	clean := filepath.Clean(localPath)
	w.rawMu.Lock()
	if w.watchWanted != nil {
		for watchedPath := range w.watchWanted {
			if watchedPath == clean || strings.HasPrefix(watchedPath, clean+string(os.PathSeparator)) {
				delete(w.watchWanted, watchedPath)
			}
		}
	}
	if w.watchPending != nil {
		for watchedPath := range w.watchPending {
			if watchedPath == clean || strings.HasPrefix(watchedPath, clean+string(os.PathSeparator)) {
				delete(w.watchPending, watchedPath)
			}
		}
	}
	if w.rawClosed || w.raw == nil || len(w.watched) == 0 {
		w.rawMu.Unlock()
		return
	}
	paths := make([]string, 0)
	for watchedPath := range w.watched {
		if watchedPath == clean || strings.HasPrefix(watchedPath, clean+string(os.PathSeparator)) {
			paths = append(paths, watchedPath)
			delete(w.watched, watchedPath)
		}
	}
	raw := w.raw
	w.rawMu.Unlock()

	if len(paths) == 0 {
		return
	}
	w.wg.Add(1)
	go func() {
		defer w.wg.Done()
		for _, watchedPath := range paths {
			_ = raw.Remove(watchedPath)
		}
	}()
}

func (w *windowsSyncWatcher) closeRaw() error {
	w.rawMu.Lock()
	if w.rawClosed || w.raw == nil {
		w.rawMu.Unlock()
		return nil
	}
	w.rawClosed = true
	raw := w.raw
	w.rawMu.Unlock()
	return raw.Close()
}

func (w *windowsSyncWatcher) touchActiveHarvestAncestors(localPath string) {
	clean := filepath.Clean(localPath)
	root := filepath.Clean(w.root)
	if clean != root && !strings.HasPrefix(clean, root+string(os.PathSeparator)) {
		return
	}

	now := time.Now()
	w.harvestMu.Lock()
	defer w.harvestMu.Unlock()

	for {
		if _, ok := w.activeHarvests[clean]; ok {
			w.activeHarvests[clean] = now
		}
		if clean == root {
			return
		}
		parent := filepath.Dir(clean)
		if parent == clean {
			return
		}
		clean = parent
	}
}

func isResumableUploadStatePath(localPath string) bool {
	return strings.HasSuffix(strings.ToLower(filepath.Clean(localPath)), ".uploading.json")
}
