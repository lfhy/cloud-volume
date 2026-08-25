// WebDAV request logging focuses on trash-related Finder operations and failures.
package mount

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"path"
	"strings"
)

type webDAVLoggingHandler struct {
	next http.Handler
}

func (h webDAVLoggingHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// x/net/webdav passes the request context through to FileSystem.OpenFile.
	// Preserve the method so LOCK's missing-resource probe can be distinguished
	// from the identical O_RDWR|O_CREATE|O_TRUNC flags used by PUT.
	r = r.WithContext(context.WithValue(r.Context(), webDAVRequestMethodKey{}, r.Method))
	recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
	h.next.ServeHTTP(recorder, r)
	if shouldLogWebDAVRequest(r, recorder.status) {
		errorText := ""
		if recorder.lastWriteErr != nil {
			errorText = fmt.Sprintf(" error=%q", recorder.lastWriteErr.Error())
		}
		log.Printf(
			"[mount/webdav] method=%s path=%q destination=%q depth=%q overwrite=%q status=%d%s",
			r.Method,
			r.URL.Path,
			r.Header.Get("Destination"),
			r.Header.Get("Depth"),
			r.Header.Get("Overwrite"),
			recorder.status,
			errorText,
		)
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status       int
	lastWriteErr error
}

func (r *statusRecorder) WriteHeader(statusCode int) {
	r.status = statusCode
	r.ResponseWriter.WriteHeader(statusCode)
}

func (r *statusRecorder) Write(p []byte) (int, error) {
	count, err := r.ResponseWriter.Write(p)
	if err != nil {
		r.lastWriteErr = err
	}
	return count, err
}

func shouldLogWebDAVRequest(r *http.Request, status int) bool {
	if isExpectedProbeMiss(r, status) {
		return false
	}
	if status >= http.StatusBadRequest {
		return true
	}
	if shouldLogWebDAVRead(r, status) {
		return true
	}
	if isTrashLikePath(r.URL.Path) || isTrashLikePath(r.Header.Get("Destination")) {
		return true
	}
	switch r.Method {
	case http.MethodDelete, "MOVE":
		return true
	default:
		return false
	}
}

func isExpectedProbeMiss(r *http.Request, status int) bool {
	if r.Method != "PROPFIND" || status != http.StatusNotFound {
		return false
	}
	name := path.Base(strings.TrimSpace(r.URL.Path))
	if strings.HasPrefix(name, "._") {
		return true
	}
	switch name {
	case ".hidden",
		".metadata_direct_scope_only",
		".metadata_never_index",
		".metadata_never_index_unless_rootfs",
		".ql_disablecache",
		".ql_disablethumbnails",
		".Spotlight-V100",
		"Contents":
		return true
	default:
		return false
	}
}

func shouldLogWebDAVRead(r *http.Request, status int) bool {
	if status < 200 || status >= 400 {
		return false
	}
	if isExpectedProbeRead(r) {
		return true
	}
	switch r.Method {
	case http.MethodGet, http.MethodHead:
		return true
	default:
		return false
	}
}

func isExpectedProbeRead(r *http.Request) bool {
	name := path.Base(strings.TrimSpace(r.URL.Path))
	if strings.HasPrefix(name, ".") {
		return false
	}
	return strings.EqualFold(name, "Contents")
}

func isTrashLikePath(value string) bool {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return false
	}
	return strings.Contains(trimmed, "/.Trash") ||
		strings.HasPrefix(trimmed, ".Trash") ||
		strings.Contains(trimmed, "/.Trashes") ||
		strings.HasPrefix(trimmed, ".Trashes")
}
