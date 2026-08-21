//go:build darwin

// Orphan WebDAV mount sweep cleans up leftover mounts after a crashed or
// force-quit app run. Exit-time cleanup is best-effort; this startup pass
// guarantees self-healing whenever a previous process died mid-session.
package mount

import (
	"fmt"
	"log"
	"net"
	"net/url"
	"strings"
)

// SweepOrphanMounts removes managed WebDAV mounts whose loopback server no
// longer has a listener. It is safe to call at every app startup.
func SweepOrphanMounts() (int, error) {
	return sweepOrphanWebDAVMounts()
}

func sweepOrphanWebDAVMounts() (int, error) {
	entries, err := listWebDAVMountEntries()
	if err != nil {
		return 0, err
	}
	removed := 0
	var firstErr error
	for _, entry := range entries {
		if !isManagedOrphanEntry(entry) {
			continue
		}
		log.Printf(
			"[mount/orphan-sweep] unmount path=%q source=%q",
			entry.Path,
			entry.SourceURL,
		)
		if err := unmountWebDAV(entry.Path); err != nil {
			log.Printf("[mount/orphan-sweep] unmount-failed path=%q err=%v", entry.Path, err)
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		removed++
	}
	if firstErr != nil {
		return removed, fmt.Errorf("orphan sweep: %w", firstErr)
	}
	return removed, nil
}

// isManagedOrphanEntry reports whether one mount row is a managed 云卷 mount
// pointing at a loopback URL with no live listener.
func isManagedOrphanEntry(entry mountEntry) bool {
	path := strings.TrimSpace(entry.Path)
	if path == "" || !isManagedMountPath(path) {
		return false
	}
	host, ok := loopbackHostPort(entry.SourceURL)
	if !ok {
		return false
	}
	listener, err := net.Dial("tcp", host)
	if err != nil {
		// No listener: the owning app process is gone; this mount is orphaned.
		return true
	}
	_ = listener.Close()
	return false
}

// isManagedMountPath checks the managed roots without the bucket-name variant
// used by session-scoped cleanup.
func isManagedMountPath(path string) bool {
	clean := canonicalMountPath(path)
	for _, root := range macOSManagedMountRoots() {
		basePrefix := root + "/" + managedMountPrefix
		if strings.HasPrefix(clean, basePrefix) {
			return true
		}
	}
	return false
}

// loopbackHostPort extracts host:port when the source URL is 127.0.0.1 loopback.
func loopbackHostPort(raw string) (string, bool) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return "", false
	}
	host := parsed.Hostname()
	if host != "127.0.0.1" && host != "localhost" && host != "::1" {
		return "", false
	}
	if parsed.Port() == "" {
		return "", false
	}
	return net.JoinHostPort(host, parsed.Port()), true
}
