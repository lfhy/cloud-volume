// Exported WebDAV HTTP handlers let the web server reuse bucketAccess safely.
package mount

import (
	"fmt"
	"net/http"
	"strings"

	storageconfig "remote-storage/go/config"

	"golang.org/x/net/webdav"
)

// BucketWebDAVHandler serves one bucket under an externally provided URL prefix.
type BucketWebDAVHandler struct {
	access  *bucketAccess
	handler http.Handler
}

// NewBucketWebDAVHandler builds a reusable HTTP handler for one bucket.
func NewBucketWebDAVHandler(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	prefix string,
) (*BucketWebDAVHandler, error) {
	trimmedBucket := normalizeBucketName(bucket)
	if trimmedBucket == "" {
		return nil, fmt.Errorf("missing bucket name")
	}
	access, err := newBucketAccess(cfg.Normalized(), trimmedBucket)
	if err != nil {
		return nil, err
	}
	scope := "/" + strings.Trim(strings.TrimSpace(prefix), "/")
	handler := &webdav.Handler{
		Prefix:     scope,
		FileSystem: &webDAVFS{access: access},
		LockSystem: webdav.NewMemLS(),
	}
	return &BucketWebDAVHandler{
		access:  access,
		handler: webDAVLoggingHandler{next: handler},
	}, nil
}

// ServeHTTP proxies requests into the bucket-scoped WebDAV filesystem.
func (h *BucketWebDAVHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.handler.ServeHTTP(w, r)
}

// Close releases mount-layer caches and writeback workers.
func (h *BucketWebDAVHandler) Close() error {
	if h == nil || h.access == nil {
		return nil
	}
	return h.access.close()
}
