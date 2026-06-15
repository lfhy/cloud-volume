// Auth endpoints validate configured WebDAV credentials before issuing cookies.
package webapi

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func (s *Server) handleAuthSession(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, fmt.Errorf("method not allowed"))
		return
	}
	config, err := loadCurrentConfig()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !isWebConfigured(config) {
		writeSuccess(w, map[string]any{
			"authenticated": false,
			"loginRequired": false,
		})
		return
	}
	if s.authenticated(r) {
		writeSuccess(w, map[string]any{
			"authenticated": true,
			"loginRequired": true,
		})
		return
	}
	writeError(w, http.StatusUnauthorized, fmt.Errorf("login required"))
}

func (s *Server) handleAuthLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, fmt.Errorf("method not allowed"))
		return
	}
	config, err := loadCurrentConfig()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !config.HasWebDAVCredentials() {
		writeError(w, http.StatusBadRequest, fmt.Errorf("WebDAV 账号密码尚未配置"))
		return
	}
	var request loginRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, fmt.Errorf("invalid login payload"))
		return
	}
	if strings.TrimSpace(request.Username) != config.WebDAVUsername ||
		request.Password != config.WebDAVPassword {
		writeError(w, http.StatusUnauthorized, fmt.Errorf("WebDAV 账号或密码错误"))
		return
	}
	if err := s.establishSession(w, r); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeSuccess(w, map[string]any{"authenticated": true})
}

func (s *Server) handleAuthLogout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, fmt.Errorf("method not allowed"))
		return
	}
	s.sessions.Delete(s.sessionToken(r))
	s.clearSessionCookie(w, r)
	writeSuccess(w, map[string]any{"ok": true})
}
