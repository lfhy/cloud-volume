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

func TestWebDAVOutOfOrderNestedMkdirCreatesLocalParents(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	backend.rejectUnknownDirectoryList = true
	_, handle := attachMetadataWriteService(t, access, backend)
	handle.Service.SetQuietPeriod(time.Hour)

	handler := &webdav.Handler{
		Prefix:     "/volume",
		FileSystem: &webDAVFS{access: access},
		LockSystem: webdav.NewMemLS(),
	}
	request := httptest.NewRequest("MKCOL", "http://mount.test/volume/project/core/proxy", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusCreated {
		t.Fatalf("out-of-order MKCOL status = %d, want %d", response.Code, http.StatusCreated)
	}

	for _, target := range []string{"project", "project/core", "project/core/proxy"} {
		info, err := access.statPath(context.Background(), target)
		if err != nil {
			t.Fatalf("stat local parent %q: %v", target, err)
		}
		if !info.IsDir {
			t.Fatalf("local parent %q = %+v, want directory", target, info)
		}
	}
	propfind := httptest.NewRequest("PROPFIND", "http://mount.test/volume/project/core", nil)
	propfind.Header.Set("Depth", "1")
	propfindResponse := httptest.NewRecorder()
	handler.ServeHTTP(propfindResponse, propfind)
	if propfindResponse.Code != http.StatusMultiStatus {
		t.Fatalf("local parent PROPFIND status = %d, want %d", propfindResponse.Code, http.StatusMultiStatus)
	}

	backend.mu.Lock()
	listPrefixes := append([]string(nil), backend.listPrefixes...)
	backend.mu.Unlock()
	for _, prefix := range listPrefixes {
		if strings.TrimSpace(prefix) != "" {
			t.Fatalf("out-of-order MKCOL materialized local parent remotely: prefix %q", prefix)
		}
	}
}
