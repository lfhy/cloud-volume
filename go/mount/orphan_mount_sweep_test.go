//go:build darwin

// Orphan mount sweep tests pin the loopback/dead-port detection rules.
package mount

import (
	"net"
	"net/http/httptest"
	"strconv"
	"testing"
)

func TestLoopbackHostPort(t *testing.T) {
	t.Parallel()

	if host, ok := loopbackHostPort("http://127.0.0.1:65024/%E4%BA%91%E5%8D%B7/"); !ok || host != "127.0.0.1:65024" {
		t.Fatalf("loopback url parse = %q %v", host, ok)
	}
	if _, ok := loopbackHostPort("http://example.com:8080/path"); ok {
		t.Fatal("non-loopback source must not qualify")
	}
	if _, ok := loopbackHostPort("http://127.0.0.1/path"); ok {
		t.Fatal("loopback without port must not qualify")
	}
}

func TestIsManagedOrphanEntry(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(nil)
	defer server.Close()
	livePort := server.Listener.Addr().(*net.TCPAddr).Port

	if !isManagedOrphanEntry(mountEntry{
		SourceURL: "http://127.0.0.1:1/云卷-live/",
		Path:      "/Volumes/云卷-live",
	}) {
		t.Fatal("dead loopback port under managed path must be orphan")
	}
	if isManagedOrphanEntry(mountEntry{
		SourceURL: "http://127.0.0.1:1/other/",
		Path:      "/Volumes/other",
	}) {
		t.Fatal("unmanaged path must never be swept")
	}
	if isManagedOrphanEntry(mountEntry{
		SourceURL: "https://example.com/云卷-remote/",
		Path:      "/Volumes/云卷-remote",
	}) {
		t.Fatal("remote-backed managed mount must never be swept")
	}
	if isManagedOrphanEntry(mountEntry{
		SourceURL: "http://127.0.0.1:" + strconv.Itoa(livePort) + "/云卷-live/",
		Path:      "/Volumes/云卷-live",
	}) {
		t.Fatal("mount with a live loopback listener must be kept")
	}
}
