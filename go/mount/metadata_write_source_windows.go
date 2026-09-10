//go:build windows

// Windows metadata write sources share delete access with Explorer moves.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/sys/windows"
)

func openMetadataWriteSource(localPath string) (*os.File, error) {
	normalizedPath, err := normalizeMetadataWriteSourcePath(localPath)
	if err != nil {
		return nil, err
	}
	path, err := windows.UTF16PtrFromString(normalizedPath)
	if err != nil {
		return nil, fmt.Errorf("encode metadata write source path: %w", err)
	}
	handle, err := windows.CreateFile(
		path,
		windows.GENERIC_READ,
		windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE|windows.FILE_SHARE_DELETE,
		nil,
		windows.OPEN_EXISTING,
		windows.FILE_ATTRIBUTE_NORMAL|windows.FILE_FLAG_BACKUP_SEMANTICS,
		0,
	)
	if err != nil {
		return nil, fmt.Errorf("open metadata write source %q: %w", localPath, err)
	}
	file := os.NewFile(uintptr(handle), normalizedPath)
	if file == nil {
		_ = windows.CloseHandle(handle)
		return nil, fmt.Errorf("create metadata write source file for %q", localPath)
	}
	return file, nil
}

// normalizeMetadataWriteSourcePath mirrors the long-path handling that os.Open
// applies before this direct CreateFile call, including UNC path conversion.
func normalizeMetadataWriteSourcePath(localPath string) (string, error) {
	if strings.HasPrefix(localPath, `\\?\`) || strings.HasPrefix(localPath, `\??\`) {
		return localPath, nil
	}
	absPath, err := filepath.Abs(localPath)
	if err != nil {
		return "", fmt.Errorf("resolve metadata write source path: %w", err)
	}
	if len(absPath) < 248 {
		return absPath, nil
	}
	if strings.HasPrefix(absPath, `\\`) {
		return `\\?\UNC\` + strings.TrimPrefix(absPath, `\\`), nil
	}
	return `\\?\` + absPath, nil
}
