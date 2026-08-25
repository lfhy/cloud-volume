// Transfer lifecycle registration keeps queued and active task state coherent.
package s3

import (
	"context"
	"time"
)

func startTransfer(id, kind, bucket, key, localPath string, totalBytes int64, cancel context.CancelFunc) {
	now := time.Now()
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	if existing, ok := globalTransferMonitor.tasks[id]; ok && existing.snapshot.Status == "running" {
		// A mount queue can own a task while an S3 helper reports its nested
		// provider phase. Keep one snapshot alive until both owners finish.
		existing.activeOwners++
		existing.updatedAt = now
		return
	}
	profileID, targetPath, createdAt := "", "", now.Format(time.RFC3339)
	wasCanceled := false
	if existing, ok := globalTransferMonitor.tasks[id]; ok {
		profileID = existing.snapshot.ProfileID
		targetPath = existing.snapshot.TargetPath
		if existing.snapshot.CreatedAt != "" {
			createdAt = existing.snapshot.CreatedAt
		}
		// A user may cancel between the pending snapshot and the provider call.
		// Keep that cancellation terminal instead of resurrecting the operation.
		wasCanceled = existing.snapshot.Status == "canceled" || existing.snapshot.Status == "cancelled"
	}
	task := &transferState{
		snapshot: TransferSnapshot{
			ID: id, Type: kind, ProfileID: profileID, Bucket: bucket, Key: key,
			LocalPath: localPath, Status: "running", StatusDetail: runningTransferDetail(kind),
			TargetPath: targetPath, CreatedAt: createdAt, TotalBytes: totalBytes, Cancelable: true,
		},
		startedAt: now, updatedAt: now, cancel: cancel, activeOwners: 1,
	}
	globalTransferMonitor.tasks[id] = task
	if _, canceled := globalTransferMonitor.pendingCancels[id]; canceled || wasCanceled {
		delete(globalTransferMonitor.pendingCancels, id)
		task.snapshot.Status = "canceled"
		task.snapshot.Cancelable = false
		if cancel != nil {
			cancel()
		}
	}
}

// QueueTransfer registers a pending task before bytes start moving.
func QueueTransfer(id, kind, bucket, key, localPath string, totalBytes int64) {
	now := time.Now()
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		globalTransferMonitor.tasks[id] = &transferState{snapshot: TransferSnapshot{
			ID: id, Type: kind, Bucket: bucket, Key: key, LocalPath: localPath,
			Status: "pending", StatusDetail: "queued", CreatedAt: now.Format(time.RFC3339),
			TotalBytes: totalBytes, Cancelable: true,
		}, startedAt: now, updatedAt: now}
		return
	}
	task.snapshot.Type, task.snapshot.Bucket = kind, bucket
	task.snapshot.Key, task.snapshot.LocalPath = key, localPath
	task.snapshot.TotalBytes, task.snapshot.BytesCompleted = totalBytes, 0
	task.snapshot.Status, task.snapshot.StatusDetail = "pending", "queued"
	task.snapshot.Error, task.snapshot.SpeedBytes, task.snapshot.Cancelable = "", 0, true
	task.snapshot.TargetPath = ""
	task.snapshot.CurrentFileKey = ""
	task.snapshot.CurrentFileBytesCompleted = 0
	task.snapshot.CurrentFileTotalBytes = 0
	task.snapshot.CurrentRange = ""
	task.snapshot.CurrentPart = 0
	task.snapshot.TotalParts = 0
	task.cancel = nil
	task.activeOwners = 0
	task.transferredBytes = 0
	task.updatedAt = now
}

// SetTransferProfile associates a physical snapshot with its durable profile.
func SetTransferProfile(id, profileID string) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	if task, ok := globalTransferMonitor.tasks[id]; ok {
		task.snapshot.ProfileID = profileID
		task.updatedAt = time.Now()
	}
}

// SetTransferStatusDetail refines a task phase without changing its status.
func SetTransferStatusDetail(id, detail string) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	if task, ok := globalTransferMonitor.tasks[id]; ok {
		task.snapshot.StatusDetail = detail
		task.updatedAt = time.Now()
	}
}

// SetTransferCancelable exposes operations, such as installer replacement, that cannot stop safely.
func SetTransferCancelable(id string, cancelable bool) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	if task, ok := globalTransferMonitor.tasks[id]; ok {
		task.snapshot.Cancelable = cancelable
		task.updatedAt = time.Now()
	}
}

// StartQueuedTransfer switches a previously queued task into the running state.
func StartQueuedTransfer(id, kind, bucket, key, localPath string, totalBytes int64, cancel context.CancelFunc) {
	startTransfer(id, kind, bucket, key, localPath, totalBytes, cancel)
}

// FinishQueuedTransfer finalizes a queued task after the remote operation completes.
func FinishQueuedTransfer(id string, err error) { finishTransfer(id, err) }

func runningTransferDetail(kind string) string {
	switch kind {
	case "download", "sync_download":
		return "downloading"
	case "delete", "sync_delete":
		return "deleting"
	case "move", "sync_rename":
		return "moving"
	case "copy":
		return "copying"
	case "app_update":
		return "preparing"
	default:
		return "uploading"
	}
}
