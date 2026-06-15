package main

import (
	bucketmount "remote-storage/go/mount"
)

// clearMountCache removes stale cache and staging files under the mount
// runtime directory, skipping active mount sessions.
func clearMountCache() (any, error) {
	return bucketmount.ClearMountCache()
}
