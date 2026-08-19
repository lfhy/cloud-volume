//go:build darwin

// System mount probing keeps in-memory mount state aligned with macOS reality.
package mount

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

var mountEscapePattern = regexp.MustCompile(`\\([0-7]{3})`)

func isWebDAVMountActive(mountPath string) (bool, error) {
	output, err := runLoggedCommand(macosProbeCommandTimeout, "probe-webdav-mounts", "mount", "-t", "webdav")
	if err != nil {
		return false, fmt.Errorf("list webdav mounts: %w: %s", err, string(output))
	}
	return mountOutputContainsPath(string(output), mountPath), nil
}

// isExactWebDAVMountActive verifies both the mount point and the loopback URL
// that owns it. It is required while a failed attempt is still being retained.
func isExactWebDAVMountActive(serverURL, mountPath string) (bool, error) {
	entries, err := listWebDAVMountEntries()
	if err != nil {
		return false, err
	}
	return findMountedWebDAVPath(serverURL, mountPath, entries) != "", nil
}

// mountEntry pairs a WebDAV volume's source URL with its on-disk mount path.
// macOS `mount -t webdav` reports both, and the URL (which carries our random
// loopback port) is the only reliable signal that a row belongs to this app's
// just-started server — matching on path name alone collides with stale or
// cross-process volumes and produces false "mounted" success.
type mountEntry struct {
	SourceURL string
	Path      string
}

func listWebDAVMountPaths() ([]string, error) {
	entries, err := listWebDAVMountEntries()
	if err != nil {
		return nil, err
	}
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		paths = append(paths, entry.Path)
	}
	return paths, nil
}

func listWebDAVMountEntries() ([]mountEntry, error) {
	output, err := runLoggedCommand(macosProbeCommandTimeout, "list-webdav-mounts", "mount", "-t", "webdav")
	if err != nil {
		return nil, fmt.Errorf("list webdav mounts: %w: %s", err, string(output))
	}
	return parseMountEntries(string(output)), nil
}

func mountOutputContainsPath(output, mountPath string) bool {
	target := canonicalMountPath(mountPath)
	if target == "." || target == "" {
		return false
	}
	for _, current := range parseMountPaths(output) {
		if canonicalMountPath(current) == target {
			return true
		}
	}
	return false
}

// canonicalMountPath compares the parent directory after resolving macOS's
// /var -> /private/var alias. Resolving only the parent avoids touching a live
// WebDAV root, where a full EvalSymlinks call could enter the slow VFS path.
func canonicalMountPath(value string) string {
	clean := filepath.Clean(strings.TrimSpace(value))
	if clean == "." || clean == "" {
		return clean
	}
	parent := filepath.Dir(clean)
	if resolvedParent, err := filepath.EvalSymlinks(parent); err == nil {
		return filepath.Join(resolvedParent, filepath.Base(clean))
	}
	return clean
}

func parseMountPaths(output string) []string {
	entries := parseMountEntries(output)
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		paths = append(paths, entry.Path)
	}
	return paths
}

// parseMountEntries splits macOS `mount` output into source/path pairs.
// A row looks like:
//
//	http://127.0.0.1:19090/<scope>/ on /Volumes/云卷-demo (webdav, nodev, ...)
//
// The " on " separator splits source URL from mount path; both halves carry
// octal escapes (e.g. \040 for space) which decodeMountField expands.
func parseMountEntries(output string) []mountEntry {
	entries := make([]mountEntry, 0)
	for _, line := range strings.Split(output, "\n") {
		source, path, ok := parseMountEntry(line)
		if !ok {
			continue
		}
		entries = append(entries, mountEntry{SourceURL: source, Path: path})
	}
	return entries
}

func parseMountPoint(line string) (string, bool) {
	_, path, ok := parseMountEntry(line)
	return path, ok
}

// parseMountEntry extracts the source URL and mount path from one mount row.
// It splits on the first " on " so a URL path containing " on " cannot fool the
// split, then trims the trailing " (options)" tail from the path half.
func parseMountEntry(line string) (source, path string, ok bool) {
	idx := strings.Index(line, " on ")
	if idx < 0 {
		return "", "", false
	}
	source = strings.TrimSpace(line[:idx])
	rest := line[idx+4:]
	end := strings.LastIndex(rest, " (")
	if end < 0 {
		return "", "", false
	}
	if source == "" {
		return "", "", false
	}
	return source, decodeMountField(rest[:end]), true
}

func decodeMountField(value string) string {
	return mountEscapePattern.ReplaceAllStringFunc(value, func(match string) string {
		code, err := strconv.ParseInt(match[1:], 8, 32)
		if err != nil {
			return match
		}
		return string(rune(code))
	})
}
