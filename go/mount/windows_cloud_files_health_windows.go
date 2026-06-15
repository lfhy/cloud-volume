//go:build windows && cgo

// Cloud Files health probes verify the sync root is still writable before the UI trusts it.
package mount

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

const (
	windowsCloudFilesHealthProbeDir  = ".cloud-volume"
	windowsCloudFilesHealthProbeFile = "write-probe.txt"
	windowsCloudFilesHealthTimeout   = 6 * time.Second
	windowsCloudFilesHealthCacheTTL  = 5 * time.Second
)

func windowsCloudFilesWriteProbe(rootPath string) error {
	probeDir := filepath.Join(rootPath, windowsCloudFilesHealthProbeDir)
	probeFile := filepath.Join(probeDir, windowsCloudFilesHealthProbeFile)
	ctx, cancel := context.WithTimeout(
		context.Background(),
		windowsCloudFilesHealthTimeout,
	)
	defer cancel()

	var lastErr error
	for {
		lastErr = windowsCloudFilesWriteProbeOnce(probeDir, probeFile)
		if lastErr == nil {
			return nil
		}
		select {
		case <-ctx.Done():
			if ctx.Err() == context.DeadlineExceeded {
				return fmt.Errorf(
					"write probe timed out after %s: %w",
					windowsCloudFilesHealthTimeout,
					lastErr,
				)
			}
			return lastErr
		case <-time.After(200 * time.Millisecond):
		}
	}
}

func windowsCloudFilesWriteProbeOnce(probeDir, probeFile string) error {
	if err := os.MkdirAll(probeDir, 0o755); err != nil {
		return fmt.Errorf("create probe dir: %w", err)
	}
	if err := os.WriteFile(probeFile, []byte("probe"), 0o644); err != nil {
		return fmt.Errorf("write probe file: %w", err)
	}
	_ = os.Remove(probeFile)
	_ = os.Remove(probeDir)
	return nil
}
