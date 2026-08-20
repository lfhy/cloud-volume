// WebDAV href tests keep URL-path decoding distinct from query-form decoding.
package storage

import (
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestWebDAVKeyFromHrefPreservesLiteralPlusAndEncodedPercent(t *testing.T) {
	backend := webDAVBackend{cfg: storageconfig.RemoteStorageConfig{
		Endpoint: "https://example.test/dav/",
	}}
	for href, want := range map[string]string{
		"/dav/a+b.txt":     "a+b.txt",
		"/dav/a%2Bb.txt":   "a+b.txt",
		"/dav/a%252Fb.txt": "a%2Fb.txt",
	} {
		got, ok := backend.keyFromHref(href)
		if !ok || got != want {
			t.Fatalf("keyFromHref(%q) = %q, %t; want %q, true", href, got, ok, want)
		}
	}
}
