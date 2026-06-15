//go:build windows

// Windows WebDAV mount helpers map the local server into a This-PC-visible network drive.
package mount

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"golang.org/x/sys/windows"
)

const managedMountPrefix = "云卷-"

var getLogicalDrivesProc = windows.NewLazySystemDLL("kernel32.dll").NewProc("GetLogicalDrives")

func mountWebDAVOnWindows(serverURL string) (string, error) {
	if err := ensureWindowsWebClientRunning(); err != nil {
		return "", err
	}
	drive, err := allocateWindowsDriveLetter()
	if err != nil {
		return "", err
	}
	cmd := exec.Command("net", "use", drive, serverURL, "/persistent:no")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("mount bucket with net use: %w: %s", err, string(output))
	}
	return drive + `\`, nil
}

func unmountWebDAVOnWindows(mountPath string) error {
	drive := normalizeWindowsDrive(mountPath)
	if drive == "" {
		return nil
	}
	cmd := exec.Command("net", "use", drive, "/delete", "/y")
	output, err := cmd.CombinedOutput()
	if err != nil {
		if !isWindowsDriveReachable(drive + `\`) {
			return nil
		}
		return fmt.Errorf("unmount bucket: %w: %s", err, string(output))
	}
	return nil
}

func isWindowsWebDAVMountActive(mountPath string) (bool, error) {
	if err := ensureWindowsMountPath(mountPath); err != nil {
		return false, err
	}
	return isWindowsDriveReachable(mountPath), nil
}

func cleanupManagedWindowsWebDAVMounts() error {
	if err := cleanupLegacyWindowsShellNamespaces(); err != nil {
		return err
	}
	drives, err := listManagedWindowsWebDAVMounts()
	if err != nil {
		return err
	}
	for _, drive := range drives {
		if err := unmountWebDAVOnWindows(drive); err != nil {
			return err
		}
	}
	return nil
}

func listManagedWindowsWebDAVMounts() ([]string, error) {
	cmd := exec.Command("net", "use")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("list mapped drives: %w: %s", err, string(output))
	}
	lines := strings.Split(string(output), "\n")
	matches := make([]string, 0)
	for _, line := range lines {
		fields := strings.Fields(strings.TrimSpace(line))
		if len(fields) < 3 {
			continue
		}
		local := strings.TrimSpace(fields[1])
		remote := strings.TrimSpace(fields[2])
		if !strings.HasSuffix(local, ":") {
			continue
		}
		if strings.Contains(strings.ToLower(remote), "127.0.0.1") {
			matches = append(matches, local+`\`)
		}
	}
	return matches, nil
}

func allocateWindowsDriveLetter() (string, error) {
	mask, _, callErr := getLogicalDrivesProc.Call()
	if mask == 0 {
		return "", fmt.Errorf("list local drives: %w", callErr)
	}
	used := uint32(mask)
	for letter := 'Z'; letter >= 'D'; letter-- {
		index := uint(letter - 'A')
		if used&(1<<index) != 0 {
			continue
		}
		return string(letter) + ":", nil
	}
	return "", fmt.Errorf("no available drive letter")
}

func ensureWindowsWebClientRunning() error {
	query := exec.Command("sc.exe", "query", "WebClient")
	output, err := query.CombinedOutput()
	if err == nil && strings.Contains(strings.ToUpper(string(output)), "RUNNING") {
		return nil
	}

	start := exec.Command("sc.exe", "start", "WebClient")
	startOutput, startErr := start.CombinedOutput()
	combined := strings.ToUpper(string(startOutput) + "\n" + string(output))
	if startErr == nil ||
		strings.Contains(combined, "RUNNING") ||
		strings.Contains(combined, "1056") {
		return nil
	}
	return fmt.Errorf("start WebClient service: %w: %s", startErr, string(startOutput))
}

func isWindowsDriveReachable(path string) bool {
	clean := filepath.Clean(strings.TrimSpace(path))
	if clean == "." || clean == "" {
		return false
	}
	if _, err := os.Stat(clean); err != nil {
		return false
	}
	return true
}

func normalizeWindowsDrive(path string) string {
	clean := strings.TrimSpace(path)
	if len(clean) < 2 {
		return ""
	}
	drive := strings.ToUpper(clean[:2])
	if drive[1] != ':' {
		return ""
	}
	return drive
}
