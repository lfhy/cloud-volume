//go:build windows

// Windows requires a writable directory handle for FlushFileBuffers; os.File.Sync opens read-only.
package metadata

import (
	"fmt"

	"golang.org/x/sys/windows"
)

func syncDirectory(path string) error {
	name, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	handle, err := windows.CreateFile(
		name,
		windows.GENERIC_WRITE,
		windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE|windows.FILE_SHARE_DELETE,
		nil,
		windows.OPEN_EXISTING,
		windows.FILE_FLAG_BACKUP_SEMANTICS,
		0,
	)
	if err != nil {
		return fmt.Errorf("open directory for sync %q: %w", path, err)
	}
	defer windows.CloseHandle(handle)
	if err := windows.FlushFileBuffers(handle); err != nil {
		return fmt.Errorf("flush directory %q: %w", path, err)
	}
	return nil
}
