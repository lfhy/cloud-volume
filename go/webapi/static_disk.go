// Disk-backed static serving keeps cmd/web compatible with build/web outputs.
package webapi

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

func (s *Server) handleStatic(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.NotFound(w, r)
		return
	}
	if s.staticFS != nil {
		s.handleStaticFS(w, r)
		return
	}
	if s.staticRoot == "" {
		http.Error(w, "web static root is not configured", http.StatusServiceUnavailable)
		return
	}
	cleanPath := filepath.Clean(strings.TrimPrefix(r.URL.Path, "/"))
	if cleanPath == "." {
		cleanPath = "index.html"
	}
	targetPath := filepath.Join(s.staticRoot, cleanPath)
	if info, err := os.Stat(targetPath); err == nil && !info.IsDir() {
		http.ServeFile(w, r, targetPath)
		return
	}
	indexPath := filepath.Join(s.staticRoot, "index.html")
	if _, err := os.Stat(indexPath); errors.Is(err, os.ErrNotExist) {
		http.Error(w, "web build output was not found", http.StatusServiceUnavailable)
		return
	}
	http.ServeFile(w, r, indexPath)
}
