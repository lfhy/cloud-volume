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

func listWebDAVMountPaths() ([]string, error) {
	output, err := runLoggedCommand(macosProbeCommandTimeout, "list-webdav-mounts", "mount", "-t", "webdav")
	if err != nil {
		return nil, fmt.Errorf("list webdav mounts: %w: %s", err, string(output))
	}
	return parseMountPaths(string(output)), nil
}

func mountOutputContainsPath(output, mountPath string) bool {
	target := filepath.Clean(strings.TrimSpace(mountPath))
	if target == "." || target == "" {
		return false
	}
	for _, current := range parseMountPaths(output) {
		if filepath.Clean(current) == target {
			return true
		}
	}
	return false
}

func parseMountPaths(output string) []string {
	paths := make([]string, 0)
	for _, line := range strings.Split(output, "\n") {
		current, ok := parseMountPoint(line)
		if !ok {
			continue
		}
		paths = append(paths, current)
	}
	return paths
}

func parseMountPoint(line string) (string, bool) {
	start := strings.Index(line, " on ")
	if start < 0 {
		return "", false
	}
	rest := line[start+4:]
	end := strings.LastIndex(rest, " (")
	if end < 0 {
		return "", false
	}
	return decodeMountField(rest[:end]), true
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
