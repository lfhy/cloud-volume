// Runtime snapshot projection mirrors the desktop task protocol for Web.
package webapi

import (
	"strings"

	s3ops "remote-storage/go/s3"
)

func webRuntimeTaskWire(snapshot s3ops.TransferSnapshot) map[string]any {
	source := "runtime"
	if strings.HasPrefix(snapshot.Type, "sync_") {
		source = "sync"
	}
	if snapshot.Type == "app_update" {
		source = "app_update"
	}
	kind := webRuntimeKind(snapshot.Type)
	return map[string]any{
		"id": "transfer:" + snapshot.ID, "source": source, "kind": kind,
		"profileId": snapshot.ProfileID, "status": snapshot.Status,
		"phase": snapshot.StatusDetail, "phaseDetail": snapshot.StatusDetail,
		"bucket": snapshot.Bucket, "sourcePath": snapshot.Key,
		"targetPath": snapshot.TargetPath, "displayPath": snapshot.Key,
		"localPath": snapshot.LocalPath, "createdAt": snapshot.CreatedAt,
		"cancelable": snapshot.Cancelable && (snapshot.Status == "pending" || snapshot.Status == "running"),
		"retryable":  false, "triggerable": snapshot.Status == "pending" && kind == "upload",
		"error": snapshot.Error, "progress": webTransferProgress(snapshot),
		"physicalTaskIds": []string{snapshot.ID},
	}
}

func webTransferProgress(snapshot s3ops.TransferSnapshot) map[string]any {
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
