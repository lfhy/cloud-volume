// WebDAV backend tests keep HTTP request construction safe for bridge callers.
package storage

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestWebDAVListObjectsPageAcceptsNilContext(t *testing.T) {
	var requested bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requested = true
		if r.Method != "PROPFIND" {
			t.Fatalf("method = %q, want PROPFIND", r.Method)
		}
		if r.Header.Get("Depth") != "1" {
			t.Fatalf("Depth = %q, want 1", r.Header.Get("Depth"))
		}
		username, password, ok := r.BasicAuth()
		if !ok || username != "web-user" || password != "web-pass" {
			t.Fatalf("unexpected basic auth username=%q password=%q ok=%v", username, password, ok)
		}
		w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
		_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/photo.jpg</D:href>
    <D:propstat><D:prop><D:getcontentlength>42</D:getcontentlength></D:prop></D:propstat>
  </D:response>
</D:multistatus>`)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	page, err := backend.ListObjectsPage(nil, "WebDAV", "", "", 200)
	if err != nil {
		t.Fatalf("ListObjectsPage returned error: %v", err)
	}
	if !requested {
		t.Fatal("expected WebDAV server to receive PROPFIND")
	}
	if len(page.Items) != 1 || page.Items[0].Key != "photo.jpg" {
		t.Fatalf("items = %#v, want one photo.jpg entry", page.Items)
	}
}

func TestWebDAVListObjectsPageSortsDirectoriesBeforeFiles(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PROPFIND" {
			t.Fatalf("method = %q, want PROPFIND", r.Method)
		}
		if r.Header.Get("Depth") != "1" {
			t.Fatalf("Depth = %q, want 1", r.Header.Get("Depth"))
		}
		w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
		_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/z-last.txt</D:href>
    <D:propstat><D:prop><D:getcontentlength>5</D:getcontentlength></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/alpha/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/beta.txt</D:href>
    <D:propstat><D:prop><D:getcontentlength>4</D:getcontentlength></D:prop></D:propstat>
  </D:response>
</D:multistatus>`)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	page, err := backend.ListObjectsPage(nil, "WebDAV", "", "", 200)
	if err != nil {
		t.Fatalf("ListObjectsPage returned error: %v", err)
	}
	if len(page.Items) != 3 {
		t.Fatalf("len(items) = %d, want 3", len(page.Items))
	}
	got := []string{page.Items[0].Key, page.Items[1].Key, page.Items[2].Key}
	want := []string{"alpha/", "beta.txt", "z-last.txt"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("keys = %v, want %v", got, want)
	}
	if !page.Items[0].IsDir {
		t.Fatalf("first item = %#v, want directory first", page.Items[0])
	}
}

func TestWebDAVHeadObjectKeepsDepthZeroTarget(t *testing.T) {
	var requestedPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestedPath = r.URL.Path
		if r.Method != "PROPFIND" {
			t.Fatalf("method = %q, want PROPFIND", r.Method)
		}
		if r.Header.Get("Depth") != "0" {
			t.Fatalf("Depth = %q, want 0", r.Header.Get("Depth"))
		}
		w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
		_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/20134-image/photo.jpg</D:href>
    <D:propstat><D:prop><D:getcontentlength>42</D:getcontentlength></D:prop></D:propstat>
  </D:response>
</D:multistatus>`)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	info, err := backend.HeadObject(nil, "WebDAV", "20134-image/photo.jpg")
	if err != nil {
		t.Fatalf("HeadObject returned error: %v", err)
	}
	if requestedPath != "/dav/20134-image/photo.jpg" {
		t.Fatalf("requested path = %q, want /dav/20134-image/photo.jpg", requestedPath)
	}
	if info.Key != "20134-image/photo.jpg" || info.Size != 42 || info.IsDir {
		t.Fatalf("info = %#v, want file object with size 42", info)
	}
}

func TestWebDAVDirectoryAccessDetectsReadOnlyPrivileges(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PROPFIND" || r.Header.Get("Depth") != "0" {
			t.Fatalf("unexpected request method=%q depth=%q", r.Method, r.Header.Get("Depth"))
		}
		w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
		_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:propstat>
      <D:status>HTTP/1.1 200 OK</D:status>
      <D:prop><D:current-user-privilege-set><D:privilege><D:read/></D:privilege></D:current-user-privilege-set></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>`)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	access, err := backend.DirectoryAccess(nil, "WebDAV", "readonly/")
	if err != nil {
		t.Fatalf("DirectoryAccess returned error: %v", err)
	}
	if !access.Known || access.Writable {
		t.Fatalf("access = %#v, want known readonly", access)
	}
}

