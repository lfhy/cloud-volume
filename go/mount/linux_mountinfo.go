//go:build linux

// Linux mount probing keeps FUSE-backed in-memory session state aligned with mountinfo.
package mount

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

func linuxMountActive(mountPath string) (bool, error) {
	target := filepath.Clean(strings.TrimSpace(mountPath))
	if target == "." || target == "" {
		return false, nil
	}
	paths, err := listLinuxFuseMountPaths()
	if err != nil {
		return false, err
	}
	for _, current := range paths {
		if filepath.Clean(current) == target {
			return true, nil
		}
	}
	return false, nil
}

func listLinuxManagedMountPaths() ([]string, error) {
	rootPath, err := linuxMountRootPath()
	if err != nil {
		return nil, err
	}
	paths, err := listLinuxFuseMountPaths()
	if err != nil {
		return nil, err
	}
	managed := make([]string, 0, len(paths))
	for _, mountPath := range paths {
		clean := filepath.Clean(mountPath)
		if clean == rootPath || strings.HasPrefix(clean, rootPath+string(os.PathSeparator)) {
			managed = append(managed, clean)
		}
	}
	return managed, nil
}

func listLinuxFuseMountPaths() ([]string, error) {
	file, err := os.Open("/proc/self/mountinfo")
	if err != nil {
		return nil, fmt.Errorf("open linux mountinfo: %w", err)
	}
	defer file.Close()

	paths := make([]string, 0)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		mountPath, fsType, ok := parseLinuxMountInfoLine(scanner.Text())
		if !ok || !strings.HasPrefix(fsType, "fuse.") {
			continue
		}
		paths = append(paths, filepath.Clean(mountPath))
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan linux mountinfo: %w", err)
	}
	return paths, nil
}

func linuxUnmountPath(mountPath string) error {
	output, err := exec.Command("fusermount3", "-u", mountPath).CombinedOutput()
	if err != nil {
		return fmt.Errorf("unmount linux fuse path %q: %w: %s", mountPath, err, string(output))
	}
	return nil
}

func parseLinuxMountInfoLine(line string) (string, string, bool) {
	parts := strings.Split(line, " - ")
	if len(parts) != 2 {
		return "", "", false
	}
	left := strings.Fields(parts[0])
	right := strings.Fields(parts[1])
	if len(left) < 5 || len(right) < 1 {
		return "", "", false
	}
	return decodeLinuxMountField(left[4]), right[0], true
}

func decodeLinuxMountField(value string) string {
	return strings.NewReplacer(`\040`, " ", `\011`, "\t", `\012`, "\n", `\134`, `\`).Replace(
		decodeLinuxOctalEscapes(value),
	)
}

func decodeLinuxOctalEscapes(value string) string {
	return mountInfoEscapePattern.ReplaceAllStringFunc(value, func(match string) string {
		code, err := strconv.ParseInt(match[1:], 8, 32)
		if err != nil {
			return match
		}
		return string(rune(code))
	})
}
