// WebDAV copy tests cover Finder's recursive directory-creation sequence.
package mount

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"golang.org/x/net/webdav"
)

func TestWebDAVNestedMkdirDoesNotMaterializeUnconfirmedParent(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	// SFTP ReadDir reports a missing path while Finder is still constructing a
	// local-only tree. This makes the test reproduce the protocol-level 409.
	backend.rejectUnknownDirectoryList = true
	_, handle := attachMetadataWriteService(t, access, backend)
	handle.Service.SetQuietPeriod(time.Hour)

	handler := &webdav.Handler{
		Prefix:     "/volume",
		FileSystem: &webDAVFS{access: access},
		LockSystem: webdav.NewMemLS(),
	}
	for _, target := range []string{"project", "project/core", "project/core/proxy"} {
		request := httptest.NewRequest("MKCOL", "http://mount.test/volume/"+target, nil)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != http.StatusCreated {
			t.Fatalf("MKCOL %q status = %d, want %d", target, response.Code, http.StatusCreated)
		}
	}
	backend.mu.Lock()
	listPrefixes := append([]string(nil), backend.listPrefixes...)
	backend.mu.Unlock()
	for _, prefix := range listPrefixes {
		if strings.TrimSpace(prefix) != "" {
			t.Fatalf("nested MKCOL materialized local parent remotely: prefix %q", prefix)
		}
	}

	info, err := access.statPath(context.Background(), "project/core/proxy")
	if err != nil {
		t.Fatalf("stat copied nested directory: %v", err)
	}
	if !info.IsDir {
		t.Fatalf("copied nested path is not a directory: %+v", info)
	}
}
