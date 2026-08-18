//go:build darwin

// macOS mount tests pin path recovery, Finder coalescing, and safe unmount lifecycle.
package mount

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"testing"
	"time"

	"path/filepath"
)

func TestUnmountCommands(t *testing.T) {
	t.Parallel()

	commands := unmountCommands("/Volumes/云卷-demo")
	if len(commands) != 3 {
		t.Fatalf("expected 3 unmount commands, got %d", len(commands))
	}
	if commands[0].name != "/sbin/umount" {
		t.Fatalf("expected first unmount command to be /sbin/umount, got %q", commands[0].name)
	}
	if commands[1].name != "/usr/sbin/diskutil" || commands[1].args[0] != "unmount" {
		t.Fatalf("expected second command to be diskutil unmount, got %+v", commands[1])
	}
	if commands[2].name != "/usr/sbin/diskutil" || commands[2].args[1] != "force" {
		t.Fatalf("expected third command to be diskutil unmount force, got %+v", commands[2])
	}
}

func TestFindMountedWebDAVPathAcceptsExactURLMatch(t *testing.T) {
	t.Parallel()

	got := findMountedWebDAVPath(
		"http://127.0.0.1:60250/%E4%BA%91%E5%8D%B7-%E6%B5%8B%E8%AF%95/",
		"",
		[]mountEntry{
			{SourceURL: "http://127.0.0.1:60250/云卷-测试/", Path: "/Volumes/云卷-测试"},
		},
	)
	if got != "/Volumes/云卷-测试" {
		t.Fatalf("recovered path = %q; want /Volumes/云卷-测试", got)
	}
}

// TestMountWebDAVRejectsEmptyMountPath pins the post-osascript-removal contract:
// mountWebDAV now always mounts at an explicit, resolved path via the synchronous
// /sbin/mount_webdav. An empty path must error explicitly rather than silently
// fall back to the old `osascript "mount volume"` fire-and-forget path, which
// registered the volume in the kernel and returned "mounted" before webdavfs_agent
// finished its ~90s handshake (leaving Finder unable to see or open the volume).
func TestMountWebDAVRejectsEmptyMountPath(t *testing.T) {
	t.Parallel()

	if _, err := mountWebDAV("http://127.0.0.1:65075/云卷-测试/", ""); err == nil {
		t.Fatal("expected mountWebDAV to reject an empty mount path")
	}
	if _, err := mountWebDAV("http://127.0.0.1:65075/云卷-测试/", "   "); err == nil {
		t.Fatal("expected mountWebDAV to reject a whitespace-only mount path")
	}
}

func TestFindMountedWebDAVPathMatchesRequestedPathByURL(t *testing.T) {
	t.Parallel()

	got := findMountedWebDAVPath(
		"http://127.0.0.1:60250/volume/",
		"/tmp/cloud-volume",
		[]mountEntry{
			{SourceURL: "http://127.0.0.1:60250/volume/", Path: "/tmp/cloud-volume"},
		},
	)
	if got != "/tmp/cloud-volume" {
		t.Fatalf("recovered requested path = %q", got)
	}
}

// TestFindMountedWebDAVPathRejectsSameNameDifferentPort is the regression
// anchor for the "reports mounted but Finder shows nothing" bug. A stale or
// cross-process volume with the same display name but a different source port
// must NOT be accepted as our mount — the random loopback port is the only
// proof the row belongs to the server we just started.
func TestFindMountedWebDAVPathRejectsSameNameDifferentPort(t *testing.T) {
	t.Parallel()

	got := findMountedWebDAVPath(
		"http://127.0.0.1:60123/云卷-demo/",
		"",
		[]mountEntry{
			{SourceURL: "http://127.0.0.1:19090/云卷-demo/", Path: "/Volumes/云卷-demo"},
		},
	)
	if got != "" {
		t.Fatalf("expected empty (port mismatch), got %q", got)
	}
}

// TestFindMountedWebDAVPathRejectsPathMatchWithoutURL guards the requested-path
// branch: even if a directory with the requested path exists in the mount
// table, it must not be reported unless its source URL matches our server.
// This catches the MkdirAll-then-misread-as-mounted failure mode.
func TestFindMountedWebDAVPathRejectsPathMatchWithoutURL(t *testing.T) {
	t.Parallel()

	got := findMountedWebDAVPath(
		"http://127.0.0.1:60123/云卷-demo/",
		"/tmp/cloud-volume-mount",
		[]mountEntry{
			{SourceURL: "http://127.0.0.1:19090/other/", Path: "/tmp/cloud-volume-mount"},
		},
	)
	if got != "" {
		t.Fatalf("expected empty (URL mismatch despite path match), got %q", got)
	}
}

// TestNormalizeServerURLTreatsTrailingSlashAsEqual confirms two equivalent
// spellings of the same loopback URL compare equal after normalization.
func TestNormalizeServerURLTreatsTrailingSlashAsEqual(t *testing.T) {
	t.Parallel()

	a, ok := normalizeServerURL("http://127.0.0.1:60123/scope")
	if !ok {
		t.Fatal("expected normalization to succeed")
	}
	b, ok := normalizeServerURL("http://127.0.0.1:60123/scope/")
	if !ok || a != b {
		t.Fatalf("trailing-slash variants must normalize equal: %q vs %q", a, b)
	}
}

