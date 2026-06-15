//go:build windows

// Windows WebDAV tests pin drive-letter parsing used by net use mount cleanup.
package mount

import "testing"

func TestNormalizeWindowsDrive(t *testing.T) {
	t.Parallel()

	if got := normalizeWindowsDrive(`z:\Cloud Volume`); got != "Z:" {
		t.Fatalf("unexpected drive normalization: %q", got)
	}
	if got := normalizeWindowsDrive(`\\server\share`); got != "" {
		t.Fatalf("expected UNC path to be ignored, got %q", got)
	}
}
