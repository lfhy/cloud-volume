// Config-backup queue tests cover debounce coalescing and writes during upload.
package main

import (
	"context"
	"runtime"
	"sync/atomic"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
	configbackup "remote-storage/go/configbackup"
)

func TestAutomaticConfigBackupCoalescesWritesDuringDebounce(t *testing.T) {
	prepareAutomaticConfigBackupTest(t)
	automaticConfigBackupDelay = 50 * time.Millisecond

	started := make(chan struct{})
	var calls atomic.Int32
	backupConfigSnapshot = func(context.Context) (configbackup.Snapshot, error) {
		if calls.Add(1) == 1 {
			close(started)
		}
		return configbackup.Snapshot{}, nil
	}

	queueAutomaticConfigBackup()
	queueAutomaticConfigBackup()
	awaitSignal(t, started, "first automatic backup")
	time.Sleep(100 * time.Millisecond)
	if got := calls.Load(); got != 1 {
		t.Fatalf("automatic backup calls = %d, want debounce to coalesce to 1", got)
	}
}

func TestAutomaticConfigBackupRerunsAfterWriteDuringUpload(t *testing.T) {
	prepareAutomaticConfigBackupTest(t)
	automaticConfigBackupDelay = 0

	started := make(chan struct{})
	release := make(chan struct{})
	var calls atomic.Int32
	backupConfigSnapshot = func(context.Context) (configbackup.Snapshot, error) {
		if calls.Add(1) == 1 {
			close(started)
			<-release
		}
		return configbackup.Snapshot{}, nil
	}

	queueAutomaticConfigBackup()
	awaitSignal(t, started, "first automatic backup upload")
	// This represents the profile write performed after an OAuth token refresh.
	queueAutomaticConfigBackup()
	close(release)
	awaitBackupCalls(t, &calls, 2)
}

func prepareAutomaticConfigBackupTest(t *testing.T) {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	if runtime.GOOS == "windows" {
		t.Setenv("USERPROFILE", home)
	}
	if err := storageconfig.SaveConfigBackupSettings(
		storageconfig.ConfigBackupSettings{Enabled: true},
	); err != nil {
		t.Fatalf("enable automatic backup: %v", err)
	}

	automaticConfigBackup.Lock()
	if automaticConfigBackup.pending {
		automaticConfigBackup.Unlock()
		t.Fatal("automatic backup queue was still pending before test")
	}
	automaticConfigBackup.uploading = false
	automaticConfigBackup.rerun = false
	automaticConfigBackup.Unlock()
	previousDelay := automaticConfigBackupDelay
	previousBackup := backupConfigSnapshot
	t.Cleanup(func() {
		awaitAutomaticBackupIdle(t)
		automaticConfigBackupDelay = previousDelay
		backupConfigSnapshot = previousBackup
	})
}

func awaitSignal(t *testing.T, signal <-chan struct{}, description string) {
	t.Helper()
	select {
	case <-signal:
	case <-time.After(time.Second):
		t.Fatalf("timed out waiting for %s", description)
	}
}

func awaitBackupCalls(t *testing.T, calls *atomic.Int32, want int32) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for calls.Load() < want && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if got := calls.Load(); got != want {
		t.Fatalf("automatic backup calls = %d, want %d", got, want)
	}
}

func awaitAutomaticBackupIdle(t *testing.T) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		automaticConfigBackup.Lock()
		pending := automaticConfigBackup.pending
		automaticConfigBackup.Unlock()
		if !pending {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("automatic backup queue did not become idle")
}
