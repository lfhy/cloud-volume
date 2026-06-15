//go:build darwin

// macOS command helpers wrap external utilities with timeout-bound logging.
package mount

import (
	"context"
	"fmt"
	"log"
	"os/exec"
	"strings"
	"time"
)

const (
	macosMountCommandTimeout   = 20 * time.Second
	macosUnmountCommandTimeout = 8 * time.Second
	macosProbeCommandTimeout   = 5 * time.Second
	macosOpenCommandTimeout    = 5 * time.Second
)

func runLoggedCommand(
	timeout time.Duration,
	phase string,
	name string,
	args ...string,
) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	startedAt := time.Now()
	if shouldLogMacOSCommandSuccess(phase) {
		log.Printf(
			"[mount/macos] %s start cmd=%q args=%q timeout=%s",
			phase,
			name,
			args,
			timeout,
		)
	}
	cmd := exec.CommandContext(ctx, name, args...)
	output, err := cmd.CombinedOutput()
	duration := time.Since(startedAt).Round(time.Millisecond)
	trimmedOutput := strings.TrimSpace(string(output))
	if ctx.Err() == context.DeadlineExceeded {
		log.Printf(
			"[mount/macos] %s timeout duration=%s output=%q",
			phase,
			duration,
			trimmedOutput,
		)
		return output, fmt.Errorf("%s timed out after %s", phase, timeout)
	}
	if err != nil {
		log.Printf(
			"[mount/macos] %s error duration=%s err=%v output=%q",
			phase,
			duration,
			err,
			trimmedOutput,
		)
		return output, err
	}
	if shouldLogMacOSCommandSuccess(phase) {
		log.Printf(
			"[mount/macos] %s done duration=%s output=%q",
			phase,
			duration,
			trimmedOutput,
		)
	}
	return output, nil
}

func shouldLogMacOSCommandSuccess(phase string) bool {
	switch phase {
	case "probe-webdav-mounts", "list-webdav-mounts":
		return false
	default:
		return true
	}
}
