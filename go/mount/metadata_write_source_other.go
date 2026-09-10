//go:build !windows

// Non-Windows metadata writes retain the standard read-only source open.
package mount

import "os"

func openMetadataWriteSource(localPath string) (*os.File, error) {
	return os.Open(localPath)
}
