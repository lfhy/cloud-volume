//go:build windows && cgo

// Windows watcher state tracks placeholder, hydration, and provider-owned events.
package mount

import (
	"os"
	"path/filepath"
	"strings"
	"time"
)

type windowsProviderDelete struct {
	isDir bool
	until time.Time
}

// windowsPendingRename holds the last stable observation of a normal local
// file while fsnotify reports a Windows rename as old-name then new-name.
type windowsPendingRename struct {
	oldPath  string
	observed windowsObservedFile
	until    time.Time
}

func (s *windowsPathState) ignore(
	localPath string,
	ttl time.Duration,
	ignoreDescendants bool,
) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.ignored[filepath.Clean(localPath)] = windowsIgnoredPath{
		until:             time.Now().Add(ttl),
		ignoreDescendants: ignoreDescendants,
	}
}

// clearIgnore re-arms a directory after an explicit placeholder fetch.
func (s *windowsPathState) clearIgnore(localPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.ignored, filepath.Clean(localPath))
}

func (s *windowsPathState) shouldIgnore(localPath string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	s.pruneRenamesLocked(now)
	clean := filepath.Clean(localPath)
	for path := range s.hydrating {
		if pathCoversLocalPath(path, clean, true) {
			return true
		}
	}
	for path, ignored := range s.ignored {
		if now.After(ignored.until) {
			delete(s.ignored, path)
			continue
		}
		if pathCoversLocalPath(path, clean, ignored.ignoreDescendants) {
			return true
		}
	}
	return false
}

func (s *windowsPathState) markProviderDelete(localPath string, isDir bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	clean := filepath.Clean(localPath)
	until := time.Now().Add(windowsCFEventIgnoreTTL)
	if s.providerDeletes == nil {
		s.providerDeletes = map[string]windowsProviderDelete{}
	}
	s.providerDeletes[clean] = windowsProviderDelete{isDir: isDir, until: until}
	s.ignored[clean] = windowsIgnoredPath{
		until:             until,
		ignoreDescendants: isDir,
	}
}

func (s *windowsPathState) clearProviderDelete(localPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	clean := filepath.Clean(localPath)
	delete(s.providerDeletes, clean)
	delete(s.ignored, clean)
}

func (s *windowsPathState) isProviderDelete(localPath string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	clean := filepath.Clean(localPath)
	for path, deletion := range s.providerDeletes {
		if now.After(deletion.until) {
			delete(s.providerDeletes, path)
			continue
		}
		if pathCoversLocalPath(path, clean, deletion.isDir) {
			return true
		}
	}
	return false
}

func pathCoversLocalPath(parent, child string, descendants bool) bool {
	if child == parent {
		return true
	}
	return descendants && strings.HasPrefix(child, parent+string(os.PathSeparator))
}

func (s *windowsPathState) markHydrating(localPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.hydrating[filepath.Clean(localPath)] = true
}

func (s *windowsPathState) markHydrated(localPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	clean := filepath.Clean(localPath)
	delete(s.hydrating, clean)
	// Hydration writes are system-owned reads, not user edits.
	s.ignored[clean] = windowsIgnoredPath{
		until:             time.Now().Add(windowsCFEventIgnoreTTL),
		ignoreDescendants: false,
	}
	delete(s.placeholders, clean)
	if info, err := os.Stat(clean); err == nil && !info.IsDir() {
		s.files[clean] = windowsObservedFile{
			size:    info.Size(),
			modTime: info.ModTime().UnixNano(),
		}
	}
}

func (s *windowsPathState) remember(localPath string, isDir bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.kinds[filepath.Clean(localPath)] = isDir
}

// beginPendingFileRename retains only files with a known stable fingerprint.
// A later Create must match exactly and uniquely before it can become a rename.
func (s *windowsPathState) beginPendingFileRename(localPath string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	s.pruneRenamesLocked(now)
	clean := filepath.Clean(localPath)
	observed, ok := s.files[clean]
	if !ok || s.kinds[clean] {
		return false
	}
	if s.pendingRenames == nil {
		s.pendingRenames = map[string]windowsPendingRename{}
	}
	s.pendingRenames[clean] = windowsPendingRename{
		oldPath:  clean,
		observed: observed,
		until:    now.Add(windowsCFEventIgnoreTTL),
	}
	return true
}

// hasPendingFileRename reports whether the path is currently retained as a
// rename source, so a delete event does not discard it before pairing.
func (s *windowsPathState) hasPendingFileRename(localPath string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.pruneRenamesLocked(time.Now())
	_, ok := s.pendingRenames[filepath.Clean(localPath)]
	return ok
}

// claimPendingFileRename accepts a target only when one recent source has the
// exact final size and mtime. Ambiguous candidates deliberately remain creates.
func (s *windowsPathState) claimPendingFileRename(
	newPath string,
	size int64,
	modTime time.Time,
) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.pruneRenamesLocked(time.Now())
	target := filepath.Clean(newPath)
	targetParent := filepath.Dir(target)
	want := windowsObservedFile{size: size, modTime: modTime.UnixNano()}
	var matched windowsPendingRename
	matchedCount := 0
	for _, candidate := range s.pendingRenames {
		if candidate.oldPath == target {
			continue
		}
		if filepath.Dir(candidate.oldPath) != targetParent {
			continue
		}
		if candidate.observed != want {
			continue
		}
		matched = candidate
		matchedCount++
	}
	if matchedCount != 1 {
		return "", false
	}
	delete(s.pendingRenames, matched.oldPath)
	return matched.oldPath, true
}

