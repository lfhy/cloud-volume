//go:build !darwin

// Non-macOS platforms have no WebDAV orphan sweep; the bridge call stays a no-op.
package mount

// SweepOrphanMounts is a macOS-only startup recovery step.
func SweepOrphanMounts() (int, error) { return 0, nil }

