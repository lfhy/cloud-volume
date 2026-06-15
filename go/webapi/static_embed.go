// Embedded static serving allows single-binary CLI web builds.
package webapi

import (
	"bytes"
	"io"
	"io/fs"
	"mime"
	"net/http"
	"path"
	"strings"
	"time"
)

func (s *Server) handleStaticFS(w http.ResponseWriter, r *http.Request) {
	cleanPath := path.Clean(strings.TrimPrefix(r.URL.Path, "/"))
	if cleanPath == "." {
		cleanPath = "index.html"
	}
	if s.serveStaticFSFile(w, r, cleanPath) {
		return
	}
	if !s.serveStaticFSFile(w, r, "index.html") {
		http.Error(w, "embedded web build output was not found", http.StatusServiceUnavailable)
	}
}

func (s *Server) serveStaticFSFile(w http.ResponseWriter, r *http.Request, name string) bool {
	file, err := s.staticFS.Open(name)
	if err != nil {
		return false
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || info.IsDir() {
		return false
	}
	content, err := io.ReadAll(file)
	if err != nil {
		http.Error(w, "failed to read embedded web asset", http.StatusInternalServerError)
		return true
	}
	if contentType := mime.TypeByExtension(path.Ext(name)); contentType != "" {
		w.Header().Set("Content-Type", contentType)
	}
	http.ServeContent(w, r, name, embeddedModTime(info), bytes.NewReader(content))
	return true
}

func embeddedModTime(info fs.FileInfo) time.Time {
	if modified := info.ModTime(); !modified.IsZero() {
		return modified
	}
	return time.Unix(0, 0)
}
