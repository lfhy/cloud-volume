// WebDAV HEAD tests preserve the shared provider not-found contract.
package storage

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestWebDAVHeadObjectMapsHTTPNotFound(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PROPFIND" || r.Header.Get("Depth") != "0" {
			t.Fatalf("request method=%q depth=%q, want PROPFIND depth 0", r.Method, r.Header.Get("Depth"))
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	_, err := newTestWebDAVBackend(server.URL).HeadObject(nil, "WebDAV", "missing.txt")
	if !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("HeadObject error = %v, want os.ErrNotExist", err)
	}
}
