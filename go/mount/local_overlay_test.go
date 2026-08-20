// Local overlay tests keep Finder-specific writable temp path behavior pinned down.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestLocalMountOverlaySeedsWritableSystemPaths(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	overlay, err := newLocalMountOverlay(root)
	if err != nil {
		t.Fatalf("newLocalMountOverlay: %v", err)
	}

	trashUID := fmt.Sprintf("%d", os.Getuid())
	requiredPaths := []string{
		filepath.Join(root, ".TemporaryItems"),
		filepath.Join(root, ".fseventsd"),
		filepath.Join(root, ".metadata_never_index"),
	}
	for _, path := range requiredPaths {
		info, statErr := os.Stat(path)
		if statErr != nil {
			t.Fatalf("stat %q: %v", path, statErr)
		}
		if path == filepath.Join(root, ".metadata_never_index") {
			if info.IsDir() {
				t.Fatalf("%q should be a file", path)
			}
			continue
		}
		if !info.IsDir() {
			t.Fatalf("%q is not a directory", path)
		}
	}

	if !overlay.handles(".TemporaryItems") {
		t.Fatal("expected overlay to handle .TemporaryItems")
	}
	if !overlay.handles("codex-debug-dir/.AU.test") {
		t.Fatal("expected overlay to handle nested .AU temp directory")
	}
	if !overlay.handles("codex-debug-dir/.ArchiveServiceTemp.sb-123") {
		t.Fatal("expected overlay to handle nested Archive Utility temp directory")
	}
	if !overlay.handles("codex-debug-dir/.DS_Store") {
		t.Fatal("expected overlay to handle nested .DS_Store sidecar file")
	}
	if overlay.handles("project/Resources/.localized") {
		t.Fatal("expected .localized to remain a regular project file")
	}
	if overlay.handles(".Trash") {
		t.Fatal("expected overlay to stop handling .Trash")
	}
	if overlay.handles(".Trashes") {
		t.Fatal("expected overlay to stop handling .Trashes")
	}
	if !overlay.isTrashPath(".Trash/example.txt") {
		t.Fatal("expected .Trash path to be treated as trash")
	}
	if !overlay.isTrashPath(".Trash-" + trashUID + "/example.txt") {
		t.Fatal("expected .Trash-<uid> path to be treated as trash")
	}
	if !overlay.isTrashPath(".Trashes/" + trashUID + "/example.txt") {
		t.Fatal("expected .Trashes/<uid> path to be treated as trash")
	}
}

func TestLocalMountOverlayListsNestedTransientEntries(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	overlay, err := newLocalMountOverlay(root)
	if err != nil {
		t.Fatalf("newLocalMountOverlay: %v", err)
	}

	tempDir := filepath.Join(root, "codex-debug-dir", ".ArchiveServiceTemp.sb-123")
	if err := os.MkdirAll(tempDir, 0o755); err != nil {
		t.Fatalf("mkdir temp dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "codex-debug-dir", ".DS_Store"), []byte("x"), 0o644); err != nil {
		t.Fatalf("write ds_store: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "codex-debug-dir", "real.txt"), []byte("skip"), 0o644); err != nil {
		t.Fatalf("write real file: %v", err)
	}

	items, err := overlay.listDirectory("codex-debug-dir")
	if err != nil {
		t.Fatalf("listDirectory: %v", err)
	}
	if len(items) != 2 {
		t.Fatalf("expected 2 transient overlay items, got %d (%+v)", len(items), items)
	}
}

func TestLocalMountOverlayRenameCreatesTargetParent(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	overlay, err := newLocalMountOverlay(root)
	if err != nil {
		t.Fatalf("newLocalMountOverlay: %v", err)
	}

	sourcePath := filepath.Join(root, "codex-debug-dir", ".AU.temp.nosync")
	if err := os.MkdirAll(sourcePath, 0o755); err != nil {
		t.Fatalf("mkdir source path: %v", err)
	}

	if err := overlay.rename(
		"codex-debug-dir/.AU.temp.nosync",
		"（AUHelperService正在保存文稿，已完成2）/.AU.temp.nosync",
	); err != nil {
		t.Fatalf("overlay rename: %v", err)
	}

	if _, err := os.Stat(filepath.Join(root, "（AUHelperService正在保存文稿，已完成2）", ".AU.temp.nosync")); err != nil {
		t.Fatalf("expected renamed overlay directory, got %v", err)
	}
}

func TestLocalMountOverlayRootListSkipsTransientParentDirectories(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	overlay, err := newLocalMountOverlay(root)
	if err != nil {
		t.Fatalf("newLocalMountOverlay: %v", err)
	}

	if err := os.MkdirAll(filepath.Join(root, "codex-debug-dir", ".ArchiveServiceTemp.sb-123"), 0o755); err != nil {
		t.Fatalf("mkdir transient nested dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(root, "（AUHelperService正在保存文稿，已完成3）", ".AU.temp.nosync"), 0o755); err != nil {
		t.Fatalf("mkdir transient target parent: %v", err)
	}

	items, err := overlay.listRootEntries()
	if err != nil {
		t.Fatalf("listRootEntries: %v", err)
	}
	for _, item := range items {
		if item.Key == "codex-debug-dir/" || item.Key == "（AUHelperService正在保存文稿，已完成3）/" {
			t.Fatalf("unexpected transient parent directory surfaced at root: %+v", item)
		}
	}
}
