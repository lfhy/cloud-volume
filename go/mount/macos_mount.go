//go:build darwin

// macOS mount helpers wrap system WebDAV mounting, unmounting, and Finder opening.
package mount

import (
	"fmt"
	"log"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

type unmountCommand struct {
	name string
	args []string
}

// macosOpenLaunchTimeout bounds how long openMountPath waits for the Finder
// open call to fire before returning. macOS LaunchServices may block for
// ~90s on a freshly mounted webdav volume's first statfs; we never want
// to hold a goroutine that long, and the gate only needs to know the
// request was dispatched.
const macosOpenLaunchTimeout = 3 * time.Second

// This wait is only for the exact mount row; it never performs an upstream
// listing or waits for Finder's first statfs.
const macosMountReadyTimeout = 30 * time.Second

const macosMountCleanupTimeout = 45 * time.Second

var (
	probeWebDAVMountActive = isWebDAVMountActive
	executeUnmountWebDAV   = unmountWebDAV
	executeMountWebDAV     = runLoggedCommand
	probeMountedWebDAV     = probeMountedWebDAVPath
	waitMountedWebDAV      = waitForMountedWebDAVPath
	prepareMountPath       = prepareMacOSMountPath
	launchFinder           = runMacOSFinderOpen
)

func (s *mountSession) start() error {
	log.Printf("[mount/session] start bucket=%q mount_name=%q", s.bucket, s.mountName)
	server, serverURL, port, err := startWebDAVServer(s.access, s.mountName)
	if err != nil {
		return err
	}
	s.server = server
	s.serverURL = serverURL
	s.port = port
	log.Printf(
		"[mount/session] webdav-ready bucket=%q mount_name=%q url=%q port=%d",
		s.bucket,
		s.mountName,
		serverURL,
		port,
	)

	mountPath, err := prepareMountPath(s.mountPath)
	if err != nil {
		s.lastError = err.Error()
		return err
	}
	s.mountPath = mountPath
	s.mountTarget = mountPath
	s.mountAttempted = true
	mountPath, err = mountWebDAVPrepared(serverURL, mountPath, s.mountName)
	if err != nil {
		s.lastError = err.Error()
		return err
	}
	s.mountPath = mountPath
	s.mountTarget = mountPath
	s.mounted = true
	s.mountAttempted = false
	log.Printf("[mount/session] mounted bucket=%q path=%q", s.bucket, mountPath)
	return nil
}

// mountWebDAV starts the loopback WebDAV volume with /sbin/mount_webdav and
// waits for this URL/path to appear in the system mount table. The row wait
// confirms registration only; Apple's webdavfs_agent may still delay its first
// statfs, so Finder opening remains a separate asynchronous operation.
//
// mountPath is either a caller path or the managed default; this helper resolves
// a permitted default-path fallback before invoking the system command.
func mountWebDAV(serverURL, mountPath, volumeName string) (string, error) {
	cleanPath := filepath.Clean(strings.TrimSpace(mountPath))
	if cleanPath == "" || cleanPath == "." || cleanPath == "/" {
		return "", fmt.Errorf("mount bucket: invalid mount path %q", mountPath)
	}
	preparedPath, err := prepareMountPath(cleanPath)
	if err != nil {
		return "", err
	}
	return mountWebDAVPrepared(serverURL, preparedPath, volumeName)
}

func mountWebDAVPrepared(serverURL, mountPath, volumeName string) (string, error) {
	cleanPath := filepath.Clean(strings.TrimSpace(mountPath))
	if cleanPath == "" || cleanPath == "." || cleanPath == "/" {
		return "", fmt.Errorf("mount bucket: invalid mount path %q", mountPath)
	}
	volumeName = strings.TrimSpace(volumeName)
	if volumeName == "" {
		volumeName = filepath.Base(cleanPath)
	}
	// Do not cancel the command merely because the mount table row appears.
	// webdavfs_agent can still be initializing at that point; canceling here
	// reports a false success and immediately tears the new volume down.
	// -S is required for a desktop daemon: without it mount_webdav may wait
	// for an authentication or "server not responding" UI that no caller can
	// dismiss. Keep the volume name explicit so Finder does not derive it from
	// a temporary fallback path.
	output, err := executeMountWebDAV(
		macosMountCommandTimeout,
		"mount-webdav-path",
		"/sbin/mount_webdav",
		"-S",
		"-v",
		volumeName,
		serverURL,
		cleanPath,
	)
	if err != nil {
		cleanupErr := cleanupFailedWebDAVMount(serverURL, cleanPath)
		if cleanupErr != nil {
			return "", fmt.Errorf("mount bucket with macOS mount_webdav: %w: %s; cleanup: %v", err, string(output), cleanupErr)
		}
		return "", fmt.Errorf("mount bucket with macOS mount_webdav: %w: %s", err, string(output))
	}
	readyPath, readyErr := waitMountedWebDAV(serverURL, cleanPath, macosMountReadyTimeout)
	if readyErr != nil {
		if cleanupErr := cleanupFailedWebDAVMount(serverURL, cleanPath); cleanupErr != nil {
			return "", fmt.Errorf("%w; cleanup: %v", readyErr, cleanupErr)
		}
		return "", readyErr
	}
	return readyPath, nil
}

// prepareMacOSMountPath creates a caller-selected mount directory. The
// system /Volumes root is root-owned on normal macOS installs, so the default
// managed path falls back to a user-owned directory when it cannot be created.
func prepareMacOSMountPath(mountPath string) (string, error) {
	cleanPath := filepath.Clean(strings.TrimSpace(mountPath))
	err := os.MkdirAll(cleanPath, 0o755)
	if err == nil {
		return cleanPath, nil
	} else if !isManagedMacOSMountPath(cleanPath) || !os.IsPermission(err) {
		return "", err
	}
	fallback := macOSUserMountPath(cleanPath)
	if fallback == "" {
		return "", err
	}
	if fallbackErr := os.MkdirAll(fallback, 0o755); fallbackErr != nil {
		return "", fmt.Errorf("create macOS mount path %q: %w (fallback %q: %v)", cleanPath, err, fallback, fallbackErr)
	}
	log.Printf("[mount/macos] default-path-not-writable requested=%q fallback=%q", cleanPath, fallback)
	return fallback, nil
}

func isManagedMacOSMountPath(path string) bool {
	clean := filepath.Clean(strings.TrimSpace(path))
	return filepath.Dir(clean) == "/Volumes" && strings.HasPrefix(filepath.Base(clean), managedMountPrefix)
}

func macOSUserMountPath(path string) string {
	home, err := os.UserHomeDir()
	if err != nil || strings.TrimSpace(home) == "" {
		return ""
	}
	return filepath.Join(home, "云卷", filepath.Base(filepath.Clean(path)))
}

func waitForMountedWebDAVPath(serverURL, requestedPath string, timeout time.Duration) (string, error) {
	startedAt := time.Now()
	deadline := time.Now().Add(timeout)
	for {
		if recovered := probeMountedWebDAV(serverURL, requestedPath); recovered != "" {
			log.Printf(
				"[mount/macos] mount-webdav-registered path=%q duration=%s",
				recovered,
				time.Since(startedAt).Round(time.Millisecond),
			)
			return recovered, nil
		}
		if time.Now().After(deadline) {
			return "", fmt.Errorf("mount bucket with macOS mount_webdav: mount did not become visible within %s", timeout)
		}
		time.Sleep(100 * time.Millisecond)
	}
}

// cleanupFailedWebDAVMount removes a mount-table entry left behind when the
// synchronous command times out. The entry is evidence that registration
// started, not that webdavfs_agent is ready; it must never be returned as a
// successful mount path.
func cleanupFailedWebDAVMount(serverURL, requestedPath string) error {
	deadline := time.Now().Add(macosMountCleanupTimeout)
	var lastErr error
	for {
		if mounted := probeMountedWebDAV(serverURL, requestedPath); mounted != "" {
			if err := executeUnmountWebDAV(mounted); err != nil {
				lastErr = err
				log.Printf("[mount/macos] failed-mount-cleanup-error path=%q err=%v", mounted, err)
			} else {
				log.Printf("[mount/macos] failed-mount-cleanup-done path=%q", mounted)
				return nil
			}
		}
		if time.Now().After(deadline) {
			if lastErr != nil {
				return lastErr
			}
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func probeMountedWebDAVPath(serverURL, requestedPath string) string {
	entries, err := listWebDAVMountEntries()
	if err != nil {
		return ""
	}
	return findMountedWebDAVPath(serverURL, requestedPath, entries)
}

// findMountedWebDAVPath resolves the on-disk path of the volume that THIS
// app just mounted. It requires the row's source URL to match serverURL
// exactly (scheme + 127.0.0.1 + the random port we own); path-name-only
// matching was the root cause of "reports mounted but Finder shows nothing",
// because stale or cross-process volumes with the same name satisfied it.
func findMountedWebDAVPath(serverURL, requestedPath string, entries []mountEntry) string {
	want, ok := normalizeServerURL(serverURL)
	if !ok {
		return ""
	}
	matched := make([]string, 0)
	for _, entry := range entries {
		got, ok := normalizeServerURL(entry.SourceURL)
		if !ok || got != want {
			continue
		}
		matched = append(matched, entry.Path)
	}
	if len(matched) == 0 {
		return ""
	}
	if strings.TrimSpace(requestedPath) != "" {
		requested := canonicalMountPath(requestedPath)
		for _, current := range matched {
			if canonicalMountPath(current) == requested {
				return filepath.Clean(requestedPath)
			}
		}
		return ""
	}
	// osascript branch: no explicit mount path. Only accept an unambiguous
	// match — two volumes from the same URL should not happen, but refusing
	// to guess avoids reporting the wrong volume.
	if len(matched) != 1 {
		return ""
	}
	return matched[0]
}

// normalizeServerURL canonicalizes a loopback WebDAV URL so two strings for the
// same target compare equal: lowercased scheme/host, default port kept, and a
// trailing slash on the path so "http://127.0.0.1:60123/x" and ".../x/" agree.
func normalizeServerURL(raw string) (string, bool) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return "", false
	}
	parsed.Scheme = strings.ToLower(parsed.Scheme)
	parsed.Host = strings.ToLower(parsed.Host)
	parsed.Path = ensureDirSuffix(parsed.Path)
	return parsed.String(), true
}

func unmountWebDAV(mountPath string) error {
	var lastErr error
	var lastOutput string
	for _, candidate := range unmountCommands(mountPath) {
		phase := fmt.Sprintf("unmount cmd=%s path=%s", filepath.Base(candidate.name), mountPath)
		output, err := runLoggedCommand(
			macosUnmountCommandTimeout,
			phase,
			candidate.name,
			candidate.args...,
		)
		if err == nil {
			return nil
		}
		gone, probeErr := mountPathInactive(mountPath)
		if probeErr == nil {
			if gone {
				log.Printf("[mount/macos] unmount-confirmed-inactive path=%q", mountPath)
				return nil
			}
			lastErr = err
			lastOutput = strings.TrimSpace(string(output))
			continue
		}
		if _, statErr := os.Stat(mountPath); statErr != nil && os.IsNotExist(statErr) {
			log.Printf("[mount/macos] unmount-path-gone path=%q", mountPath)
			return nil
		}
		lastErr = err
		lastOutput = strings.TrimSpace(string(output))
	}
	if lastErr == nil {
		return nil
	}
	return fmt.Errorf("unmount bucket: %w: %s", lastErr, lastOutput)
}

func mountPathInactive(mountPath string) (bool, error) {
	active, err := isWebDAVMountActive(mountPath)
	if err != nil {
		return false, err
	}
	return !active, nil
}

var macOSMountOpenGate = newMountOpenGate()

type mountOpenGate struct {
	mu      sync.Mutex
	running map[string]struct{}
}

func newMountOpenGate() *mountOpenGate {
	return &mountOpenGate{running: make(map[string]struct{})}
}

func (g *mountOpenGate) tryStart(mountPath string) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	if _, exists := g.running[mountPath]; exists {
		return false
	}
	g.running[mountPath] = struct{}{}
	return true
}

func (g *mountOpenGate) finish(mountPath string) {
	g.mu.Lock()
	delete(g.running, mountPath)
	g.mu.Unlock()
}

func openMountPath(mountPath string) error {
	clean := filepath.Clean(mountPath)
	if !macOSMountOpenGate.tryStart(clean) {
		log.Printf("[mount/macos] open-mount-path coalesced path=%q", clean)
		return nil
	}
	go launchFinder(clean)
	return nil
}

// runMacOSFinderOpen launches Finder without inheriting our pipes.
// macOS LaunchServices spawns Finder via XPC; a plain exec inherits
// stdout/stderr which Finder keeps open for ~90s during the first statfs,
// so CombinedOutput blocks far past its context timeout. We detach the
// process: Start it with Stdout/Stderr set to os.DevNull and never Wait,
// logging only whether the launch itself succeeded.
func runMacOSFinderOpen(mountPath string) {
	defer macOSMountOpenGate.finish(mountPath)
	log.Printf("[mount/macos] open-mount-path start path=%q", mountPath)

	startedAt := time.Now()
	cmd := exec.Command("open", mountPath)
	// Detach all standard streams so no descendant (Finder, webdavfs_agent)
	// can hold our goroutine via an inherited pipe.
	devNull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		log.Printf("[mount/macos] open-mount-path detach-error path=%q err=%v", mountPath, err)
		return
	}
	defer devNull.Close()
	cmd.Stdout = devNull
	cmd.Stderr = devNull
	// Place the child in its own process group so a signal sent to our
	// process tree (e.g. during shutdown) cannot drag Finder with it.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	if err := cmd.Start(); err != nil {
		log.Printf("[mount/macos] open-mount-path start-error path=%q err=%v", mountPath, err)
		return
	}
	// Reap the immediate child (open exits quickly); do NOT wait for
	// descendants, which is exactly what blocks CombinedOutput.
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case <-done:
		log.Printf("[mount/macos] open-mount-path done path=%q duration=%s", mountPath, time.Since(startedAt).Round(time.Millisecond))
	case <-time.After(macosOpenLaunchTimeout):
		log.Printf("[mount/macos] open-mount-path dispatched path=%q duration=%s (open still running, Finder will appear)", mountPath, time.Since(startedAt).Round(time.Millisecond))
	}
}

// unmountCommands prefers plain umount first, then diskutil fallbacks for busy Finder-held volumes.
func unmountCommands(mountPath string) []unmountCommand {
	return []unmountCommand{
		{name: "/sbin/umount", args: []string{mountPath}},
		{name: "/usr/sbin/diskutil", args: []string{"unmount", mountPath}},
		{name: "/usr/sbin/diskutil", args: []string{"unmount", "force", mountPath}},
	}
}
