// Current-file transfer progress keeps directory upload details out of the main monitor.
package s3

import (
	"fmt"
	"time"
)

// SetTransferCurrentFile resets the per-file progress nested under a directory task.
func SetTransferCurrentFile(id, key string, totalBytes int64) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.CurrentFileKey = key
	task.snapshot.CurrentFileTotalBytes = totalBytes
	task.snapshot.CurrentFileBytesCompleted = 0
	task.snapshot.CurrentRange = ""
	task.snapshot.CurrentPart = 0
	task.snapshot.TotalParts = 0
	task.updatedAt = time.Now()
}

// SetTransferCurrentPart publishes structured multipart progress for task UIs.
func SetTransferCurrentPart(id, key string, part, total int32, offset, size int64) {
	if size < 0 || offset < 0 {
		return
	}
	SetTransferCurrentFile(id, key, size)
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	if task, ok := globalTransferMonitor.tasks[id]; ok {
		end := offset
		if size > 0 {
			end += size - 1
		}
		task.snapshot.CurrentRange = fmt.Sprintf("bytes=%d-%d", offset, end)
		task.snapshot.CurrentPart = part
		task.snapshot.TotalParts = total
		task.updatedAt = time.Now()
	}
}

func AdvanceTransfer(id string, delta int64) {
	advanceTransfer(id, delta)
}

// SeedTransferProgress restores already persisted bytes without counting them
// toward this attempt's throughput measurement.
func SeedTransferProgress(id string, bytes int64) {
	if bytes <= 0 {
		return
	}
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	if task, ok := globalTransferMonitor.tasks[id]; ok {
		task.snapshot.BytesCompleted += bytes
		task.updatedAt = time.Now()
	}
}

// AdvanceTransferCurrentFile advances total progress and the visible current file
// only while the supplied key is still the task's current file.
func AdvanceTransferCurrentFile(id, key string, delta int64) {
	advanceTransferForCurrentFile(id, key, delta)
}

// AdvanceTransferCurrentPart advances aggregate bytes and only the displayed
// multipart slot, avoiding concurrent parts corrupting its per-part counter.
func AdvanceTransferCurrentPart(id string, part int32, delta int64) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	advanceTransferLocked(task, delta)
	if task.snapshot.CurrentPart == part && task.snapshot.CurrentFileTotalBytes > 0 {
		task.snapshot.CurrentFileBytesCompleted += delta
		if task.snapshot.CurrentFileBytesCompleted > task.snapshot.CurrentFileTotalBytes {
			task.snapshot.CurrentFileBytesCompleted = task.snapshot.CurrentFileTotalBytes
		}
	}
}

func advanceTransferForCurrentFile(id, key string, delta int64) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	advanceTransferLocked(task, delta)
	if task.snapshot.CurrentFileKey == key && task.snapshot.CurrentFileTotalBytes > 0 {
		task.snapshot.CurrentFileBytesCompleted += delta
		if task.snapshot.CurrentFileBytesCompleted > task.snapshot.CurrentFileTotalBytes {
			task.snapshot.CurrentFileBytesCompleted = task.snapshot.CurrentFileTotalBytes
		}
	}
}

func advanceTransferLocked(task *transferState, delta int64) {
	task.snapshot.BytesCompleted += delta
	task.transferredBytes += delta
	task.updatedAt = time.Now()
	elapsed := task.updatedAt.Sub(task.startedAt).Seconds()
	if elapsed > 0 {
		task.snapshot.SpeedBytes = float64(task.transferredBytes) / elapsed
	}
}
