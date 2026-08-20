package mount

import "strings"

// isFinderCopyTempPath identifies the per-file .BC.T_* staging names emitted
// by macOS webdavfs during a Finder copy. They are immediately renamed to the
// user-visible name, so persisting their bytes as remote objects duplicates
// every small-file write and exposes an implementation detail to the journal.
func isFinderCopyTempPath(virtualPath string) bool {
	name := baseName(virtualPath)
	return strings.HasPrefix(name, ".BC.T_") && len(name) > len(".BC.T_")
}
