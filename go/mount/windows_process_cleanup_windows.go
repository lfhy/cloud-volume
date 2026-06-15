//go:build windows

// Windows process cleanup helpers terminate stale local debug runners that can
// keep bridge artifacts and writeback DB files locked after a failed session.
package mount

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// CleanupStaleWindowsProcesses kills leftover cloud-volume.exe processes that
// were launched from this repository's Windows runner output.
func CleanupStaleWindowsProcesses() (int, error) {
	exePath, err := exec.LookPath("powershell")
	if err != nil {
		return 0, fmt.Errorf("locate powershell: %w", err)
	}

	workspaceRoot, err := locateWorkspaceRoot()
	if err != nil {
		return 0, fmt.Errorf("resolve workspace root: %w", err)
	}
	targetPrefix := strings.ToLower(filepath.Clean(
		filepath.Join(workspaceRoot, "build", "windows", "x64", "runner"),
	))
	currentPID := os.Getpid()
	escapedPrefix := strings.ReplaceAll(targetPrefix, "'", "''")

	script := fmt.Sprintf(`
$targetPrefix = '%s'
$currentPid = %d
$killed = 0
$processes = Get-CimInstance Win32_Process -Filter "Name = 'cloud-volume.exe'"
foreach ($process in $processes) {
  if ($process.ProcessId -eq $currentPid) { continue }
  $path = $process.ExecutablePath
  if (-not $path) { continue }
  $clean = [System.IO.Path]::GetFullPath($path).ToLowerInvariant()
  if (-not $clean.StartsWith($targetPrefix)) { continue }
  Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
  $killed++
}
Write-Output $killed
`, escapedPrefix, currentPID)

	cmd := exec.Command(exePath, "-NoProfile", "-Command", script)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return 0, fmt.Errorf("cleanup stale windows processes: %w: %s", err, strings.TrimSpace(stderr.String()))
	}
	countText := strings.TrimSpace(stdout.String())
	if countText == "" {
		return 0, nil
	}
	var count int
	if _, err := fmt.Sscanf(countText, "%d", &count); err != nil {
		return 0, fmt.Errorf("parse cleanup stale windows processes count %q: %w", countText, err)
	}
	return count, nil
}

func locateWorkspaceRoot() (string, error) {
	candidates := []string{}
	if wd, err := os.Getwd(); err == nil && wd != "" {
		candidates = append(candidates, wd)
	}
	if exePath, err := os.Executable(); err == nil && exePath != "" {
		candidates = append(candidates, filepath.Dir(exePath))
	}

	for _, candidate := range candidates {
		if root, ok := searchWorkspaceRoot(candidate); ok {
			return root, nil
		}
	}
	return "", fmt.Errorf("could not locate repository root from cwd or executable path")
}

func searchWorkspaceRoot(start string) (string, bool) {
	current := filepath.Clean(start)
	for {
		if fileExists(filepath.Join(current, "go.mod")) &&
			dirExists(filepath.Join(current, "bridge")) {
			return current, true
		}
		parent := filepath.Dir(current)
		if parent == current {
			return "", false
		}
		current = parent
	}
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}
