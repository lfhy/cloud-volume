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

var (
	probeWebDAVMountActive = isWebDAVMountActive
	executeUnmountWebDAV   = unmountWebDAV
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

	mountPath, err := mountWebDAV(serverURL, s.mountPath)
	if err != nil {
		s.lastError = err.Error()
		return err
	}
	s.mountPath = mountPath
	s.mountTarget = mountPath
	s.mounted = true
	log.Printf("[mount/session] mounted bucket=%q path=%q", s.bucket, mountPath)
	// Pre-warm macOS webdavfs so the first user-visible access doesn't
	// pay the ~90s statfs initialization penalty. A background filesystem
	// stat forces webdavfs_agent to start its handshake immediately after
	// the volume appears, rather than waiting for Finder to trigger it.
	go prewarmWebDAVMount(mountPath)
	return nil
}

// prewarmWebDAVMount triggers webdavfs_agent initialization without
// blocking the mount path. It does a single os.Stat on the mount root
// (which forces the VFS layer to query the WebDAV server), then a
// ReadDir to populate the directory cache.
//
// os.Stat / os.ReadDir have no context parameter and cannot be interrupted
// once blocked inside webdavfs_agent. To stay true to "non-blocking to the
// caller", each call runs in its own goroutine and prewarmWebDAVMount waits
// at most prewarmStatTimeout for it. A truly wedged webdavfs therefore leaves
// a single leaked syscall goroutine behind, but prewarmWebDAVMount itself
// always returns within the bound and the next stop()/unmount can proceed.
const prewarmStatTimeout = 30 * time.Second

func prewarmWebDAVMount(mountPath string) {
	startedAt := time.Now()
	info, ok := boundedStat(mountPath, prewarmStatTimeout)
	if !ok {
		log.Printf("[mount/macos] prewarm-stat-timeout path=%q duration=%s", mountPath, time.Since(startedAt).Round(time.Millisecond))
		return
	}
	if info.err != nil {
		log.Printf("[mount/macos] prewarm-stat-error path=%q err=%v duration=%s", mountPath, info.err, time.Since(startedAt).Round(time.Millisecond))
		return
	}
	log.Printf("[mount/macos] prewarm-stat-done path=%q duration=%s size=%d", mountPath, time.Since(startedAt).Round(time.Millisecond), info.size)
	// Read one directory entry to populate the webdavfs dirent cache.
	// This is non-blocking to the caller and makes the first Finder
	// window significantly faster.
	entries, ok := boundedReadDir(mountPath, prewarmStatTimeout)
	if !ok {
		log.Printf("[mount/macos] prewarm-readdir-timeout path=%q duration=%s", mountPath, time.Since(startedAt).Round(time.Millisecond))
		return
	}
	if entries.err != nil {
		log.Printf("[mount/macos] prewarm-readdir-error path=%q err=%v duration=%s", mountPath, entries.err, time.Since(startedAt).Round(time.Millisecond))
		return
	}
	log.Printf("[mount/macos] prewarm-done path=%q entries=%d duration=%s", mountPath, entries.count, time.Since(startedAt).Round(time.Millisecond))
}

type statResult struct {
	size int64
	err  error
}

// boundedStat runs os.Stat in a goroutine and returns ok=false if it does
// not finish within timeout. The underlying syscall cannot be cancelled, so
// on timeout the goroutine remains live until webdavfs releases it.
func boundedStat(path string, timeout time.Duration) (statResult, bool) {
	result := make(chan statResult, 1)
	go func() {
		info, err := os.Stat(path)
		size := int64(-1)
		if err == nil {
			size = info.Size()
		}
		result <- statResult{size: size, err: err}
	}()
	select {
	case r := <-result:
		return r, true
	case <-time.After(timeout):
		return statResult{}, false
	}
}

type readDirResult struct {
	count int
	err   error
}

func boundedReadDir(path string, timeout time.Duration) (readDirResult, bool) {
	result := make(chan readDirResult, 1)
	go func() {
		entries, err := os.ReadDir(path)
		result <- readDirResult{count: len(entries), err: err}
	}()
	select {
	case r := <-result:
		return r, true
	case <-time.After(timeout):
		return readDirResult{}, false
	}
}

// mountWebDAV mounts the loopback WebDAV server at mountPath using the
// synchronous /sbin/mount_webdav command. Unlike `osascript "mount volume"`,
// which registers the volume in the kernel and returns immediately while
// webdavfs_agent finishes its ~90s handshake in the background, mount_webdav
// blocks until the volume is actually usable. The previous osascript path
// reported "mounted" from a stale mount-table entry, cancelled the still-running
// handshake, and left Finder unable to see or open the volume.
//
// mountPath is the already-resolved on-disk path (set by the macOS backend to
// either the caller's requested path or the default /Volumes/云卷-<bucket>).
func mountWebDAV(serverURL, mountPath string) (string, error) {
	cleanPath := filepath.Clean(strings.TrimSpace(mountPath))
	if cleanPath == "" || cleanPath == "." || cleanPath == "/" {
		return "", fmt.Errorf("mount bucket: invalid mount path %q", mountPath)
	}
	preparedPath, err := prepareMacOSMountPath(cleanPath)
	if err != nil {
		return "", err
	}
	cleanPath = preparedPath
	output, recovered, err := runLoggedCommandUntilSuccess(
		macosMountCommandTimeout,
		100*time.Millisecond,
		"mount-webdav-path",
		func() (string, bool) {
			mounted := probeMountedWebDAVPath(serverURL, cleanPath)
			return mounted, mounted != ""
		},
		"/sbin/mount_webdav",
		serverURL,
		cleanPath,
	)
	if recovered != "" {
		return recovered, nil
	}
	if err != nil {
		if recovered := recoverMountedWebDAVPath(serverURL, cleanPath); recovered != "" {
			return recovered, nil
		}
		return "", fmt.Errorf("mount bucket with macOS mount_webdav: %w: %s", err, string(output))
	}
	return cleanPath, nil
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

func recoverMountedWebDAVPath(serverURL, requestedPath string) string {
	deadline := time.Now().Add(2 * time.Second)
	for {
		if recovered := probeMountedWebDAVPath(serverURL, requestedPath); recovered != "" {
			return recovered
		}
		if time.Now().After(deadline) {
			return ""
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
		requested := filepath.Clean(requestedPath)
		for _, current := range matched {
			if filepath.Clean(current) == requested {
				return requested
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
