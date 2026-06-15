// WebDAV routes require browser login and then hand off to per-bucket handlers.
package webapi

import (
	"fmt"
	"net/http"
	"strings"
)

func (s *Server) handleWebDAV(w http.ResponseWriter, r *http.Request) {
	config, err := requireConfiguredStorage()
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	username, password, ok := r.BasicAuth()
	if !ok ||
		strings.TrimSpace(username) != config.WebDAVUsername ||
		password != config.WebDAVPassword {
		w.Header().Set("WWW-Authenticate", `Basic realm="Remote Storage WebDAV"`)
		writeError(w, http.StatusUnauthorized, fmt.Errorf("invalid WebDAV credentials"))
		return
	}
	trimmedPath := strings.TrimPrefix(r.URL.Path, "/webdav/")
	parts := strings.SplitN(strings.Trim(trimmedPath, "/"), "/", 2)
	bucket := strings.TrimSpace(parts[0])
	if bucket == "" {
		writeError(w, http.StatusBadRequest, fmt.Errorf("missing bucket name"))
		return
	}
	handler, err := s.webdav.HandlerFor(config, bucket, "/webdav/"+bucket)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	handler.ServeHTTP(w, r)
}
