// Package mount keeps optional mount request parameters separate from session state.
package mount

import (
	"path/filepath"
	"strings"
)

// MountOptions carries optional caller-specific mount behavior without
// changing the desktop bridge contract.
type MountOptions struct {
	MountPath     string
	ReadOnly      bool
	AutoSync      bool
	UploadWorkers int
}

func normalizeMountPath(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}
	return filepath.Clean(trimmed)
}
