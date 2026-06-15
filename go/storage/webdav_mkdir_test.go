// WebDAV mkdir tests cover MKCOL status handling that differs across servers.
package storage

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestWebDAVCreateDirectoryReturnsMethodNotAllowedWhenTargetMissing(t *testing.T) {
	var mkcolPath string
	var existsProbePath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case "PROPFIND":
			if r.Header.Get("Depth") != "0" {
				t.Fatalf("Depth = %q, want 0", r.Header.Get("Depth"))
			}
			if r.URL.Path == "/dav/" {
				writeWebDAVAccessResponse(w, `<D:privilege><D:write/></D:privilege>`)
				return
			}
			if r.URL.Path == "/dav/new-folder/" {
				existsProbePath = r.URL.Path
				w.WriteHeader(http.StatusNotFound)
				return
			}
			t.Fatalf("PROPFIND path = %q, want access root or target probe", r.URL.Path)
		case "MKCOL":
			mkcolPath = r.URL.Path
			w.WriteHeader(http.StatusMethodNotAllowed)
		default:
			t.Fatalf("method = %q, want PROPFIND or MKCOL", r.Method)
		}
	}))
	defer server.Close()

	backend := newTestWebDAVBackend(server.URL)
	err := backend.CreateDirectory(nil, "WebDAV", "", "new-folder")
	if err == nil || !strings.Contains(err.Error(), "405 Method Not Allowed") {
		t.Fatalf("CreateDirectory error = %v, want 405 Method Not Allowed", err)
	}
	if mkcolPath != "/dav/new-folder/" {
		t.Fatalf("MKCOL path = %q, want /dav/new-folder/", mkcolPath)
	}
	if existsProbePath != "/dav/new-folder/" {
		t.Fatalf("exists probe path = %q, want /dav/new-folder/", existsProbePath)
	}
}

func TestWebDAVCreateDirectoryTreatsMethodNotAllowedAsExistingDirectory(t *testing.T) {
	var targetPropfinds int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case "PROPFIND":
			if r.Header.Get("Depth") != "0" {
				t.Fatalf("Depth = %q, want 0", r.Header.Get("Depth"))
			}
			if r.URL.Path == "/dav/" {
				writeWebDAVAccessResponse(w, `<D:privilege><D:write/></D:privilege>`)
				return
			}
			if r.URL.Path == "/dav/existing/" {
				targetPropfinds++
				writeWebDAVCollectionResponse(w, "/dav/existing/")
				return
			}
			t.Fatalf("PROPFIND path = %q, want access root or target probe", r.URL.Path)
		case "MKCOL":
			if r.URL.Path != "/dav/existing/" {
				t.Fatalf("MKCOL path = %q, want /dav/existing/", r.URL.Path)
			}
			w.WriteHeader(http.StatusMethodNotAllowed)
		default:
			t.Fatalf("method = %q, want PROPFIND or MKCOL", r.Method)
		}
	}))
	defer server.Close()

	backend := newTestWebDAVBackend(server.URL)
	if err := backend.CreateDirectory(nil, "WebDAV", "", "existing"); err != nil {
		t.Fatalf("CreateDirectory returned error: %v", err)
	}
	if targetPropfinds != 1 {
		t.Fatalf("target PROPFIND calls = %d, want 1", targetPropfinds)
	}
}

func newTestWebDAVBackend(serverURL string) Backend {
	return NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          serverURL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
}

func writeWebDAVAccessResponse(w http.ResponseWriter, privileges string) {
	w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
	_, _ = fmt.Fprintf(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:propstat>
      <D:status>HTTP/1.1 200 OK</D:status>
      <D:prop><D:current-user-privilege-set>%s</D:current-user-privilege-set></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>`, privileges)
}

func writeWebDAVCollectionResponse(w http.ResponseWriter, href string) {
	w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
	_, _ = fmt.Fprintf(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>%s</D:href>
    <D:propstat>
      <D:status>HTTP/1.1 200 OK</D:status>
      <D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>`, href)
}
