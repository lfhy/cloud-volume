//go:build !windows

package mount

// CleanupStaleWindowsProcesses is a no-op outside Windows.
func CleanupStaleWindowsProcesses() (int, error) {
	return 0, nil
}
