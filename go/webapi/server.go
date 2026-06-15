// HTTP server wiring keeps API, WebDAV, and static asset serving under one entrypoint.
package webapi

import (
	"encoding/json"
	"io/fs"
	"net/http"
	"strings"
	"time"
)

const sessionCookieName = "remote_storage_token"

type responsePayload struct {
	Ok     bool           `json:"ok"`
	Result any            `json:"result,omitempty"`
	Error  *responseError `json:"error,omitempty"`
}

type responseError struct {
	Message string `json:"message"`
}

// Options controls how the web server exposes static assets.
type Options struct {
	StaticRoot string
	StaticFS   fs.FS
}

// Server owns browser auth state plus cached WebDAV handlers.
type Server struct {
	staticRoot string
	staticFS   fs.FS
	sessions   *sessionStore
	webdav     *webDAVService
}

func NewServer(options Options) *Server {
	return &Server{
		staticRoot: strings.TrimSpace(options.StaticRoot),
		staticFS:   options.StaticFS,
		sessions:   newSessionStore(),
		webdav:     newWebDAVService(),
	}
}

func (s *Server) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasPrefix(r.URL.Path, "/api/invoke/"):
			s.handleInvoke(w, r)
		case r.URL.Path == "/api/auth/session":
			s.handleAuthSession(w, r)
		case r.URL.Path == "/api/auth/login":
			s.handleAuthLogin(w, r)
		case r.URL.Path == "/api/auth/logout":
			s.handleAuthLogout(w, r)
		case r.URL.Path == "/api/upload":
			s.handleUpload(w, r)
		case r.URL.Path == "/api/download":
			s.handleDownload(w, r)
		case strings.HasPrefix(r.URL.Path, "/webdav/"):
			s.handleWebDAV(w, r)
		default:
			s.handleStatic(w, r)
		}
	})
}

func (s *Server) Close() error {
	return s.webdav.Reset()
}

func writeSuccess(w http.ResponseWriter, result any) {
	writeJSON(w, http.StatusOK, responsePayload{Ok: true, Result: result})
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, responsePayload{
		Ok: false,
		Error: &responseError{
			Message: err.Error(),
		},
	})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func (s *Server) sessionToken(r *http.Request) string {
	cookie, err := r.Cookie(sessionCookieName)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(cookie.Value)
}

func (s *Server) authenticated(r *http.Request) bool {
	return s.sessions.Valid(s.sessionToken(r))
}

func (s *Server) setSessionCookie(
	w http.ResponseWriter,
	r *http.Request,
	token string,
	expiresAt time.Time,
) {
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookieName,
		Value:    token,
		Path:     "/",
		Expires:  expiresAt,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Secure:   r.TLS != nil,
	})
}

func (s *Server) clearSessionCookie(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookieName,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Secure:   r.TLS != nil,
	})
}