func (s *windowsPathState) markFallbackRenameHandled(oldPath, newPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.completedRenames == nil {
		s.completedRenames = map[string]time.Time{}
	}
	s.completedRenames[windowsRenamePairKey(oldPath, newPath)] = time.Now().Add(windowsCFEventIgnoreTTL)
}

// fallbackRenameHandled stops a late CFAPI completion callback from applying
// the same durable rename after the watcher has already folded it.
func (s *windowsPathState) fallbackRenameHandled(oldPath, newPath string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pruneRenamesLocked(time.Now())
	_, ok := s.completedRenames[windowsRenamePairKey(oldPath, newPath)]
	return ok
}

func windowsRenamePairKey(oldPath, newPath string) string {
	return filepath.Clean(oldPath) + "\x00" + filepath.Clean(newPath)
}

func (s *windowsPathState) markPlaceholder(localPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.placeholders[filepath.Clean(localPath)] = true
}

func (s *windowsPathState) shouldQueueFile(
	localPath string,
	size int64,
	modTime time.Time,
	fromHarvest bool,
) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	clean := filepath.Clean(localPath)
	if fromHarvest && s.placeholders[clean] {
		return false
	}
	delete(s.placeholders, clean)
	next := windowsObservedFile{size: size, modTime: modTime.UnixNano()}
	current, ok := s.files[clean]
	if ok && current == next {
		return false
	}
	s.files[clean] = next
	return true
}

func (s *windowsPathState) isDir(localPath string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.kinds[filepath.Clean(localPath)]
}

func (s *windowsPathState) forget(localPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.forgetLocked(filepath.Clean(localPath))
}

func (s *windowsPathState) forgetLocked(clean string) {
	for current := range s.hydrating {
		if pathCoversLocalPath(clean, current, true) {
			delete(s.hydrating, current)
		}
	}
	for current := range s.kinds {
		if pathCoversLocalPath(clean, current, true) {
			delete(s.kinds, current)
		}
	}
	for current := range s.files {
		if pathCoversLocalPath(clean, current, true) {
			delete(s.files, current)
		}
	}
	for current := range s.placeholders {
		if pathCoversLocalPath(clean, current, true) {
			delete(s.placeholders, current)
		}
	}
	for current := range s.pendingRenames {
		if pathCoversLocalPath(clean, current, true) {
			delete(s.pendingRenames, current)
		}
	}
}

func (s *windowsPathState) pruneRenamesLocked(now time.Time) {
	for source, candidate := range s.pendingRenames {
		if now.After(candidate.until) {
			delete(s.pendingRenames, source)
			s.forgetLocked(source)
		}
	}
	for key, until := range s.completedRenames {
		if now.After(until) {
			delete(s.completedRenames, key)
		}
	}
}

func (s *windowsPathState) clearPlaceholdersUnder(localPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	clean := filepath.Clean(localPath)
	for current := range s.placeholders {
		if pathCoversLocalPath(clean, current, true) {
			delete(s.placeholders, current)
		}
	}
}

func (s *windowsPathState) rebase(oldPath, newPath string, isDir bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	oldClean := filepath.Clean(oldPath)
	newClean := filepath.Clean(newPath)
	updates := map[string]bool{}
	hydratingUpdates := map[string]bool{}
	for current := range s.hydrating {
		if pathCoversLocalPath(oldClean, current, true) {
			replacement := strings.Replace(current, oldClean, newClean, 1)
			hydratingUpdates[replacement] = true
			delete(s.hydrating, current)
		}
	}
	for current := range s.pendingRenames {
		if pathCoversLocalPath(oldClean, current, true) {
			delete(s.pendingRenames, current)
		}
	}
	for current, currentIsDir := range s.kinds {
		if pathCoversLocalPath(oldClean, current, true) {
			replacement := strings.Replace(current, oldClean, newClean, 1)
			updates[replacement] = currentIsDir
			delete(s.kinds, current)
		}
	}
	fileUpdates := map[string]windowsObservedFile{}
	for current, file := range s.files {
		if pathCoversLocalPath(oldClean, current, true) {
			replacement := strings.Replace(current, oldClean, newClean, 1)
			fileUpdates[replacement] = file
			delete(s.files, current)
		}
	}
	placeholderUpdates := map[string]bool{}
	for current := range s.placeholders {
		if pathCoversLocalPath(oldClean, current, true) {
			replacement := strings.Replace(current, oldClean, newClean, 1)
			placeholderUpdates[replacement] = true
			delete(s.placeholders, current)
		}
	}
	if len(updates) == 0 {
		updates[newClean] = isDir
	}
	for current, currentIsDir := range updates {
		s.kinds[current] = currentIsDir
	}
	for current, file := range fileUpdates {
		s.files[current] = file
	}
	for current := range placeholderUpdates {
		s.placeholders[current] = true
	}
	for current := range hydratingUpdates {
		s.hydrating[current] = true
	}
}
