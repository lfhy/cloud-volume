// Web remote-task handlers expose the same logical queue contract as desktop.
package webapi

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	bucketmetadata "remote-storage/go/mount/metadata"
	s3ops "remote-storage/go/s3"
)

type webRemoteTaskQueueCounts struct {
	Active  int `json:"active"`
	Waiting int `json:"waiting"`
	Failed  int `json:"failed"`
	History int `json:"history"`
	Total   int `json:"total"`
}

type webRemoteTaskPage struct {
	Items        []any                    `json:"items"`
	Total        int                      `json:"total"`
	Queue        webRemoteTaskQueueCounts `json:"queue"`
	NextCursor   string                   `json:"nextCursor,omitempty"`
	ServerTime   string                   `json:"serverTime"`
	Freshness    string                   `json:"freshness"`
	Capabilities map[string]bool          `json:"capabilities"`
}

// webRemoteTaskQueueFromItems counts real queue sizes from the full filtered
// (pre-pagination) item list so the UI never guesses from loaded rows.
func webRemoteTaskQueueFromItems(items []any) webRemoteTaskQueueCounts {
	active := webActiveTaskStates()
	counts := webRemoteTaskQueueCounts{}
	for _, raw := range items {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		counts.Total++
		status, _ := item["status"].(string)
		status = strings.ToLower(strings.TrimSpace(status))
		switch {
		case status == "done" || status == "completed" ||
			status == "canceled" || status == "cancelled":
			counts.History++
		case status == "failed" || status == "conflict":
			counts.Failed++
		case status == "pending" || status == "waiting" ||
			status == "blocked" || status == "retry_wait":
			// Keep browser queue badges consistent with RemoteTaskStatus.fromWire.
			counts.Waiting++
		case active[status]:
			counts.Active++
		default:
			counts.Waiting++
		}
	}
	return counts
}

func listWebRemoteTasks(input invokeEnvelope) (any, error) {
	config, err := loadCurrentConfig()
	if err != nil {
		return nil, err
	}
	// Web callers are always scoped to the authenticated server-side active
	// profile; a client-supplied profile ID must never widen visibility.
	input.ProfileID = config.ProfileID
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return nil, err
	}
	handles, err := warmWebTaskNamespaces(manager, config, input.Bucket)
	if err != nil {
		return nil, err
	}
	defer releaseWebTaskHandles(manager, handles)
	// Retention compaction is throttled: the 30-day scan is O(n²) over the
	// journal, which starves this same endpoint once history grows large.
	if _, err := manager.CompactTaskHistoryThrottled(config.ProfileID, input.Bucket); err != nil {
		return nil, err
	}
	groups, err := manager.ListTaskGroups()
	if err != nil {
		return nil, err
	}
	physical := s3ops.ListTransferSnapshots()
	byID := make(map[string]s3ops.TransferSnapshot, len(physical))
	for _, snapshot := range physical {
		byID[snapshot.ID] = snapshot
	}
	// Counts always cover the complete profile/bucket scope. includeHistory
	// changes response rows only, so active polling cannot erase loaded history
	// totals in the task page.
	countInput := webRemoteTaskCountInput(input)
	items := make([]any, 0)
	for _, group := range groups {
		for _, task := range group.Tasks {
			if !webMetadataTaskMatches(task, countInput) {
				continue
			}
			items = append(items, webMetadataTaskWire(task, byID))
		}
	}
	for _, snapshot := range physical {
		if strings.HasPrefix(snapshot.ID, "metadata-op-") || !webRuntimeTaskMatches(snapshot, countInput) {
			continue
		}
		items = append(items, webRuntimeTaskWire(snapshot))
	}
	// Active tasks first (newest first), then history; shared ordering keeps
	// page one visible for polling exactly like the desktop bridge.
	total := len(items)
	queue := webRemoteTaskQueueFromItems(items)
	items = webRemoteTaskResponseItems(items, input.IncludeHistory)
	// Active-only requests must return the full unsettled set so the
	// waiting/running tabs never cap at the page size; history still pages.
	limit := input.Limit
	if !input.IncludeHistory {
		// Page all active rows. webRemoteTaskPageSlice treats 0 as the normal
		// default page size, so use the active length as the no-cap limit.
		limit = len(items)
	}
	items, nextCursor := webRemoteTaskPageSlice(items, input.Cursor, limit)
	return webRemoteTaskPage{
		Items:      items,
		Total:      total,
		Queue:      queue,
		NextCursor: nextCursor,
		ServerTime: time.Now().UTC().Format(time.RFC3339Nano),
		Freshness:  "journal+transfer-monitor",
		Capabilities: map[string]bool{
			"cancel": true, "retry": true, "trigger": true, "history": true,
		},
	}, nil
}

