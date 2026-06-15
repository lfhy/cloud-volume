// WebDAV server lifecycle is kept separate from mount command execution.
package mount

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"golang.org/x/net/webdav"
)

type webDAVServer struct {
	server   *http.Server
	listener net.Listener
}

func startWebDAVServer(
	access *bucketAccess,
	volumeName string,
) (*webDAVServer, string, int, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, "", 0, fmt.Errorf("listen local webdav server: %w", err)
	}
	address := listener.Addr().(*net.TCPAddr)
	fs := &webDAVFS{access: access}
	scope := "/" + strings.Trim(volumeName, "/")
	handler := &webdav.Handler{
		Prefix:     scope,
		FileSystem: fs,
		LockSystem: webdav.NewMemLS(),
	}
	server := &http.Server{
		Handler:           webDAVLoggingHandler{next: handler},
		ReadHeaderTimeout: 5 * time.Second,
	}
	instance := &webDAVServer{
		server:   server,
		listener: listener,
	}
	go func() {
		_ = server.Serve(listener)
	}()
	return instance, scopedServerURL(address.Port, scope), address.Port, nil
}

func (s *webDAVServer) stop() error {
	if s == nil || s.server == nil {
		return nil
	}
	if s.listener != nil {
		_ = s.listener.Close()
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	err := s.server.Shutdown(ctx)
	if err == context.DeadlineExceeded {
		_ = s.server.Close()
		return nil
	}
	return err
}

func scopedServerURL(port int, scope string) string {
	return (&url.URL{
		Scheme: "http",
		Host:   fmt.Sprintf("127.0.0.1:%d", port),
		Path:   ensureDirSuffix(strings.Trim(scope, "/")),
	}).String()
}
