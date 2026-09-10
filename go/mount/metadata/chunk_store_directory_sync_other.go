//go:build !windows

// Directory synchronization preserves the rename-before-bbolt durability order on POSIX hosts.
package metadata

import "os"

func syncDirectory(path string) error {
	dir, err := os.Open(path)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}