func warmWebTaskNamespaces(manager *bucketmetadata.Manager, config storageconfig.RemoteStorageConfig, bucket string) ([]*bucketmetadata.AcquireHandle, error) {
	manifests, err := manager.KnownNamespaces()
	if err != nil {
		return nil, err
	}
	handles := make([]*bucketmetadata.AcquireHandle, 0, len(manifests))
	for _, manifest := range manifests {
		if manifest.ProfileID != config.ProfileID || (bucket != "" && manifest.Bucket != bucket) {
			continue
		}
		handle, err := manager.Acquire(config, manifest.Bucket)
		if err != nil {
			releaseWebTaskHandles(manager, handles)
			return nil, err
		}
		handles = append(handles, handle)
	}
	return handles, nil
}

func releaseWebTaskHandles(manager *bucketmetadata.Manager, handles []*bucketmetadata.AcquireHandle) {
	for _, handle := range handles {
		manager.Release(handle)
	}
}

func getWebRemoteTask(input invokeEnvelope) (any, error) {
	config, err := loadCurrentConfig()
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(input.TaskID) == "" {
		return nil, fmt.Errorf("missing remote task id")
	}
	if strings.HasPrefix(input.TaskID, "transfer:") {
		snapshot, ok := s3ops.GetTransferSnapshot(strings.TrimPrefix(input.TaskID, "transfer:"))
		if !ok || (snapshot.ProfileID != config.ProfileID && snapshot.Type != "app_update") ||
			(input.Bucket != "" && snapshot.Bucket != input.Bucket) {
			return nil, bucketmetadata.ErrNotFound
		}
		return webRuntimeTaskWire(snapshot), nil
	}
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return nil, err
	}
	handles, err := warmWebTaskNamespaces(manager, config, "")
	if err != nil {
		return nil, err
	}
	defer releaseWebTaskHandles(manager, handles)
	namespace := webRemoteTaskNamespace(input.TaskID)
	if namespace == "" {
		return nil, bucketmetadata.ErrNotFound
	}
	task, err := manager.GetTask(namespace, input.TaskID)
	if err != nil {
		return nil, err
	}
	if task.ProfileID != config.ProfileID {
		return nil, bucketmetadata.ErrNotFound
	}
	physical := s3ops.ListTransferSnapshots()
	byID := make(map[string]s3ops.TransferSnapshot, len(physical))
	for _, snapshot := range physical {
		byID[snapshot.ID] = snapshot
	}
	return webMetadataTaskWire(task, byID), nil
}

func controlWebRemoteTask(input invokeEnvelope, action string) (any, error) {
	config, err := loadCurrentConfig()
	if err != nil {
		return nil, err
	}
	if strings.HasPrefix(input.TaskID, "transfer:") {
		id := strings.TrimPrefix(input.TaskID, "transfer:")
		snapshot, ok := s3ops.GetTransferSnapshot(id)
		if !ok || (snapshot.ProfileID != config.ProfileID && snapshot.Type != "app_update") ||
			(input.Bucket != "" && snapshot.Bucket != input.Bucket) {
			return nil, bucketmetadata.ErrNotFound
		}
		ok = false
		switch action {
		case "cancel":
			ok = bucketmount.CancelQueuedTransfer(id) || s3ops.CancelTransfer(id)
		case "trigger":
			ok = bucketmount.TriggerQueuedTransfer(id)
		case "retry":
			ok = false
		}
		return map[string]any{"ok": ok}, nil
	}
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return nil, err
	}
	handles, err := warmWebTaskNamespaces(manager, config, "")
	if err != nil {
		return nil, err
	}
	defer releaseWebTaskHandles(manager, handles)
	namespace := webRemoteTaskNamespace(input.TaskID)
	if namespace == "" {
		return nil, bucketmetadata.ErrNotFound
	}
	current, err := manager.GetTask(namespace, input.TaskID)
	if err != nil {
		return nil, err
	}
	if current.ProfileID != config.ProfileID {
		return nil, bucketmetadata.ErrNotFound
	}
	var task bucketmetadata.Task
	switch action {
	case "cancel":
		task, err = manager.CancelTask(input.TaskID)
	case "retry":
		task, err = manager.RetryTask(input.TaskID)
	case "trigger":
		task, err = manager.TriggerTask(input.TaskID)
	}
	if err != nil {
		return nil, err
	}
	return map[string]any{"ok": true, "task": task}, nil
}

func clearWebRemoteTaskHistory(input invokeEnvelope) (any, error) {
	config, err := loadCurrentConfig()
	if err != nil {
		return nil, err
	}
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return nil, err
	}
	handles, err := warmWebTaskNamespaces(manager, config, input.Bucket)
	if err != nil {
		return nil, err
	}
	defer releaseWebTaskHandles(manager, handles)
	var removed int
	if len(input.TaskIDs) > 0 {
		removed, err = manager.ClearTaskHistoryIDsFor(config.ProfileID, input.Bucket, input.TaskIDs)
	} else {
		// Explicit UI cleanup is allowed to remove all compactable terminal
		// history in scope; listing still enforces the 30-day retention policy.
		removed, err = manager.ClearTaskHistoryFor(config.ProfileID, input.Bucket, time.Time{})
	}
	removed += s3ops.ForgetTerminalTransfers(input.TaskIDs, config.ProfileID, input.Bucket)
	if err != nil {
		return nil, err
	}
	return map[string]any{"removed": removed}, nil
}

