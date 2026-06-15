// Transfer monitor: keeps short-lived object operation snapshots for Flutter.

package s3

import (
	"context"
	"errors"
	"io"
	"sort"
	"sync"
	"time"
)

// TransferSnapshot is polled by Flutter to render sidebar and transfers UI.
type TransferSnapshot struct {
	ID                        string  `json:"id"`
	Type                      string  `json:"type"`
	Bucket                    string  `json:"bucket"`
	Key                       string  `json:"key"`
	LocalPath                 string  `json:"localPath"`
	TargetPath                string  `json:"targetPath,omitempty"`
	Status                    string  `json:"status"`
	StatusDetail              string  `json:"statusDetail,omitempty"`
	CreatedAt                 string  `json:"createdAt,omitempty"`
	BytesCompleted            int64   `json:"bytesCompleted"`
	TotalBytes                int64   `json:"totalBytes"`
	ItemsCompleted            int64   `json:"itemsCompleted,omitempty"`
	TotalItems                int64   `json:"totalItems,omitempty"`
	CurrentFileKey            string  `json:"currentFileKey,omitempty"`
	CurrentFileBytesCompleted int64   `json:"currentFileBytesCompleted,omitempty"`
	CurrentFileTotalBytes     int64   `json:"currentFileTotalBytes,omitempty"`
	SpeedBytes                float64 `json:"speedBytes"`
	Error                     string  `json:"error,omitempty"`
}

type transferState struct {
	snapshot  TransferSnapshot
	startedAt time.Time
	updatedAt time.Time
	cancel    context.CancelFunc
}

type transferMonitor struct {
	mu             sync.Mutex
	tasks          map[string]*transferState
	pendingCancels map[string]time.Time
}

var globalTransferMonitor = &transferMonitor{
	tasks:          map[string]*transferState{},
	pendingCancels: map[string]time.Time{},
}

func startTransfer(
	id,
	kind,
	bucket,
	key,
	localPath string,
	totalBytes int64,
	cancel context.CancelFunc,
) {
	now := time.Now()
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	globalTransferMonitor.tasks[id] = &transferState{
		snapshot: TransferSnapshot{
			ID:           id,
			Type:         kind,
			Bucket:       bucket,
			Key:          key,
			LocalPath:    localPath,
			Status:       "running",
			StatusDetail: "uploading",
			CreatedAt:    now.Format(time.RFC3339),
			TotalBytes:   totalBytes,
		},
		startedAt: now,
		updatedAt: now,
		cancel:    cancel,
	}
	if _, ok := globalTransferMonitor.pendingCancels[id]; ok {
		delete(globalTransferMonitor.pendingCancels, id)
		globalTransferMonitor.tasks[id].snapshot.Status = "canceled"
		globalTransferMonitor.tasks[id].updatedAt = now
		if cancel != nil {
			cancel()
		}
	}
}

// QueueTransfer registers a pending task before bytes start moving.
func QueueTransfer(
	id,
	kind,
	bucket,
	key,
	localPath string,
	totalBytes int64,
) {
	now := time.Now()
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		globalTransferMonitor.tasks[id] = &transferState{
			snapshot: TransferSnapshot{
				ID:           id,
				Type:         kind,
				Bucket:       bucket,
				Key:          key,
				LocalPath:    localPath,
				Status:       "pending",
				StatusDetail: "queued",
				CreatedAt:    now.Format(time.RFC3339),
				TotalBytes:   totalBytes,
			},
			startedAt: now,
			updatedAt: now,
		}
		return
	}
	task.snapshot.Type = kind
	task.snapshot.Bucket = bucket
	task.snapshot.Key = key
	task.snapshot.LocalPath = localPath
	task.snapshot.TotalBytes = totalBytes
	task.snapshot.Status = "pending"
	task.snapshot.StatusDetail = "queued"
	task.snapshot.Error = ""
	task.snapshot.SpeedBytes = 0
	task.updatedAt = now
}

// SetTransferStatusDetail refines a task's current phase without changing its main status.
func SetTransferStatusDetail(id, detail string) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.StatusDetail = detail
	task.updatedAt = time.Now()
}

// StartQueuedTransfer switches a previously queued task into the running state.
func StartQueuedTransfer(
	id,
	kind,
	bucket,
	key,
	localPath string,
	totalBytes int64,
	cancel context.CancelFunc,
) {
	startTransfer(id, kind, bucket, key, localPath, totalBytes, cancel)
}

// FinishQueuedTransfer finalizes a queued task after the mount layer finishes the remote operation.
func FinishQueuedTransfer(id string, err error) {
	finishTransfer(id, err)
}

func setTransferTotal(id string, totalBytes int64) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.TotalBytes = totalBytes
	task.updatedAt = time.Now()
}

// AddTransferTotal grows a task's total work as directory scanning discovers files.
func AddTransferTotal(id string, deltaBytes int64) {
	if deltaBytes <= 0 {
		return
	}
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.TotalBytes += deltaBytes
	task.updatedAt = time.Now()
}

// AddTransferItems grows a task's item count as directory scanning discovers files.
func AddTransferItems(id string, deltaItems int64) {
	if deltaItems <= 0 {
		return
	}
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.TotalItems += deltaItems
	task.updatedAt = time.Now()
}

// AdvanceTransferItems increments the completed item count after file uploads finish.
func AdvanceTransferItems(id string, deltaItems int64) {
	if deltaItems <= 0 {
		return
	}
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.ItemsCompleted += deltaItems
	task.updatedAt = time.Now()
}

