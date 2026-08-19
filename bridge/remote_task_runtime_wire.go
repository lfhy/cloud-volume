// Runtime snapshot projection keeps physical transfer fields out of task dispatch.
package main

import (
	"strings"

	s3ops "remote-storage/go/s3"
)

func runtimeTaskWire(snapshot s3ops.TransferSnapshot) map[string]any {
	kind := runtimeTaskKind(snapshot.Type)
	status := snapshot.Status
	source := "runtime"
	if strings.HasPrefix(snapshot.Type, "sync_") {
		source = "sync"
	}
	if snapshot.Type == "app_update" {
		source = "app_update"
	}
	return map[string]any{
		"id": "transfer:" + snapshot.ID, "source": source, "kind": kind,
		"profileId": snapshot.ProfileID, "status": status, "phase": snapshot.StatusDetail,
		"phaseDetail": snapshot.StatusDetail, "bucket": snapshot.Bucket,
		"sourcePath": snapshot.Key, "targetPath": snapshot.TargetPath,
		"displayPath": snapshot.Key, "localPath": snapshot.LocalPath,
		"createdAt":  snapshot.CreatedAt,
		"cancelable": snapshot.Cancelable && (status == "pending" || status == "running"),
		"retryable":  false, "triggerable": status == "pending" && kind == "upload",
		"error": snapshot.Error, "progress": transferProgressWire(snapshot),
		"physicalTaskIds": []string{snapshot.ID},
	}
}

func transferProgressWire(snapshot s3ops.TransferSnapshot) map[string]any {
	return map[string]any{
		"bytesCompleted": snapshot.BytesCompleted, "totalBytes": snapshot.TotalBytes,
		"itemsCompleted": snapshot.ItemsCompleted, "totalItems": snapshot.TotalItems,
		"speedBytes": snapshot.SpeedBytes, "currentKey": snapshot.CurrentFileKey,
		"currentFileBytesCompleted": snapshot.CurrentFileBytesCompleted,
		"currentFileTotalBytes":     snapshot.CurrentFileTotalBytes,
		"currentRange":              snapshot.CurrentRange, "currentPart": snapshot.CurrentPart,
		"totalParts": snapshot.TotalParts,
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
