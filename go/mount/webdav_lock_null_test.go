// WebDAV lock-null tests keep Finder's reservation probes out of local writes.
package mount

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"golang.org/x/net/webdav"
)

const testLockInfo = `<?xml version="1.0" encoding="utf-8"?>
<D:lockinfo xmlns:D="DAV:">
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
  <D:owner><D:href>cloud-volume-test</D:href></D:owner>
</D:lockinfo>`

func TestWebDAVLockNullDoesNotStageContent(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	handle.Service.SetQuietPeriod(0)
	handler := webDAVLoggingHandler{next: &webdav.Handler{
		Prefix:     "/volume",
		FileSystem: &webDAVFS{access: access},
		LockSystem: webdav.NewMemLS(),
	}}

	lock := httptest.NewRequest("LOCK", "http://mount.test/volume/new.txt", strings.NewReader(testLockInfo))
	lock.Header.Set("Timeout", "Second-3600")
	lockResponse := httptest.NewRecorder()
	handler.ServeHTTP(lockResponse, lock)
	if lockResponse.Code != http.StatusCreated {
		t.Fatalf("LOCK status = %d, want %d", lockResponse.Code, http.StatusCreated)
	}
	if status := handle.Service.Status(); status.PendingOps != 0 || status.PendingContent != 0 {
		t.Fatalf("LOCK created durable content: %+v", status)
	}
	if _, err := handle.Service.StatPath(context.Background(), "new.txt"); err == nil {
		t.Fatal("LOCK created a Desired inode")
	}

	// A client that keeps the lock sends its token on the subsequent PUT.
	put := httptest.NewRequest("PUT", "http://mount.test/volume/new.txt", strings.NewReader("payload"))
	put.Header.Set("If", "("+lockResponse.Header().Get("Lock-Token")+")")
	putResponse := httptest.NewRecorder()
	handler.ServeHTTP(putResponse, put)
	if putResponse.Code != http.StatusCreated {
		t.Fatalf("PUT status = %d, want %d", putResponse.Code, http.StatusCreated)
	}
	if status := handle.Service.Status(); status.PendingOps != 1 || status.PendingContent != 1 {
		t.Fatalf("PUT did not create exactly one pending write: %+v", status)
	}
	if _, err := handle.Service.StatPath(context.Background(), "new.txt"); err != nil {
		t.Fatalf("PUT did not create Desired file: %v", err)
	}
}

func TestWebDAVLockNullDoesNotSuppressEmptyPut(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	handler := webDAVLoggingHandler{next: &webdav.Handler{
		Prefix:     "/volume",
		FileSystem: &webDAVFS{access: access},
		LockSystem: webdav.NewMemLS(),
	}}
	lock := httptest.NewRequest("LOCK", "http://mount.test/volume/empty.txt", strings.NewReader(testLockInfo))
	lock.Header.Set("Timeout", "Second-3600")
	lockResponse := httptest.NewRecorder()
	handler.ServeHTTP(lockResponse, lock)
	if lockResponse.Code != http.StatusCreated {
		t.Fatalf("LOCK status = %d, want %d", lockResponse.Code, http.StatusCreated)
	}
	put := httptest.NewRequest("PUT", "http://mount.test/volume/empty.txt", strings.NewReader(""))
	put.Header.Set("If", "("+lockResponse.Header().Get("Lock-Token")+")")
	putResponse := httptest.NewRecorder()
	handler.ServeHTTP(putResponse, put)
	if putResponse.Code != http.StatusCreated {
		t.Fatalf("empty PUT status = %d, want %d", putResponse.Code, http.StatusCreated)
	}
	if status := handle.Service.Status(); status.PendingOps != 1 || status.PendingContent != 1 {
		t.Fatalf("empty PUT was suppressed or duplicated: %+v", status)
	}
}
