// Unified task bridge joins durable metadata operations with legacy transfer snapshots.
package main

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	bucketmetadata "remote-storage/go/mount/metadata"
	s3ops "remote-storage/go/s3"
)

type remoteTaskListArgs struct {
	ProfileID      string   `json:"profileId"`
	Bucket         string   `json:"bucket"`
	Statuses       []string `json:"statuses"`
	IncludeHistory bool     `json:"includeHistory"`
	Cursor         string   `json:"cursor"`
	Limit          int      `json:"limit"`
}

type remoteTaskQueueCounts struct {
	Active  int `json:"active"`
	Waiting int `json:"waiting"`
	Failed  int `json:"failed"`
	History int `json:"history"`
	Total   int `json:"total"`
}

type remoteTaskPage struct {
	Items        []any                 `json:"items"`
	Total        int                   `json:"total"`
	Queue        remoteTaskQueueCounts `json:"queue"`
	NextCursor   string                `json:"nextCursor,omitempty"`
	ServerTime   string                `json:"serverTime"`
	Freshness    string                `json:"freshness"`
	Capabilities map[string]bool       `json:"capabilities"`
}

// remoteTaskQueueFromItems counts real queue sizes from the full filtered
// (pre-pagination) item list so the UI never guesses from loaded rows.
func remoteTaskQueueFromItems(items []any) remoteTaskQueueCounts {
	active := activeTaskStates()
	counts := remoteTaskQueueCounts{}
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
			// The Dart wire parser renders pending as waiting, so these counts
			// must drive the same queue tab as the rows themselves.
			counts.Waiting++
		case active[status]:
			counts.Active++
		default:
			// Unknown wire states deliberately degrade to waiting in Dart.
			counts.Waiting++
		}
	}
	return counts
}