func TestMountOpenGateCoalescesBusyFinderOpen(t *testing.T) {
	t.Parallel()

	gate := newMountOpenGate()
	const mountPath = "/Volumes/云卷-demo"
	if !gate.tryStart(mountPath) {
		t.Fatal("first Finder open was not admitted")
	}
	if gate.tryStart(mountPath) {
		t.Fatal("duplicate Finder open was not coalesced")
	}
	gate.finish(mountPath)
	if !gate.tryStart(mountPath) {
		t.Fatal("Finder open remained stuck after command completion")
	}
}

func TestStopKeepsWebDAVAliveWhenUnmountFails(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, "alive")
	})}
	go func() { _ = server.Serve(listener) }()
	webDAV := &webDAVServer{server: server, listener: listener}
	t.Cleanup(func() { _ = webDAV.stop() })

	oldProbe := probeWebDAVMountActive
	oldUnmount := executeUnmountWebDAV
	probeWebDAVMountActive = func(string) (bool, error) { return true, nil }
	executeUnmountWebDAV = func(string) error { return errors.New("busy") }
	t.Cleanup(func() {
		probeWebDAVMountActive = oldProbe
		executeUnmountWebDAV = oldUnmount
	})

	session := &mountSession{
		bucket:      "test-bucket",
		mounted:     true,
		stopping:    true,
		mountTarget: "/Volumes/云卷-test",
		server:      webDAV,
	}
	if err := session.stop(); err == nil {
		t.Fatal("stop unexpectedly succeeded")
	}
	if !session.mounted || session.stopping || session.server == nil {
		t.Fatal("failed unmount discarded the live mount server")
	}
	response, err := http.Get("http://" + listener.Addr().String())
	if err != nil {
		t.Fatalf("WebDAV server stopped after failed unmount: %v", err)
	}
	_ = response.Body.Close()
}

func TestStopDrainsWritebackBeforeUnmount(t *testing.T) {
	access := newTestBucketAccess(t)
	access.transferTimeout = time.Second
	var order []string
	oldDrain := drainMacOSWriteback
	oldProbe := probeWebDAVMountActive
	oldUnmount := executeUnmountWebDAV
	drainMacOSWriteback = func(_ context.Context, _ *bucketAccess) error {
		order = append(order, "drain")
		return nil
	}
	probeWebDAVMountActive = func(string) (bool, error) {
		order = append(order, "probe")
		return true, nil
	}
	executeUnmountWebDAV = func(string) error {
		order = append(order, "unmount")
		return nil
	}
	t.Cleanup(func() {
		drainMacOSWriteback = oldDrain
		probeWebDAVMountActive = oldProbe
		executeUnmountWebDAV = oldUnmount
	})

	session := &mountSession{
		bucket:      "test-bucket",
		mounted:     true,
		stopping:    true,
		mountTarget: "/Volumes/云卷-test",
		access:      access,
	}
	if err := session.stop(); err != nil {
		t.Fatalf("stop: %v", err)
	}
	if got, want := len(order), 3; got != want ||
		order[0] != "drain" || order[1] != "probe" || order[2] != "unmount" {
		t.Fatalf("unexpected stop order: %v", order)
	}
}

func TestStopKeepsMountWhenWritebackDrainTimesOut(t *testing.T) {
	access := newTestBucketAccess(t)
	access.transferTimeout = 10 * time.Millisecond
	oldDrain := drainMacOSWriteback
	oldProbe := probeWebDAVMountActive
	drainMacOSWriteback = func(ctx context.Context, _ *bucketAccess) error {
		<-ctx.Done()
		return ctx.Err()
	}
	probeWebDAVMountActive = func(string) (bool, error) {
		t.Fatal("unmount probe ran after drain timeout")
		return false, nil
	}
	t.Cleanup(func() {
		drainMacOSWriteback = oldDrain
		probeWebDAVMountActive = oldProbe
	})

	session := &mountSession{
		bucket:      "test-bucket",
		mounted:     true,
		stopping:    true,
		mountTarget: "/Volumes/云卷-test",
		access:      access,
	}
	if err := session.stop(); err == nil {
		t.Fatal("stop unexpectedly succeeded after drain timeout")
	}
	if !session.mounted || session.stopping || session.access == nil {
		t.Fatal("drain timeout did not preserve the live mount for retry")
	}
	if session.lastError == "" {
		t.Fatal("drain timeout was not surfaced through mount status")
	}
}

func TestOpenMountPathReturnsBeforeFinderStatfs(t *testing.T) {
	oldLaunchFinder := launchFinder
	launchFinder = func(path string) {
		macOSMountOpenGate.finish(filepath.Clean(path))
	}
	t.Cleanup(func() { launchFinder = oldLaunchFinder })
	dir := t.TempDir()
	startedAt := time.Now()
	if err := openMountPath(dir); err != nil {
		t.Fatalf("openMountPath: %v", err)
	}
	if elapsed := time.Since(startedAt); elapsed > time.Second {
		t.Fatalf("openMountPath blocked for %v; should return immediately", elapsed)
	}
	// The gate must eventually release so a subsequent open is not coalesced.
	clean := filepath.Clean(dir)
	deadline := time.Now().Add(macosOpenLaunchTimeout + 2*time.Second)
	for time.Now().Before(deadline) {
		if macOSMountOpenGate.tryStart(clean) {
			macOSMountOpenGate.finish(clean)
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("open gate was never released after Finder open dispatched")
}