func webMetadataTaskMatches(task bucketmetadata.Task, input invokeEnvelope) bool {
	if task.ProfileID != input.ProfileID || (input.Bucket != "" && task.Bucket != input.Bucket) {
		return false
	}
	if !input.IncludeHistory && (task.State == bucketmetadata.TaskStateDone || task.State == bucketmetadata.TaskStateCanceled) {
		return false
	}
	if len(input.Statuses) == 0 {
		return true
	}
	for _, status := range input.Statuses {
		if status == task.Status || status == string(task.State) {
			return true
		}
	}
	return false
}

func webRuntimeTaskMatches(snapshot s3ops.TransferSnapshot, input invokeEnvelope) bool {
	if input.ProfileID != "" && snapshot.ProfileID != input.ProfileID && snapshot.Type != "app_update" {
		return false
	}
	if input.Bucket != "" && snapshot.Bucket != input.Bucket {
		return false
	}
	if !input.IncludeHistory && (snapshot.Status == "done" || snapshot.Status == "completed" || snapshot.Status == "canceled" || snapshot.Status == "cancelled") {
		return false
	}
	if len(input.Statuses) == 0 {
		return true
	}
	for _, status := range input.Statuses {
		if status == snapshot.Status {
			return true
		}
	}
	return false
}

func webMetadataTaskWire(task bucketmetadata.Task, physical map[string]s3ops.TransferSnapshot) map[string]any {
	raw, _ := json.Marshal(task)
	var wire map[string]any
	_ = json.Unmarshal(raw, &wire)
	wire["source"] = "metadata"
	wire["rawEventCount"] = len(task.Events)
	wire["events"] = task.Events
	physicalIDs := task.PhysicalTaskIDs
	if len(physicalIDs) == 0 && task.PhysicalSnapshot != "" {
		physicalIDs = []string{task.PhysicalSnapshot}
	}
	wire["physicalTaskIds"] = physicalIDs
	owned := webOwnedPhysicalSnapshots(task, physical)
	if progress, ok := webMergeTransferProgress(owned, physicalIDs); ok {
		wire["progress"] = progress
		wire["phases"] = webTransferPhases(owned, physicalIDs)
	}
	return wire
}

func webOwnedPhysicalSnapshots(task bucketmetadata.Task, physical map[string]s3ops.TransferSnapshot) map[string]s3ops.TransferSnapshot {
	owned := make(map[string]s3ops.TransferSnapshot)
	for id, snapshot := range physical {
		if snapshot.ProfileID != "" && task.ProfileID != "" && snapshot.ProfileID != task.ProfileID {
			continue
		}
		if task.Bucket != "" && snapshot.Bucket != "" && snapshot.Bucket != task.Bucket {
			continue
		}
		owned[id] = snapshot
	}
	return owned
}

func webTransferPhases(physical map[string]s3ops.TransferSnapshot, ids []string) []map[string]any {
	phases := make([]map[string]any, 0, len(ids))
	for _, id := range ids {
		snapshot, ok := physical[id]
		if !ok {
			continue
		}
		phases = append(phases, map[string]any{
			"name": id, "status": snapshot.Status, "detail": snapshot.StatusDetail,
			"progress": webTransferProgress(snapshot),
		})
	}
	return phases
}

func webMergeTransferProgress(physical map[string]s3ops.TransferSnapshot, ids []string) (map[string]any, bool) {
	var merged s3ops.TransferSnapshot
	found := false
	for _, id := range ids {
		snapshot, ok := physical[id]
		if !ok {
			continue
		}
		if !found {
			merged = snapshot
			found = true
			continue
		}
		merged.BytesCompleted += snapshot.BytesCompleted
		merged.TotalBytes += snapshot.TotalBytes
		merged.ItemsCompleted += snapshot.ItemsCompleted
		merged.TotalItems += snapshot.TotalItems
		merged.SpeedBytes += snapshot.SpeedBytes
		if snapshot.CurrentFileKey != "" {
			merged.CurrentFileKey = snapshot.CurrentFileKey
		}
	}
	if !found {
		return nil, false
	}
	return webTransferProgress(merged), true
}

func webRemoteTaskNamespace(taskID string) string {
	trimmed := strings.TrimSpace(taskID)
	if strings.HasPrefix(trimmed, "sync:") {
		rest := strings.TrimPrefix(trimmed, "sync:")
		if index := strings.IndexByte(rest, ':'); index > 0 {
			return rest[:index]
		}
		return ""
	}
	if index := strings.LastIndexByte(trimmed, ':'); index > 0 {
		return trimmed[:index]
	}
	return ""
}
