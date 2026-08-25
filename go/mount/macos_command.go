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
	// LaunchServices helpers may leave descendants holding the output pipes.
	// Bound that post-cancel wait so a five-second command cannot block for a minute.
	cmd.WaitDelay = 500 * time.Millisecond
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

// runLoggedCommandUntilSuccess lets mount startup finish as soon as an
// independent system probe confirms that the command already took effect.
// CommandContext still reaps the command in the background after cancellation.
func runLoggedCommandUntilSuccess(
	timeout time.Duration,
	probeInterval time.Duration,
	phase string,
	probe func() (string, bool),
	name string,
	args ...string,
) ([]byte, string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	startedAt := time.Now()
	log.Printf(
		"[mount/macos] %s start cmd=%q args=%q timeout=%s",
		phase,
		name,
		args,
		timeout,
	)
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.WaitDelay = 500 * time.Millisecond
	type commandResult struct {
		output []byte
		err    error
	}
	done := make(chan commandResult, 1)
	go func() {
		output, err := cmd.CombinedOutput()
		done <- commandResult{output: output, err: err}
	}()

	ticker := time.NewTicker(probeInterval)
	defer ticker.Stop()
	for {
		select {
		case result := <-done:
			cancel()
			if ctx.Err() == context.DeadlineExceeded {
				duration := time.Since(startedAt).Round(time.Millisecond)
				log.Printf(
					"[mount/macos] %s timeout duration=%s output=%q",
					phase,
					duration,
					strings.TrimSpace(string(result.output)),
				)
				return result.output, "", fmt.Errorf("%s timed out after %s", phase, timeout)
			}
			if result.err != nil {
				return result.output, "", result.err
			}
			return result.output, "", nil
		case <-ctx.Done():
			duration := time.Since(startedAt).Round(time.Millisecond)
			log.Printf("[mount/macos] %s timeout duration=%s", phase, duration)
			return nil, "", fmt.Errorf("%s timed out after %s", phase, timeout)
		case <-ticker.C:
			if recovered, ok := probe(); ok {
				duration := time.Since(startedAt).Round(time.Millisecond)
				log.Printf(
					"[mount/macos] %s confirmed duration=%s result=%q",
					phase,
					duration,
					recovered,
				)
				cancel()
				return nil, recovered, nil
			}
		}
	}
}

func shouldLogMacOSCommandSuccess(phase string) bool {
	switch phase {
	case "probe-webdav-mounts", "list-webdav-mounts":
		return false
	default:
		return true
	}
}