func setTransferTarget(id string, targetPath string) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.TargetPath = targetPath
	task.updatedAt = time.Now()
}

// SetTransferTarget updates the task subtitle target, such as a copy destination
// or the current byte range being streamed by a mounted WebDAV file.
func SetTransferTarget(id string, targetPath string) {
	setTransferTarget(id, targetPath)
}

func advanceTransfer(id string, delta int64) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.BytesCompleted += delta
	task.updatedAt = time.Now()

	elapsed := task.updatedAt.Sub(task.startedAt).Seconds()
	if elapsed > 0 {
		task.snapshot.SpeedBytes = float64(task.snapshot.BytesCompleted) / elapsed
	}
}

func finishTransfer(id string, err error) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.updatedAt = time.Now()
	task.cancel = nil
	task.snapshot.SpeedBytes = 0
	if task.snapshot.Status == "canceled" {
		task.snapshot.Error = ""
		return
	}
	if errors.Is(err, context.Canceled) {
		task.snapshot.Status = "canceled"
		task.snapshot.Error = ""
		return
	}
	if err != nil {
		task.snapshot.Status = "failed"
		task.snapshot.Error = err.Error()
		return
	}
	task.snapshot.Status = "done"
	if task.snapshot.TotalBytes > 0 && task.snapshot.StatusDetail != "mount_read" {
		task.snapshot.BytesCompleted = task.snapshot.TotalBytes
	}
}

// CancelTransfer stops an in-flight transfer when the task is still registered.
func CancelTransfer(id string) bool {
	globalTransferMonitor.mu.Lock()
	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		globalTransferMonitor.pendingCancels[id] = time.Now()
		globalTransferMonitor.mu.Unlock()
		return true
	}
	if task.snapshot.Status == "done" || task.snapshot.Status == "failed" {
		globalTransferMonitor.mu.Unlock()
		return false
	}
	cancel := task.cancel
	task.cancel = nil
	task.snapshot.Status = "canceled"
	task.snapshot.SpeedBytes = 0
	task.snapshot.Error = ""
	task.updatedAt = time.Now()
	globalTransferMonitor.mu.Unlock()

	if cancel != nil {
		cancel()
	}
	return true
}

// ForgetTransfer drops a task snapshot immediately so superseded mount writes do not stack in the UI.
func ForgetTransfer(id string) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	delete(globalTransferMonitor.tasks, id)
	delete(globalTransferMonitor.pendingCancels, id)
}

// ListTransferSnapshots returns a recent-first list so the newest task stays visible.
func ListTransferSnapshots() []TransferSnapshot {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	type item struct {
		snapshot  TransferSnapshot
		updatedAt time.Time
	}

	now := time.Now()
	for id, requestedAt := range globalTransferMonitor.pendingCancels {
		if now.Sub(requestedAt) > 10*time.Minute {
			delete(globalTransferMonitor.pendingCancels, id)
		}
	}
	result := make([]item, 0, len(globalTransferMonitor.tasks))
	for id, task := range globalTransferMonitor.tasks {
		if task.snapshot.Status != "running" && now.Sub(task.updatedAt) > 10*time.Minute {
			delete(globalTransferMonitor.tasks, id)
			continue
		}
		result = append(result, item{
			snapshot:  task.snapshot,
			updatedAt: task.updatedAt,
		})
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].updatedAt.After(result[j].updatedAt)
	})

	out := make([]TransferSnapshot, 0, len(result))
	for _, item := range result {
		out = append(out, item.snapshot)
	}
	return out
}

// GetTransferSnapshot returns the current snapshot for a specific task when present.
func GetTransferSnapshot(id string) (TransferSnapshot, bool) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return TransferSnapshot{}, false
	}
	return task.snapshot, true
}

type countingReader struct {
	reader io.Reader
	onRead func(int)
}

func (r *countingReader) Read(p []byte) (int, error) {
	n, err := r.reader.Read(p)
	if n > 0 && r.onRead != nil {
		r.onRead(n)
	}
	return n, err
}

type contextReader struct {
	ctx    context.Context
	reader io.Reader
	onRead func(int)
}

func (r *contextReader) Read(p []byte) (int, error) {
	select {
	case <-r.ctx.Done():
		return 0, r.ctx.Err()
	default:
	}

	n, err := r.reader.Read(p)
	if n > 0 && r.onRead != nil {
		r.onRead(n)
	}
	if err != nil {
		return n, err
	}

	select {
	case <-r.ctx.Done():
		return n, r.ctx.Err()
	default:
		return n, nil
	}
}

type contextReadSeeker struct {
	ctx    context.Context
	reader io.ReadSeeker
	onRead func(int)
}

func (r *contextReadSeeker) Read(p []byte) (int, error) {
	select {
	case <-r.ctx.Done():
		return 0, r.ctx.Err()
	default:
	}

	n, err := r.reader.Read(p)
	if n > 0 && r.onRead != nil {
		r.onRead(n)
	}
	if err != nil {
		return n, err
	}

	select {
	case <-r.ctx.Done():
		return n, r.ctx.Err()
	default:
		return n, nil
	}
}

func (r *contextReadSeeker) Seek(offset int64, whence int) (int64, error) {
	select {
	case <-r.ctx.Done():
		return 0, r.ctx.Err()
	default:
		return r.reader.Seek(offset, whence)
	}
}
