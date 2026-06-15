//go:build windows

// Windows WebDAV backend preserves the mapped-drive fallback for compatibility testing.
package mount

import "fmt"

type windowsWebDAVBackend struct{}

func (b *windowsWebDAVBackend) Initialize(session *mountSession) error {
	session.mountName = managedMountPrefix + session.bucket
	session.mountPath = ""
	session.mountTarget = ""
	return nil
}

func (b *windowsWebDAVBackend) Start(session *mountSession) error {
	server, serverURL, port, err := startWebDAVServer(session.access, session.mountName)
	if err != nil {
		return err
	}
	session.server = server
	session.serverURL = serverURL
	session.port = port

	mountPath, err := mountWebDAVOnWindows(serverURL)
	if err != nil {
		session.lastError = err.Error()
		return err
	}
	session.mountPath = mountPath
	session.mountTarget = mountPath
	session.mounted = true
	return nil
}

func (b *windowsWebDAVBackend) Stop(session *mountSession) error {
	var mountErr error
	if session.mounted && session.mountTarget != "" {
		if active, err := isWindowsWebDAVMountActive(session.mountTarget); err != nil {
			mountErr = err
		} else if active {
			mountErr = unmountWebDAVOnWindows(session.mountTarget)
		}
		session.mounted = false
	}

	serverErr := error(nil)
	if session.server != nil {
		serverErr = session.server.stop()
	}
	accessErr := error(nil)
	if session.access != nil {
		accessErr = session.access.close()
	}

	switch {
	case mountErr != nil:
		session.lastError = mountErr.Error()
		return mountErr
	case serverErr != nil:
		session.lastError = serverErr.Error()
		return serverErr
	case accessErr != nil:
		session.lastError = accessErr.Error()
		return accessErr
	default:
		return nil
	}
}

func (b *windowsWebDAVBackend) IsActive(session *mountSession) (bool, error) {
	return isWindowsWebDAVMountActive(session.mountTarget)
}

func (b *windowsWebDAVBackend) CleanupStale(session *mountSession) error {
	_ = session
	return cleanupManagedWindowsWebDAVMounts()
}

func ensureWindowsMountPath(path string) error {
	if path == "" {
		return fmt.Errorf("mount path is required")
	}
	return nil
}
