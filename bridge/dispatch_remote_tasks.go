// Unified task bridge joins durable metadata operations with legacy transfer snapshots.
package main

import (
	"encoding/json"
	"fmt"
	"sort"
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

type remoteTaskPage struct {
	Items        []any           `json:"items"`
	NextCursor   string          `json:"nextCursor,omitempty"`
	ServerTime   string          `json:"serverTime"`
	Freshness    string          `json:"freshness"`
	Capabilities map[string]bool `json:"capabilities"`
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
	if _, err := manager.ClearTaskHistoryFor(input.ProfileID, input.Bucket, time.Now().Add(-30*24*time.Hour)); err != nil {
		return nil, err
	}
	groups, err := manager.ListTaskGroups()
	if err != nil {
		return nil, err
	}
	items := make([]any, 0)
	physical := s3ops.ListTransferSnapshots()
	physicalByID := make(map[string]s3ops.TransferSnapshot, len(physical))
	for _, snapshot := range physical {
		physicalByID[snapshot.ID] = snapshot
	}
	for _, group := range groups {
		for _, task := range group.Tasks {
			if !remoteTaskMatches(task, input) {
				continue
			}
			items = append(items, metadataTaskWire(task, physicalByID))
		}
	}
	for _, snapshot := range physical {
		if strings.HasPrefix(snapshot.ID, "metadata-op-") {
			continue
		}
		if !runtimeTaskMatches(snapshot, input) {
			continue
		}
		items = append(items, runtimeTaskWire(snapshot))
	}
	sort.SliceStable(items, func(i, j int) bool {
		return fmt.Sprint(items[i].(map[string]any)["id"]) < fmt.Sprint(items[j].(map[string]any)["id"])
	})
	start := taskCursorOffset(input.Cursor)
	if start > len(items) {
		start = len(items)
	}
	items = items[start:]
	limit := input.Limit
	if limit <= 0 {
		limit = 100
	}
	var nextCursor string
	if len(items) > limit {
		items = items[:limit]
		nextCursor = strconv.Itoa(start + limit)
	}
	return remoteTaskPage{
		Items:      items,
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
		if !ok {
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
	if input.ProfileID != "" && snapshot.ProfileID != input.ProfileID {
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

func runtimeTaskWire(snapshot s3ops.TransferSnapshot) map[string]any {
	kind := runtimeTaskKind(snapshot.Type)
	status := snapshot.Status
	phase := snapshot.StatusDetail
	source := "runtime"
	if strings.HasPrefix(snapshot.Type, "sync_") {
		source = "sync"
	}
	if snapshot.Type == "app_update" {
		source = "app_update"
	}
	return map[string]any{
		"id":          "transfer:" + snapshot.ID,
		"source":      source,
		"kind":        kind,
		"profileId":   snapshot.ProfileID,
		"status":      status,
		"phase":       phase,
		"bucket":      snapshot.Bucket,
		"sourcePath":  snapshot.Key,
		"targetPath":  snapshot.TargetPath,
		"displayPath": snapshot.Key,
		"createdAt":   snapshot.CreatedAt,
		"cancelable":  status == "pending" || status == "running",
		// Runtime producers do not yet expose a replayable request contract.
		"retryable":       false,
		"triggerable":     status == "pending" && kind == "upload",
		"error":           snapshot.Error,
		"progress":        transferProgressWire(snapshot),
		"physicalTaskIds": []string{snapshot.ID},
	}
}

func transferProgressWire(snapshot s3ops.TransferSnapshot) map[string]any {
	return map[string]any{
		"bytesCompleted": snapshot.BytesCompleted,
		"totalBytes":     snapshot.TotalBytes,
		"itemsCompleted": snapshot.ItemsCompleted,
		"totalItems":     snapshot.TotalItems,
		"speedBytes":     snapshot.SpeedBytes,
		"currentKey":     snapshot.CurrentFileKey,
	}
}

func runtimeTaskKind(value string) string {
	switch value {
	case "upload", "sync_upload":
		return "upload"
	case "download", "sync_download":
		return "download"
	case "copy":
		return "copy"
	case "move", "sync_rename":
		return "move"
	case "delete", "sync_delete":
		return "delete"
	case "app_update":
		return "app_update"
	case "sync_mkdir":
		return "mkdir"
	default:
		return "unknown"
	}
}
