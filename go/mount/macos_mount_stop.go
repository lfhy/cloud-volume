//go:build darwin

// macOS stop handling drains durable writes before disconnecting WebDAV.
package mount

import (
	"context"
	"fmt"
	"log"
	"time"
)

// drainMacOSWriteback is an injectable lifecycle seam for the platform-free
// stop tests; production uses the queue's cancellation-aware drain directly.
var drainMacOSWriteback = func(ctx context.Context, access *bucketAccess) error {
	return access.drainWritebackContext(ctx)
}

func (s *mountSession) stop() error {
	log.Printf(
		"[mount/session] stop bucket=%q mounted=%t target=%q",
		s.bucket,
		s.mounted,
		s.mountTarget,
	)
	if s.mounted {
		if err := s.drainWritebackBeforeUnmount(); err != nil {
			return s.keepWebDAVMountAfterStopError("drain", err)
		}
	}

	var mountErr error
	if s.mounted && s.mountTarget != "" {
		active, err := probeWebDAVMountActive(s.mountTarget)
		if err != nil {
			mountErr = err
		} else if active {
			mountErr = executeUnmountWebDAV(s.mountTarget)
		}
		if mountErr != nil {
			return s.keepWebDAVMountAfterStopError("unmount", mountErr)
		}
		s.mounted = false
	}

	var serverErr error
	if s.server != nil {
		log.Printf("[mount/session] stop-webdav bucket=%q", s.bucket)
		serverErr = s.server.stop()
		s.server = nil
	}
	var accessErr error
	if s.access != nil {
		log.Printf("[mount/session] close-access bucket=%q", s.bucket)
		accessErr = s.access.close()
		s.access = nil
	}
	if serverErr != nil {
		s.lastError = serverErr.Error()
		return serverErr
	}
	if accessErr != nil {
		s.lastError = accessErr.Error()
		return accessErr
	}
	log.Printf("[mount/session] stop-done bucket=%q", s.bucket)
	return nil
}

func (s *mountSession) drainWritebackBeforeUnmount() error {
	if s.access == nil || s.access.writeback == nil {
		return nil
	}
	timeout := s.access.transferTimeout
	if timeout <= 0 {
		timeout = defaultTransferTimeout * time.Second
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	log.Printf("[mount/session] drain-start bucket=%q timeout=%s", s.bucket, timeout)
	err := drainMacOSWriteback(ctx, s.access)
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("等待挂载写回超过 %s；挂载保持连接，请重试卸载", timeout)
	}
	if err != nil {
		return fmt.Errorf("挂载写回未完成；挂载保持连接，请重试卸载: %w", err)
	}
	log.Printf("[mount/session] drain-done bucket=%q", s.bucket)
	return nil
}

func (s *mountSession) keepWebDAVMountAfterStopError(phase string, err error) error {
	s.lastError = err.Error()
	s.stopping = false
	log.Printf(
		"[mount/session] keep-webdav-after-%s-error bucket=%q err=%v",
		phase,
		s.bucket,
		err,
	)
	return err
}