func TestWebDAVDirectoryAccessDoesNotInheritRootReadOnly(t *testing.T) {
	var childAccessPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PROPFIND" || r.Header.Get("Depth") != "0" {
			t.Fatalf("unexpected request method=%q depth=%q", r.Method, r.Header.Get("Depth"))
		}
		w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
		privilege := `<D:privilege><D:read/></D:privilege>`
		if r.URL.Path == "/dav/writable/" {
			childAccessPath = r.URL.Path
			privilege = `<D:privilege><D:read/></D:privilege><D:privilege><D:write/></D:privilege>`
		}
		_, _ = fmt.Fprintf(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:propstat>
      <D:status>HTTP/1.1 200 OK</D:status>
      <D:prop><D:current-user-privilege-set>%s</D:current-user-privilege-set></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>`, privilege)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	rootAccess, err := backend.DirectoryAccess(nil, "WebDAV", "")
	if err != nil {
		t.Fatalf("root DirectoryAccess returned error: %v", err)
	}
	if !rootAccess.Known || rootAccess.Writable {
		t.Fatalf("root access = %#v, want known readonly", rootAccess)
	}
	childAccess, err := backend.DirectoryAccess(nil, "WebDAV", "writable/")
	if err != nil {
		t.Fatalf("child DirectoryAccess returned error: %v", err)
	}
	if childAccessPath != "/dav/writable/" {
		t.Fatalf("child access path = %q, want /dav/writable/", childAccessPath)
	}
	if !childAccess.Known || !childAccess.Writable {
		t.Fatalf("child access = %#v, want known writable", childAccess)
	}
}

func TestWebDAVUploadChecksChildDirectoryAccess(t *testing.T) {
	var sawPut bool
	var accessPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case "PROPFIND":
			if r.Header.Get("Depth") != "0" {
				t.Fatalf("Depth = %q, want 0", r.Header.Get("Depth"))
			}
			accessPath = r.URL.Path
			w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
			privilege := `<D:privilege><D:read/></D:privilege>`
			if r.URL.Path == "/dav/writable/" {
				privilege = `<D:privilege><D:read/></D:privilege><D:privilege><D:write-content/></D:privilege>`
			}
			_, _ = fmt.Fprintf(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:propstat>
      <D:status>HTTP/1.1 200 OK</D:status>
      <D:prop><D:current-user-privilege-set>%s</D:current-user-privilege-set></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>`, privilege)
		case "PUT":
			sawPut = true
			if r.URL.Path != "/dav/writable/photo.jpg" {
				t.Fatalf("PUT path = %q, want /dav/writable/photo.jpg", r.URL.Path)
			}
			w.WriteHeader(http.StatusCreated)
		default:
			t.Fatalf("method = %q, want PROPFIND or PUT", r.Method)
		}
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	err := backend.UploadReader(nil, "WebDAV", "writable/photo.jpg", strings.NewReader("image"), 5, "", "photo.jpg")
	if err != nil {
		t.Fatalf("UploadReader returned error: %v", err)
	}
	if accessPath != "/dav/writable/" {
		t.Fatalf("access path = %q, want /dav/writable/", accessPath)
	}
	if !sawPut {
		t.Fatal("expected PUT after child directory access check")
	}
}

func TestWebDAVDirectoryAccessTreatsReadOnlyOptionsMethodsAsReadOnly(t *testing.T) {
	var sawOptions bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "PROPFIND" {
			w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
			_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:"/>`)
			return
		}
		if r.Method != "OPTIONS" {
			t.Fatalf("method = %q, want OPTIONS fallback", r.Method)
		}
		sawOptions = true
		w.Header().Set("Allow", "OPTIONS, PROPFIND, GET")
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	access, err := backend.DirectoryAccess(nil, "WebDAV", "readonly/")
	if err != nil {
		t.Fatalf("DirectoryAccess returned error: %v", err)
	}
	if !sawOptions {
		t.Fatal("expected OPTIONS fallback")
	}
	if !access.Known || access.Writable {
		t.Fatalf("access = %#v, want known readonly fallback", access)
	}
}

