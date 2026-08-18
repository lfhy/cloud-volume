// Web remote-task handlers expose the same logical queue contract as desktop.
package webapi

import (
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	storageconfig "remote-storage/go/config"
	bucketmetadata "remote-storage/go/mount/metadata"
	s3ops "remote-storage/go/s3"
)

type webRemoteTaskPage struct {
	Items        []any           `json:"items"`
	NextCursor   string          `json:"nextCursor,omitempty"`
	ServerTime   string          `json:"serverTime"`
	Freshness    string          `json:"freshness"`
	Capabilities map[string]bool `json:"capabilities"`
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
	if _, err := manager.CompactTaskHistory(); err != nil {
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
	items := make([]any, 0)
	for _, group := range groups {
		for _, task := range group.Tasks {
			if !webMetadataTaskMatches(task, input) {
				continue
			}
			items = append(items, webMetadataTaskWire(task, byID))
		}
	}
	for _, snapshot := range physical {
		if strings.HasPrefix(snapshot.ID, "metadata-op-") || !webRuntimeTaskMatches(snapshot, input) {
			continue
		}
		items = append(items, webRuntimeTaskWire(snapshot))
	}
	sort.SliceStable(items, func(i, j int) bool {
		return fmt.Sprint(items[i].(map[string]any)["id"]) < fmt.Sprint(items[j].(map[string]any)["id"])
	})
	start := webTaskCursorOffset(input.Cursor)
	if start > len(items) {
		start = len(items)
	}
	items = items[start:]
	limit := input.Limit
	if limit <= 0 {
		limit = 100
	}
	nextCursor := ""
	if len(items) > limit {
		items = items[:limit]
		nextCursor = strconv.Itoa(start + limit)
	}
	return webRemoteTaskPage{
		Items:      items,
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
	if strings.TrimSpace(input.TaskID) == "" {
		return nil, fmt.Errorf("missing remote task id")
	}
	if strings.HasPrefix(input.TaskID, "transfer:") {
		// Runtime snapshots do not yet carry an authenticated profile identity.
		// Keep them out of the Web API until that adapter can scope them safely.
		return nil, bucketmetadata.ErrNotFound
	}
	config, err := loadCurrentConfig()
	if err != nil {
		return nil, err
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
	if strings.HasPrefix(input.TaskID, "transfer:") {
		return nil, bucketmetadata.ErrNotFound
	}
	config, err := loadCurrentConfig()
	if err != nil {
		return nil, err
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
	removed, err := manager.ClearTaskHistoryFor(config.ProfileID, input.Bucket, time.Now().Add(-30*24*time.Hour))
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
	if input.ProfileID != "" && snapshot.ProfileID != input.ProfileID {
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
	wire["rawEventCount"] = len(task.SourceSeqs)
	events := make([]map[string]any, 0, len(task.SourceSeqs))
	for index, seq := range task.SourceSeqs {
		kind := task.Kind
		if index < len(task.SourceKinds) {
			kind = task.SourceKinds[index]
		}
		events = append(events, map[string]any{
			"sequence": seq, "kind": kind, "state": task.Status,
			"targetPath": task.DisplayPath, "folded": index != len(task.SourceSeqs)-1,
		})
	}
	wire["events"] = events
	physicalIDs := task.PhysicalTaskIDs
	if len(physicalIDs) == 0 && task.PhysicalSnapshot != "" {
		physicalIDs = []string{task.PhysicalSnapshot}
	}
	wire["physicalTaskIds"] = physicalIDs
	if progress, ok := webMergeTransferProgress(physical, physicalIDs); ok {
		wire["progress"] = progress
		wire["phases"] = webTransferPhases(physical, physicalIDs)
	}
	return wire
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

func webTaskCursorOffset(cursor string) int {
	value, err := strconv.Atoi(strings.TrimSpace(cursor))
	if err != nil || value < 0 {
		return 0
	}
	return value
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

func webRuntimeTaskWire(snapshot s3ops.TransferSnapshot) map[string]any {
	source := "runtime"
	if strings.HasPrefix(snapshot.Type, "sync_") {
		source = "sync"
	}
	if snapshot.Type == "app_update" {
		source = "app_update"
	}
	return map[string]any{
		"id":              "transfer:" + snapshot.ID,
		"source":          source,
		"kind":            webRuntimeKind(snapshot.Type),
		"profileId":       snapshot.ProfileID,
		"status":          snapshot.Status,
		"phase":           snapshot.StatusDetail,
		"bucket":          snapshot.Bucket,
		"sourcePath":      snapshot.Key,
		"targetPath":      snapshot.TargetPath,
		"displayPath":     snapshot.Key,
		"createdAt":       snapshot.CreatedAt,
		"cancelable":      snapshot.Status == "pending" || snapshot.Status == "running",
		"retryable":       snapshot.Status == "failed" && snapshot.LocalPath != "",
		"triggerable":     snapshot.Status == "pending" && webRuntimeKind(snapshot.Type) == "upload",
		"progress":        webTransferProgress(snapshot),
		"physicalTaskIds": []string{snapshot.ID},
	}
}

func webTransferProgress(snapshot s3ops.TransferSnapshot) map[string]any {
	return map[string]any{
		"bytesCompleted": snapshot.BytesCompleted,
		"totalBytes":     snapshot.TotalBytes,
		"itemsCompleted": snapshot.ItemsCompleted,
		"totalItems":     snapshot.TotalItems,
		"speedBytes":     snapshot.SpeedBytes,
		"currentKey":     snapshot.CurrentFileKey,
	}
}

func webRuntimeKind(value string) string {
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
	case "sync_mkdir":
		return "mkdir"
	case "app_update":
		return "app_update"
	default:
		return "unknown"
	}
}