func listRemoteTasks(args json.RawMessage) (any, error) {
	var input remoteTaskListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return nil, err
	}
	handles, err := warmKnownTaskNamespaces(manager, input)
	if err != nil {
		return nil, err
	}
	defer releaseTaskNamespaceHandles(manager, handles)
	// Retention compaction is throttled: the 30-day scan is O(n²) over the
	// journal, which starves this same endpoint once history grows large.
	if _, err := manager.CompactTaskHistoryThrottled(input.ProfileID, input.Bucket); err != nil {
		return nil, err
	}
	groups, err := manager.ListTaskGroups()
	if err != nil {
		return nil, err
	}
	// Counts always describe the complete profile/bucket scope. includeHistory
	// controls only the rows sent to a poller; otherwise an active-only refresh
	// would overwrite a loaded history count with zero ("共 0 项 · 已加载 200").
	countInput := remoteTaskCountInput(input)
	items := make([]any, 0)
	physical := s3ops.ListTransferSnapshots()
	physicalByID := make(map[string]s3ops.TransferSnapshot, len(physical))
	for _, snapshot := range physical {
		physicalByID[snapshot.ID] = snapshot
	}
	for _, group := range groups {
		for _, task := range group.Tasks {
			if !remoteTaskMatches(task, countInput) {
				continue
			}
			items = append(items, metadataTaskWire(task, physicalByID))
		}
	}
	for _, snapshot := range physical {
		if strings.HasPrefix(snapshot.ID, "metadata-op-") {
			continue
		}
		if !runtimeTaskMatches(snapshot, countInput) {
			continue
		}
		items = append(items, runtimeTaskWire(snapshot))
	}
	// Active tasks always outrank history so page-one polling can observe
	// every unsettled operation regardless of accumulated done entries.
	total := len(items)
	queue := remoteTaskQueueFromItems(items)
	items = remoteTaskResponseItems(items, input.IncludeHistory)
	// Active-only requests must return the full unsettled set so the
	// waiting/running tabs never cap at the page size; history still pages.
	limit := input.Limit
	if !input.IncludeHistory {
		// Page all active rows. remoteTaskPageSlice treats 0 as the normal
		// default page size, so use the actual active length as the no-cap limit.
		limit = len(items)
	}
	items, nextCursor := remoteTaskPageSlice(items, input.Cursor, limit)
	return remoteTaskPage{
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

// warmKnownTaskNamespaces reopens only manifests that match a saved profile;
// profile configs remain the authority for credentials and provider settings.
func warmKnownTaskNamespaces(manager *bucketmetadata.Manager, input remoteTaskListArgs) ([]*bucketmetadata.AcquireHandle, error) {
	manifests, err := manager.KnownNamespaces()
	if err != nil {
		return nil, err
	}
	profiles, err := storageconfig.ListProfiles()
	if err != nil {
		return nil, err
	}
	configs := make(map[string]storageconfig.RemoteStorageConfig, len(profiles))
	for _, profile := range profiles {
		config, loadErr := storageconfig.LoadProfile(profile.Name)
		if loadErr == nil && config.ProfileID != "" {
			configs[config.ProfileID] = config
		}
	}
	handles := make([]*bucketmetadata.AcquireHandle, 0, len(manifests))
	for _, manifest := range manifests {
		if input.ProfileID != "" && manifest.ProfileID != input.ProfileID {
			continue
		}
		if input.Bucket != "" && manifest.Bucket != input.Bucket {
			continue
		}
		config, ok := configs[manifest.ProfileID]
		if !ok {
			continue
		}
		handle, acquireErr := manager.Acquire(config, manifest.Bucket)
		if acquireErr != nil {
			releaseTaskNamespaceHandles(manager, handles)
			return nil, acquireErr
		}
		handles = append(handles, handle)
	}
	return handles, nil
}

func releaseTaskNamespaceHandles(manager *bucketmetadata.Manager, handles []*bucketmetadata.AcquireHandle) {
	for _, handle := range handles {
		manager.Release(handle)
	}
}

func getRemoteTask(args json.RawMessage) (any, error) {
	var input transferTaskArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if strings.TrimSpace(input.TaskID) == "" {
		return nil, fmt.Errorf("missing remote task id")
	}
	if strings.HasPrefix(input.TaskID, "transfer:") {
		snapshot, ok := s3ops.GetTransferSnapshot(strings.TrimPrefix(input.TaskID, "transfer:"))
		if !ok || (input.ProfileID != "" && snapshot.ProfileID != input.ProfileID) ||
			(input.Bucket != "" && snapshot.Bucket != input.Bucket) {
			return nil, bucketmetadata.ErrNotFound
		}
		return runtimeTaskWire(snapshot), nil
	}
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return nil, err
	}
	handles, err := warmKnownTaskNamespaces(manager, remoteTaskListArgs{})
	if err != nil {
		return nil, err
	}
	defer releaseTaskNamespaceHandles(manager, handles)
	namespace := remoteTaskNamespace(input.TaskID)
	if namespace == "" {
		return nil, bucketmetadata.ErrNotFound
	}
	task, err := manager.GetTask(namespace, input.TaskID)
	if err != nil {
		return nil, err
	}
	physical := s3ops.ListTransferSnapshots()
	byID := make(map[string]s3ops.TransferSnapshot, len(physical))
	for _, snapshot := range physical {
		byID[snapshot.ID] = snapshot
	}
	return metadataTaskWire(task, byID), nil
}

func cancelRemoteTask(args json.RawMessage) (any, error) {
	return controlRemoteTask(args, "cancel")
}

func retryRemoteTask(args json.RawMessage) (any, error) {
	return controlRemoteTask(args, "retry")
}

func triggerRemoteTask(args json.RawMessage) (any, error) {
	return controlRemoteTask(args, "trigger")
}