func TestWebDAVDirectoryAccessDoesNotTreatMutatingOptionsWithoutPutAsReadOnly(t *testing.T) {
	var sawOptions bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "PROPFIND" {
			w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
			_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:"/>`)
			return
		}
		if r.Method != "OPTIONS" {
			t.Fatalf("method = %q, want OPTIONS fallback", r.Method)
		}
		sawOptions = true
		w.Header().Set("Allow", "OPTIONS, LOCK, DELETE, PROPPATCH, COPY, MOVE, UNLOCK, PROPFIND")
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	access, err := backend.DirectoryAccess(nil, "WebDAV", "writable/")
	if err != nil {
		t.Fatalf("DirectoryAccess returned error: %v", err)
	}
	if !sawOptions {
		t.Fatal("expected OPTIONS fallback")
	}
	if access.Known || !access.Writable {
		t.Fatalf("access = %#v, want unknown writable fallback", access)
	}
}

func TestWebDAVDirectoryAccessUsesCurrentOptionsPath(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "PROPFIND" {
			w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
			_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:"/>`)
			return
		}
		if r.Method != "OPTIONS" {
			t.Fatalf("method = %q, want OPTIONS fallback", r.Method)
		}
		allow := "OPTIONS, PROPFIND, GET"
		if r.URL.Path == "/dav/writable/" {
			allow = "OPTIONS, PROPFIND, GET, PUT"
		}
		w.Header().Set("Allow", allow)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	rootAccess, err := backend.DirectoryAccess(nil, "WebDAV", "")
	if err != nil {
		t.Fatalf("root DirectoryAccess returned error: %v", err)
	}
	if !rootAccess.Known || rootAccess.Writable {
		t.Fatalf("root access = %#v, want known readonly from root OPTIONS", rootAccess)
	}
	childAccess, err := backend.DirectoryAccess(nil, "WebDAV", "writable/")
	if err != nil {
		t.Fatalf("child DirectoryAccess returned error: %v", err)
	}
	if !childAccess.Known || !childAccess.Writable {
		t.Fatalf("child access = %#v, want known writable from child OPTIONS", childAccess)
	}
}

func TestWebDAVDirectoryAccessTreatsForbiddenOptionsAsReadOnly(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "PROPFIND" {
			w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
			_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:"/>`)
			return
		}
		if r.Method != "OPTIONS" {
			t.Fatalf("method = %q, want OPTIONS fallback", r.Method)
		}
		w.WriteHeader(http.StatusForbidden)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	access, err := backend.DirectoryAccess(nil, "WebDAV", "readonly/")
	if err != nil {
		t.Fatalf("DirectoryAccess returned error: %v", err)
	}
	if !access.Known || access.Writable {
		t.Fatalf("access = %#v, want known readonly", access)
	}
}

func TestWebDAVListBucketsUsesMappedBucketName(t *testing.T) {
	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          "https://example.invalid/dav/",
		DisplayName:       "Account Fallback",
		MappedBucketName:  "Second DAV",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	buckets, err := backend.ListBuckets(nil)
	if err != nil {
		t.Fatalf("ListBuckets returned error: %v", err)
	}
	if len(buckets) != 1 || buckets[0].Name != "Second DAV" {
		t.Fatalf("buckets = %#v, want mapped bucket name", buckets)
	}
}

func TestWebDAVReadObjectRangeUsesServerRangeSupport(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Fatalf("method = %q, want GET", r.Method)
		}
		if got := r.Header.Get("Range"); got != "bytes=6-10" {
			t.Fatalf("Range = %q, want bytes=6-10", got)
		}
		w.WriteHeader(http.StatusPartialContent)
		_, _ = fmt.Fprint(w, "world")
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	data, err := backend.ReadObjectRange(nil, "WebDAV", "notes.txt", 6, 5)
	if err != nil {
		t.Fatalf("ReadObjectRange returned error: %v", err)
	}
	if string(data) != "world" {
		t.Fatalf("data = %q, want world", string(data))
	}
}

func TestWebDAVReadObjectRangeFallsBackWhenServerIgnoresRange(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Fatalf("method = %q, want GET", r.Method)
		}
		w.WriteHeader(http.StatusOK)
		_, _ = fmt.Fprint(w, "hello world")
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	data, err := backend.ReadObjectRange(nil, "WebDAV", "notes.txt", 6, 5)
	if err != nil {
		t.Fatalf("ReadObjectRange returned error: %v", err)
	}
	if string(data) != "world" {
		t.Fatalf("data = %q, want world", string(data))
	}
}
