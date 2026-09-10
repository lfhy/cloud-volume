//go:build windows && cgo

// Rename fallback tests cover the fsnotify Rename(old)+Create(new) pairing path.
package mount

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/fsnotify/fsnotify"
)

func TestWindowsHandleEventPrefersRenameOverRemove(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	oldPath := filepath.Join(root, "alpha.txt")
	newPath := filepath.Join(root, "renamed.txt")
	observed := windowsObservedFile{size: 19, modTime: 1234}
	state := &windowsPathState{
		ignored:      map[string]windowsIgnoredPath{},
		hydrating:    map[string]bool{},
		kinds:        map[string]bool{oldPath: false},
		files:        map[string]windowsObservedFile{oldPath: observed},
		placeholders: map[string]bool{},
	}
	access := newTestBucketAccess(t)
	watcher := &windowsSyncWatcher{root: root, access: access, state: state}

	watcher.handleEvent(fsnotify.Event{Name: oldPath, Op: fsnotify.Remove | fsnotify.Rename})
	if _, ok := state.pendingRenames[oldPath]; !ok {
		t.Fatal("combined Remove|Rename event discarded the rename candidate")
	}
	if _, ok := state.files[oldPath]; !ok {
		t.Fatal("combined source event must not forget the stable fingerprint")
	}

	newInfo, err := os.Stat(newPath)
	if err == nil {
		// The destination is optional for this event-ordering test; claiming a
		// matching fingerprint keeps the assertion meaningful when it exists.
		if old, ok := state.claimPendingFileRename(newPath, newInfo.Size(), newInfo.ModTime()); !ok || old != oldPath {
			t.Fatalf("combined event did not remain claimable: old=%q ok=%t", old, ok)
		}
	} else if !os.IsNotExist(err) {
		t.Fatalf("stat destination: %v", err)
	}
}

func TestWindowsRenameSourceRemoveEventKeepsPendingPair(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	oldPath := filepath.Join(root, "source.txt")
	newPath := filepath.Join(root, "target.txt")
	state := &windowsPathState{
		ignored:      map[string]windowsIgnoredPath{},
		hydrating:    map[string]bool{},
		kinds:        map[string]bool{oldPath: false},
		files:        map[string]windowsObservedFile{oldPath: {size: 12, modTime: 77}},
		placeholders: map[string]bool{},
	}
	if !state.beginPendingFileRename(oldPath) {
		t.Fatal("expected source to become pending rename")
	}
	watcher := &windowsSyncWatcher{root: root, access: access, state: state}
	watcher.handleRemovedSource(oldPath, "source.txt")
	if _, ok := state.claimPendingFileRename(newPath, 12, time.Unix(0, 77)); !ok {
		t.Fatal("Remove(old) event discarded the pending rename pair")
	}
}

func TestWindowsWatcherKeepsLegacyRenameAsNewUpload(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	oldPath := filepath.Join(root, "alpha.txt")
	newPath := filepath.Join(root, "renamed.txt")
	if err := os.WriteFile(oldPath, []byte("legacy payload"), 0o644); err != nil {
		t.Fatalf("write source: %v", err)
	}
	info, err := os.Stat(oldPath)
	if err != nil {
		t.Fatalf("stat source: %v", err)
	}
	watcher := &windowsSyncWatcher{
		root:   root,
		access: access,
		state: &windowsPathState{
			ignored:      map[string]windowsIgnoredPath{},
			hydrating:    map[string]bool{},
			kinds:        map[string]bool{oldPath: false},
			files:        map[string]windowsObservedFile{oldPath: {size: info.Size(), modTime: info.ModTime().UnixNano()}},
			placeholders: map[string]bool{},
		},
	}

	if err := os.Rename(oldPath, newPath); err != nil {
		t.Fatalf("rename legacy file: %v", err)
	}
	watcher.handleRenameSource(oldPath, "alpha.txt")
	newInfo, err := os.Stat(newPath)
	if err != nil {
		t.Fatalf("stat rename target: %v", err)
	}
	if watcher.completePendingFileRename(newPath, "renamed.txt", newInfo) {
		t.Fatal("legacy watcher must preserve create/upload semantics, not queue a remote move")
	}
	if len(watcher.state.pendingRenames) != 0 {
		t.Fatalf("legacy rename retained metadata-only candidates: %+v", watcher.state.pendingRenames)
	}
	if _, ok := watcher.state.files[oldPath]; ok {
		t.Fatal("legacy source watcher state survived rename")
	}
}
