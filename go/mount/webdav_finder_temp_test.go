// Finder copy-temp tests keep macOS's private staging names out of metadata.
package mount

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"golang.org/x/net/webdav"
)

func TestWebDAVFinderCopyTempStagesOnlyFinalName(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	handle.Service.SetQuietPeriod(0)
	handler := webDAVLoggingHandler{next: &webdav.Handler{
		Prefix:     "/volume",
		FileSystem: &webDAVFS{access: access},
		LockSystem: webdav.NewMemLS(),
	}}

	tempName := ".BC.T_copy"
	put := httptest.NewRequest(http.MethodPut, "http://mount.test/volume/"+tempName, strings.NewReader("payload"))
	putResponse := httptest.NewRecorder()
	handler.ServeHTTP(putResponse, put)
	if putResponse.Code != http.StatusCreated {
		t.Fatalf("temporary PUT status = %d, want %d", putResponse.Code, http.StatusCreated)
	}
	if status := handle.Service.Status(); status.PendingOps != 0 || status.PendingContent != 0 {
		t.Fatalf("temporary PUT entered metadata: %+v", status)
	}
	if _, err := access.overlay.statPath(tempName); err != nil {
		t.Fatalf("temporary overlay file missing: %v", err)
	}

	move := httptest.NewRequest("MOVE", "http://mount.test/volume/"+tempName, nil)
	move.Header.Set("Destination", "http://mount.test/volume/final.txt")
	moveResponse := httptest.NewRecorder()
	handler.ServeHTTP(moveResponse, move)
	if moveResponse.Code != http.StatusCreated {
		t.Fatalf("temporary MOVE status = %d, want %d", moveResponse.Code, http.StatusCreated)
	}
	if status := handle.Service.Status(); status.PendingOps != 1 || status.PendingContent != 1 {
		t.Fatalf("final MOVE did not create exactly one pending write: %+v", status)
	}
	if _, err := access.overlay.statPath(tempName); !os.IsNotExist(err) {
		t.Fatalf("temporary overlay remains after MOVE: %v", err)
	}
	object, err := handle.Service.StatPath(context.Background(), "final.txt")
	if err != nil {
		t.Fatalf("stat final Desired file: %v", err)
	}
	if object.Size != int64(len("payload")) {
		t.Fatalf("final Desired size = %d, want %d", object.Size, len("payload"))
	}
}

func TestWebDAVFinderCopyTempUsesFinalNestedPath(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	handler := webDAVLoggingHandler{next: &webdav.Handler{
		Prefix:     "/volume",
		FileSystem: &webDAVFS{access: access},
		LockSystem: webdav.NewMemLS(),
	}}

	put := httptest.NewRequest(
		http.MethodPut, "http://mount.test/volume/drafts/.BC.T_copy", strings.NewReader("payload"),
	)
	putResponse := httptest.NewRecorder()
	handler.ServeHTTP(putResponse, put)
	if putResponse.Code != http.StatusCreated {
		t.Fatalf("temporary PUT status = %d, want %d", putResponse.Code, http.StatusCreated)
	}
	move := httptest.NewRequest("MOVE", "http://mount.test/volume/drafts/.BC.T_copy", nil)
	move.Header.Set("Destination", "http://mount.test/volume/drafts/final.txt")
	moveResponse := httptest.NewRecorder()
	handler.ServeHTTP(moveResponse, move)
	if moveResponse.Code != http.StatusCreated {
		t.Fatalf("temporary MOVE status = %d, want %d", moveResponse.Code, http.StatusCreated)
	}
	object, err := handle.Service.StatPath(context.Background(), "drafts/final.txt")
	if err != nil {
		t.Fatalf("stat final Desired file: %v", err)
	}
	if object.Size != int64(len("payload")) {
		t.Fatalf("final Desired size = %d, want %d", object.Size, len("payload"))
	}
}
