// Current-file transfer progress keeps directory upload details out of the main monitor.
package s3

import "time"

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
	task.updatedAt = time.Now()
}

func AdvanceTransfer(id string, delta int64) {
	advanceTransfer(id, delta)
}

// AdvanceTransferCurrentFile advances total progress and the visible current file
// only while the supplied key is still the task's current file.
func AdvanceTransferCurrentFile(id, key string, delta int64) {
	advanceTransferForCurrentFile(id, key, delta)
}

func advanceTransferForCurrentFile(id, key string, delta int64) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.BytesCompleted += delta
	if task.snapshot.CurrentFileKey == key && task.snapshot.CurrentFileTotalBytes > 0 {
		task.snapshot.CurrentFileBytesCompleted += delta
		if task.snapshot.CurrentFileBytesCompleted > task.snapshot.CurrentFileTotalBytes {
			task.snapshot.CurrentFileBytesCompleted = task.snapshot.CurrentFileTotalBytes
		}
	}
	task.updatedAt = time.Now()

	elapsed := task.updatedAt.Sub(task.startedAt).Seconds()
	if elapsed > 0 {
		task.snapshot.SpeedBytes = float64(task.snapshot.BytesCompleted) / elapsed
	}
}
