//go:build !darwin

// Non-macOS builds keep the mount attribute hook as a no-op so the shared
// mount package can still compile on Windows and Linux hosts.
package mount

func markMountPathIgnoredByFileProvider(mountPath string) error {
	return nil
}