func controlRemoteTask(args json.RawMessage, action string) (any, error) {
	var input transferTaskArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if strings.HasPrefix(input.TaskID, "transfer:") {
		id := strings.TrimPrefix(input.TaskID, "transfer:")
		snapshot, exists := s3ops.GetTransferSnapshot(id)
		if !exists || (input.ProfileID != "" && snapshot.ProfileID != input.ProfileID) ||
			(input.Bucket != "" && snapshot.Bucket != input.Bucket) {
			return nil, bucketmetadata.ErrNotFound
		}
		var ok bool
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
	handles, err := warmKnownTaskNamespaces(manager, remoteTaskListArgs{})
	if err != nil {
		return nil, err
	}
	defer releaseTaskNamespaceHandles(manager, handles)
	if remoteTaskNamespace(input.TaskID) == "" {
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

func clearRemoteTaskHistory(args json.RawMessage) (any, error) {
	var input struct {
		ProfileID string   `json:"profileId"`
		Bucket    string   `json:"bucket"`
		TaskIDs   []string `json:"taskIds"`
	}
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return nil, err
	}
	handles, err := warmKnownTaskNamespaces(manager, remoteTaskListArgs{ProfileID: input.ProfileID, Bucket: input.Bucket})
	if err != nil {
		return nil, err
	}
	defer releaseTaskNamespaceHandles(manager, handles)
	var removed int
	if len(input.TaskIDs) > 0 {
		removed, err = manager.ClearTaskHistoryIDsFor(input.ProfileID, input.Bucket, input.TaskIDs)
	} else {
		// Explicit UI cleanup is allowed to remove all compactable terminal
		// history in scope; the 30-day retention rule is applied on listing.
		removed, err = manager.ClearTaskHistoryFor(input.ProfileID, input.Bucket, time.Time{})
	}
	removed += s3ops.ForgetTerminalTransfers(input.TaskIDs, input.ProfileID, input.Bucket)
	if err != nil {
		return nil, err
	}
	return map[string]any{"removed": removed}, nil
}

func remoteTaskMatches(task bucketmetadata.Task, input remoteTaskListArgs) bool {
	if input.ProfileID != "" && task.ProfileID != input.ProfileID {
		return false
	}
	if input.Bucket != "" && task.Bucket != input.Bucket {
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

func runtimeTaskMatches(snapshot s3ops.TransferSnapshot, input remoteTaskListArgs) bool {
	if input.Bucket != "" && snapshot.Bucket != input.Bucket {
		return false
	}
	if input.ProfileID != "" && snapshot.ProfileID != input.ProfileID && snapshot.Type != "app_update" {
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

func metadataTaskWire(task bucketmetadata.Task, physical map[string]s3ops.TransferSnapshot) map[string]any {
	raw, _ := json.Marshal(task)
	var wire map[string]any
	_ = json.Unmarshal(raw, &wire)
	wire["source"] = "metadata"
	wire["namespaceId"] = task.NamespaceID
	wire["rawEventCount"] = len(task.Events)
	wire["events"] = task.Events
	physicalIDs := task.PhysicalTaskIDs
	if len(physicalIDs) == 0 && task.PhysicalSnapshot != "" {
		physicalIDs = []string{task.PhysicalSnapshot}
	}
	wire["physicalTaskIds"] = physicalIDs
	owned := ownedPhysicalSnapshots(task, physical)
	if progress, ok := mergeTransferProgress(owned, physicalIDs); ok {
		wire["progress"] = progress
		wire["phases"] = transferPhases(owned, physicalIDs)
	}
	return wire
}

func ownedPhysicalSnapshots(task bucketmetadata.Task, physical map[string]s3ops.TransferSnapshot) map[string]s3ops.TransferSnapshot {
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

func transferPhases(physical map[string]s3ops.TransferSnapshot, ids []string) []map[string]any {
	phases := make([]map[string]any, 0, len(ids))
	for _, id := range ids {
		snapshot, ok := physical[id]
		if !ok {
			continue
		}
		phases = append(phases, map[string]any{
			"name": id, "status": snapshot.Status, "detail": snapshot.StatusDetail,
			"progress": transferProgressWire(snapshot),
		})
	}
	return phases
}

func mergeTransferProgress(physical map[string]s3ops.TransferSnapshot, ids []string) (map[string]any, bool) {
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
	return transferProgressWire(merged), true
}

func remoteTaskNamespace(taskID string) string {
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

func taskCursorOffset(cursor string) int {
	value, err := strconv.Atoi(strings.TrimSpace(cursor))
	if err != nil || value < 0 {
		return 0
	}
	return value
}
