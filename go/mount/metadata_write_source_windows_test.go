//go:build windows

// The Windows source handle must permit Explorer to rename a staged file.
package mount

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestOpenMetadataWriteSourceAllowsRenameWhileOpen(t *testing.T) {
	dir := t.TempDir()
	oldPath := filepath.Join(dir, "alpha.txt")
	newPath := filepath.Join(dir, "renamed.txt")
	const content = "metadata source content"
	if err := os.WriteFile(oldPath, []byte(content), 0o600); err != nil {
		t.Fatalf("write source: %v", err)
	}

	file, err := openMetadataWriteSource(oldPath)
	if err != nil {
		t.Fatalf("open metadata write source: %v", err)
	}
	defer file.Close()
	if err := os.Rename(oldPath, newPath); err != nil {
		t.Fatalf("rename while source is open: %v", err)
	}
	data, err := io.ReadAll(file)
	if err != nil {
		t.Fatalf("read renamed source through open handle: %v", err)
	}
	if string(data) != content {
		t.Fatalf("read content = %q, want %q", data, content)
	}
}

func TestOpenMetadataWriteSourceAllowsDirectoryValidation(t *testing.T) {
	file, err := openMetadataWriteSource(t.TempDir())
	if err != nil {
		t.Fatalf("open directory source: %v", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		t.Fatalf("stat directory source: %v", err)
	}
	if !info.IsDir() {
		t.Fatalf("source mode = %v, want directory", info.Mode())
	}
}

func TestNormalizeMetadataWriteSourcePathPreservesLongPathForms(t *testing.T) {
	deepPath := filepath.Join(t.TempDir(), strings.Repeat("a", 245))
	normalized, err := normalizeMetadataWriteSourcePath(deepPath)
	if err != nil {
		t.Fatalf("normalize drive path: %v", err)
	}
	if !strings.HasPrefix(normalized, `\\?\`) {
		t.Fatalf("normalized drive path = %q, want long-path prefix", normalized)
	}

	uncPath := `\\server\share\` + strings.Repeat("a", 245)
	normalized, err = normalizeMetadataWriteSourcePath(uncPath)
	if err != nil {
		t.Fatalf("normalize UNC path: %v", err)
	}
	if !strings.HasPrefix(normalized, `\\?\UNC\server\share\`) {
		t.Fatalf("normalized UNC path = %q, want UNC long-path prefix", normalized)
	}

	alreadyExtended := `\\?\C:\` + strings.Repeat("a", 245)
	normalized, err = normalizeMetadataWriteSourcePath(alreadyExtended)
	if err != nil {
		t.Fatalf("normalize extended path: %v", err)
	}
	if normalized != alreadyExtended {
		t.Fatalf("normalized extended path = %q, want %q", normalized, alreadyExtended)
	}
}
