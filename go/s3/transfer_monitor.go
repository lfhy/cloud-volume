// Transfer monitor: keeps short-lived object operation snapshots for Flutter.

package s3

import (
	"context"
	"errors"
	"sort"
	"sync"
	"time"
)

// TransferSnapshot is polled by Flutter to render sidebar and transfers UI.
type TransferSnapshot struct {
	ID           string `json:"id"`
	Type         string `json:"type"`
	ProfileID    string `json:"profileId,omitempty"`
	Bucket       string `json:"bucket"`
	Key          string `json:"key"`
	LocalPath    string `json:"localPath"`
	TargetPath   string `json:"targetPath,omitempty"`
	Status       string `json:"status"`
	StatusDetail string `json:"statusDetail,omitempty"`
	CreatedAt    string `json:"createdAt,omitempty"`
	// UpdatedAt (UTC RFC3339Nano) keeps ordering aligned with metadata tasks
	// even while a runtime snapshot's local-zone createdAt differs.
	UpdatedAt     string `json:"updatedAt,omitempty"`
	BytesCompleted int64  `json:"bytesCompleted"`
	TotalBytes     int64  `json:"totalBytes"`
	ItemsCompleted int64  `json:"itemsCompleted,omitempty"`
	TotalItems     int64  `json:"totalItems,omitempty"`
	// PlannedItems remembers the work units discovered so far for two-phase
	// sweeps (copy + source cleanup) so a second enumeration can reset the
	// running total instead of double-counting.
	PlannedItems              int64   `json:"-"`
	CurrentFileKey            string  `json:"currentFileKey,omitempty"`
	CurrentFileBytesCompleted int64   `json:"currentFileBytesCompleted,omitempty"`
	CurrentFileTotalBytes     int64   `json:"currentFileTotalBytes,omitempty"`
	CurrentRange              string  `json:"currentRange,omitempty"`
	CurrentPart               int32   `json:"currentPart,omitempty"`
	TotalParts                int32   `json:"totalParts,omitempty"`
	Cancelable                bool    `json:"cancelable"`
	SpeedBytes                float64 `json:"speedBytes"`
	Error                     string  `json:"error,omitempty"`
}

type transferState struct {
	snapshot     TransferSnapshot
	startedAt    time.Time
	updatedAt    time.Time
	cancel       context.CancelFunc
	activeOwners int
	// transferredBytes excludes pre-existing resume bytes so speed always
	// reflects the current transfer attempt rather than cached work.
	transferredBytes int64
	// phaseItems tracks per-phase item contributions so re-planning a phase
	// adjusts the running total instead of adding it twice.
	phaseItems map[string]int64
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
	task.snapshot.PlannedItems += deltaItems
	task.updatedAt = time.Now()
}

// PlanTransferPhaseItems declares the item count for one phase of a sweep.
// Calling it again for the same phase replaces that phase's contribution, so
// enumerating the same tree twice (progress pre-scan + transfer plan) never
// inflates the total. A sweep that enumerates two different trees (for example
// copy-to-trash then delete-source) calls it with distinct phases and the
// totals add up.
func PlanTransferPhaseItems(id string, phase string, items int64) {
	if items <= 0 {
		return
	}
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	if task.phaseItems == nil {
		task.phaseItems = map[string]int64{}
	}
	previous := task.phaseItems[phase]
	task.phaseItems[phase] = items
	task.snapshot.TotalItems += items - previous
	task.snapshot.PlannedItems += items - previous
	task.updatedAt = time.Now()
}

// resetTransferPhaseItems removes all phase contributions from the running
// total. Multi-phase sweeps that keep advancing one task call this between
// phases so the bar restarts at 0/N for each phase instead of accumulating
// "2N / N" style counts. PlannedItems is kept so phase sizing still works.
func resetTransferPhaseItems(id string) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.phaseItems = nil
	task.snapshot.TotalItems = 0
	task.updatedAt = time.Now()
}

// PlannedTransferItems returns how many work units a sweep has already
// declared for the task, so a later phase can size itself relative to it.
func PlannedTransferItems(id string) int64 {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return 0
	}
	return task.snapshot.PlannedItems
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
	task.transferredBytes += delta
	task.updatedAt = time.Now()

	elapsed := task.updatedAt.Sub(task.startedAt).Seconds()
	if elapsed > 0 {
		task.snapshot.SpeedBytes = float64(task.transferredBytes) / elapsed
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
	if task.activeOwners > 1 {
		task.activeOwners--
		return
	}
	if task.activeOwners > 0 {
		task.activeOwners--
	}
	task.cancel = nil
	task.snapshot.Cancelable = false
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
	// Show a clean "total / total" state: sweeps may over-plan phases (for
	// example sizing the source-cleanup phase from the copy-phase listing
	// before the trash-move target enumeration).
	if task.snapshot.TotalItems > 0 {
		task.snapshot.ItemsCompleted = task.snapshot.TotalItems
	}
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
	if task.snapshot.Status == "done" || task.snapshot.Status == "failed" || !task.snapshot.Cancelable {
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
		snapshot := task.snapshot
		snapshot.UpdatedAt = task.updatedAt.UTC().Format(time.RFC3339Nano)
		result = append(result, item{
			snapshot:  snapshot,
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
