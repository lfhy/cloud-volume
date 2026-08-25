// Transfer monitor tests lock down cancellation state transitions.

package s3

import (
	"context"
	"testing"
	"time"
)

func TestCancelTransferBeforeStartCancelsOnRegistration(t *testing.T) {
	resetTransferMonitorForTest()

	if ok := CancelTransfer("task-pre-cancel"); !ok {
		t.Fatalf("expected pending cancel to be accepted")
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	startTransfer(
		"task-pre-cancel",
		"upload",
		"bucket-a",
		"folder/demo.txt",
		"/tmp/demo.txt",
		128,
		cancel,
	)

	snapshots := ListTransferSnapshots()
	if len(snapshots) != 1 {
		t.Fatalf("expected 1 snapshot, got %d", len(snapshots))
	}
	if snapshots[0].Status != "canceled" {
		t.Fatalf("expected canceled status, got %q", snapshots[0].Status)
	}
	if ctx.Err() != context.Canceled {
		t.Fatalf("expected context to be canceled, got %v", ctx.Err())
	}
}

func TestQueuedCancellationStaysTerminalWhenProviderStarts(t *testing.T) {
	resetTransferMonitorForTest()
	QueueTransfer("task-queued-cancel", "move", "bucket-a", "old.txt", "", 0)
	SetTransferProfile("task-queued-cancel", "profile-a")
	SetTransferTarget("task-queued-cancel", "new.txt")
	if ok := CancelTransfer("task-queued-cancel"); !ok {
		t.Fatal("expected queued cancellation to be accepted")
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	startTransfer("task-queued-cancel", "move", "bucket-a", "old.txt", "", 0, cancel)

	snapshot, ok := GetTransferSnapshot("task-queued-cancel")
	if !ok || snapshot.Status != "canceled" || snapshot.ProfileID != "profile-a" ||
		snapshot.TargetPath != "new.txt" {
		t.Fatalf("queued cancellation snapshot = %#v", snapshot)
	}
	if ctx.Err() != context.Canceled {
		t.Fatalf("provider context = %v, want canceled", ctx.Err())
	}
}

func TestTransferCanBecomeNonCancelableBeforeTerminalState(t *testing.T) {
	resetTransferMonitorForTest()
	startTransfer("task-install", "app_update", "", "CloudVolume.dmg", "", 0, nil)
	SetTransferCancelable("task-install", false)

	if ok := CancelTransfer("task-install"); ok {
		t.Fatal("non-cancelable transfer accepted cancellation")
	}
	snapshot, ok := GetTransferSnapshot("task-install")
	if !ok || snapshot.Status != "running" || snapshot.Cancelable {
		t.Fatalf("installer snapshot = %#v", snapshot)
	}
}

func TestNestedTransferLifecycleWaitsForOuterOwner(t *testing.T) {
	resetTransferMonitorForTest()
	startTransfer("task-nested", "move", "bucket-a", "old.txt", "", 0, nil)
	startTransfer("task-nested", "copy", "bucket-a", "old.txt", "", 0, nil)

	finishTransfer("task-nested", nil)
	snapshot, ok := GetTransferSnapshot("task-nested")
	if !ok || snapshot.Status != "running" {
		t.Fatalf("nested completion ended outer task: %#v", snapshot)
	}
	finishTransfer("task-nested", nil)
	snapshot, ok = GetTransferSnapshot("task-nested")
	if !ok || snapshot.Status != "done" {
		t.Fatalf("outer completion snapshot = %#v", snapshot)
	}
}

func TestFinishTransferMapsContextCanceledToCanceledStatus(t *testing.T) {
	resetTransferMonitorForTest()

	ctx, cancel := context.WithCancel(context.Background())
	startTransfer(
		"task-runtime-cancel",
		"download",
		"bucket-b",
		"movie.mp4",
		"/tmp/movie.mp4",
		0,
		cancel,
	)
	cancel()
	finishTransfer("task-runtime-cancel", ctx.Err())

	snapshots := ListTransferSnapshots()
	if len(snapshots) != 1 {
		t.Fatalf("expected 1 snapshot, got %d", len(snapshots))
	}
	if snapshots[0].Status != "canceled" {
		t.Fatalf("expected canceled status, got %q", snapshots[0].Status)
	}
}

func TestTransferLifecycleUsesKindPhaseAndKeepsSeedOutOfSpeed(t *testing.T) {
	resetTransferMonitorForTest()
	startTransfer("task-download", "download", "bucket", "movie.mp4", "/tmp/movie.mp4", 100, nil)
	globalTransferMonitor.mu.Lock()
	globalTransferMonitor.tasks["task-download"].startedAt = time.Now().Add(-time.Second)
	globalTransferMonitor.mu.Unlock()
	SeedTransferProgress("task-download", 80)
	AdvanceTransfer("task-download", 5)

	snapshot, ok := GetTransferSnapshot("task-download")
	if !ok {
		t.Fatal("missing snapshot")
	}
	if snapshot.StatusDetail != "downloading" {
		t.Fatalf("phase = %q, want downloading", snapshot.StatusDetail)
	}
	if snapshot.BytesCompleted != 85 {
		t.Fatalf("bytes = %d, want 85", snapshot.BytesCompleted)
	}
	if snapshot.SpeedBytes > 20 {
		t.Fatalf("seeded bytes leaked into speed: %f", snapshot.SpeedBytes)
	}
}

func TestCurrentMultipartPartCarriesRange(t *testing.T) {
	resetTransferMonitorForTest()
	startTransfer("task-part", "upload", "bucket", "large.bin", "", 20, nil)
	SetTransferCurrentPart("task-part", "large.bin", 2, 3, 8, 8)
	AdvanceTransferCurrentPart("task-part", 2, 3)

	snapshot, ok := GetTransferSnapshot("task-part")
	if !ok {
		t.Fatal("missing snapshot")
	}
	if snapshot.CurrentPart != 2 || snapshot.TotalParts != 3 || snapshot.CurrentRange != "bytes=8-15" {
		t.Fatalf("part display = %#v", snapshot)
	}
	if snapshot.CurrentFileBytesCompleted != 3 {
		t.Fatalf("part bytes = %d, want 3", snapshot.CurrentFileBytesCompleted)
	}
}

func resetTransferMonitorForTest() {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	globalTransferMonitor.tasks = map[string]*transferState{}
	globalTransferMonitor.pendingCancels = map[string]time.Time{}
}
