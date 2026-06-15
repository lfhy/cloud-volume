// Upload and download endpoints expose browser-friendly transfer primitives.
package webapi

import (
	"fmt"
	"net/http"
	"strings"

	storageops "remote-storage/go/storage"
)

func (s *Server) handleUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, fmt.Errorf("method not allowed"))
		return
	}
	if !s.authenticated(r) {
		writeError(w, http.StatusUnauthorized, fmt.Errorf("login required"))
		return
	}
	config, err := requireConfiguredStorage()
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	bucket := strings.TrimSpace(r.URL.Query().Get("bucket"))
	key := strings.Trim(strings.TrimSpace(r.URL.Query().Get("key")), "/")
	taskID := strings.TrimSpace(r.URL.Query().Get("taskId"))
	if bucket == "" || key == "" {
		writeError(w, http.StatusBadRequest, fmt.Errorf("bucket and key are required"))
		return
	}
	if err := r.ParseMultipartForm(64 << 20); err != nil {
		writeError(w, http.StatusBadRequest, fmt.Errorf("invalid upload form"))
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, fmt.Errorf("missing upload file"))
		return
	}
	defer file.Close()
	if err := storageops.ForConfig(config).UploadReader(
		r.Context(),
		bucket,
		key,
		file,
		header.Size,
		taskID,
		header.Filename,
	); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeSuccess(w, map[string]any{"ok": true})
}

func (s *Server) handleDownload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, fmt.Errorf("method not allowed"))
		return
	}
	if !s.authenticated(r) {
		writeError(w, http.StatusUnauthorized, fmt.Errorf("login required"))
		return
	}
	config, err := requireConfiguredStorage()
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	bucket := strings.TrimSpace(r.URL.Query().Get("bucket"))
	key := strings.Trim(strings.TrimSpace(r.URL.Query().Get("key")), "/")
	if bucket == "" || key == "" {
		writeError(w, http.StatusBadRequest, fmt.Errorf("bucket and key are required"))
		return
	}
	inline := r.URL.Query().Get("inline") == "1"
	if err := storageops.ForConfig(config).StreamObjectToHTTP(r.Context(), bucket, key, inline, w); err != nil {
		writeError(w, http.StatusInternalServerError, err)
	}
}
