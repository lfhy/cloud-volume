// Invoke endpoints mirror bridge method names while sourcing config from the server.
package webapi

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	s3ops "remote-storage/go/s3"
	shareops "remote-storage/go/share"
	storageops "remote-storage/go/storage"
)

type invokeEnvelope struct {
	Config         storageconfig.RemoteStorageConfig `json:"config"`
	Name           string                            `json:"name"`
	Bucket         string                            `json:"bucket"`
	Prefix         string                            `json:"prefix"`
	NextToken      string                            `json:"nextToken"`
	PageSize       int32                             `json:"pageSize"`
	Key            string                            `json:"key"`
	IsDirectory    bool                              `json:"isDirectory"`
	NewName        string                            `json:"newName"`
	SourceKey      string                            `json:"sourceKey"`
	TargetKey      string                            `json:"targetKey"`
	TaskID         string                            `json:"taskId"`
	TaskIDs        []string                          `json:"taskIds"`
	ProfileID      string                            `json:"profileId"`
	Statuses       []string                          `json:"statuses"`
	IncludeHistory bool                              `json:"includeHistory"`
	Cursor         string                            `json:"cursor"`
	Limit          int                               `json:"limit"`
	Permanent      bool                              `json:"permanent"`
	TrashID        string                            `json:"trashId"`
	DurationSec    int                               `json:"durationSec"`
	ID             string                            `json:"id"`
	ClearAll       bool                              `json:"clearAll"`
	Names          []string                          `json:"names"`
	Ids            []string                          `json:"ids"`
}

func (s *Server) handleInvoke(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, fmt.Errorf("method not allowed"))
		return
	}
	method := strings.TrimPrefix(r.URL.Path, "/api/invoke/")
	method = strings.TrimSpace(method)
	if method == "" {
		writeError(w, http.StatusNotFound, fmt.Errorf("missing method"))
		return
	}

	var input invokeEnvelope
	if err := decodeBody(r.Body, &input); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if method == "save_config" {
		currentConfig, err := loadCurrentConfig()
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if isWebConfigured(currentConfig) && !s.authenticated(r) {
			writeError(w, http.StatusUnauthorized, fmt.Errorf("login required"))
			return
		}
	}
	if method == "reset_user_config" && !s.authenticated(r) {
		// Resetting accounts wipes the active login, so require an existing
		// session first to avoid anonymous callers clearing stored config.
		writeError(w, http.StatusUnauthorized, fmt.Errorf("login required"))
		return
	}
	if method != "load_bootstrap_state" &&
		method != "save_config" &&
		method != "list_profiles" &&
		method != "load_profile" &&
		!s.authenticated(r) {
		writeError(w, http.StatusUnauthorized, fmt.Errorf("login required"))
		return
	}
	result, status, err := s.invokeMethod(r.Context(), method, input)
	if err != nil {
		writeError(w, status, err)
		return
	}
	if method == "save_config" {
		if state, ok := result.(storageconfig.BootstrapState); ok && isWebConfigured(state.Config) {
			if err := s.establishSession(w, r); err != nil {
				writeError(w, http.StatusInternalServerError, err)
				return
			}
		}
	}
	if method == "reset_user_config" {
		// Wiping accounts also drops the active session so the browser returns to
		// the first-run setup flow instead of staying logged in against empty config.
		s.sessions.Delete(s.sessionToken(r))
		s.clearSessionCookie(w, r)
	}
	writeSuccess(w, result)
}

func (s *Server) invokeMethod(
	ctx context.Context,
	method string,
	input invokeEnvelope,
) (any, int, error) {
	switch method {
	case "load_bootstrap_state":
		state, err := loadBootstrapState()
		return state, http.StatusOK, err
	case "save_config":
		state, err := s.saveConfig(input.Config)
		return state, http.StatusOK, err
	case "list_profiles":
		profiles, err := storageconfig.ListProfiles()
		return profiles, http.StatusOK, err
	case "load_profile":
		if strings.TrimSpace(input.Name) == "" {
			return nil, http.StatusBadRequest, fmt.Errorf("missing profile name")
		}
		config, err := storageconfig.LoadProfile(input.Name)
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		publicConfig, err := config.PublicSanitized().WithResolvedCacheDirectory()
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		return publicConfig, http.StatusOK, nil
	case "save_profile":
		if strings.TrimSpace(input.Name) == "" {
			return nil, http.StatusBadRequest, fmt.Errorf("missing profile name")
		}
		if err := storageconfig.SaveProfile(input.Name, input.Config); err != nil {
			return nil, http.StatusInternalServerError, err
		}
		return map[string]any{"ok": true}, http.StatusOK, nil
	case "delete_profile":
		if strings.TrimSpace(input.Name) == "" {
			return nil, http.StatusBadRequest, fmt.Errorf("missing profile name")
		}
		if err := storageconfig.DeleteProfile(input.Name); err != nil {
			return nil, http.StatusInternalServerError, err
		}
		return map[string]any{"ok": true}, http.StatusOK, nil
	case "reset_user_config":
		if err := storageconfig.ResetAllProfiles(); err != nil {
			return nil, http.StatusInternalServerError, err
		}
		// Reset the per-server WebDAV server state so stale mounts/credentials do
		// not leak across the wipe.
		if err := s.webdav.Reset(); err != nil {
			return nil, http.StatusInternalServerError, err
		}
		state, err := loadBootstrapState()
		return state, http.StatusOK, err
	case "set_active_profile":
		if strings.TrimSpace(input.Name) == "" {
			return nil, http.StatusBadRequest, fmt.Errorf("missing profile name")
		}
		state, err := setActiveWebProfile(input.Name)
		return state, http.StatusOK, err
	case "reorder_profiles":
		if err := storageconfig.ReorderProfiles(input.Names); err != nil {
			return nil, http.StatusInternalServerError, err
		}
		return map[string]any{"ok": true}, http.StatusOK, nil
	case "reorder_buckets":
		if err := storageconfig.ReorderBuckets(input.Ids); err != nil {
			return nil, http.StatusInternalServerError, err
		}
		return map[string]any{"ok": true}, http.StatusOK, nil
	case "list_bucket_order":
		order, err := storageconfig.ListBucketOrder()
		return order, http.StatusOK, err
	}
	config, err := requireConfiguredStorage()
	if err != nil {
		return nil, http.StatusBadRequest, err
	}

	switch method {
	case "list_buckets":
		result, err := storageops.ForConfig(config).ListBuckets(ctx)
		return result, http.StatusOK, err
	case "get_bucket_quota":
		result, err := storageops.GetBucketQuota(ctx, config, input.Bucket)
		return result, http.StatusOK, err
	case "list_object_page":
		if config.Normalized().StorageType != storageconfig.StorageTypeWebDAV {
			if page, handled, err := bucketmount.ListMountedObjectPage(
				config,
				input.Bucket,
				input.Prefix,
				input.NextToken,
				input.PageSize,
			); handled || err != nil {
				return page, http.StatusOK, err
			}
		}
		result, err := storageops.ForConfig(config).ListObjectsPage(
			ctx,
			input.Bucket,
			input.Prefix,
			input.NextToken,
			input.PageSize,
		)
		return result, http.StatusOK, err
	case "head_object":
		result, err := storageops.ForConfig(config).HeadObject(ctx, input.Bucket, input.Key)
		return result, http.StatusOK, err
	case "directory_access":
		result, err := storageops.ForConfig(config).DirectoryAccess(ctx, input.Bucket, input.Prefix)
		return result, http.StatusOK, err
	case "create_directory":
		err := storageops.ForConfig(config).CreateDirectory(ctx, input.Bucket, input.Prefix, input.Name)
		if err == nil {
			// Keep mounted session caches in sync with the out-of-mount mutation.
			newDir := joinWebapiChildPath(input.Prefix, input.Name)
			bucketmount.NotifyExternalUpload(config, input.Bucket, newDir, true)
		}
		return map[string]any{"ok": true}, http.StatusOK, err
	case "delete_object":
		backend := storageops.ForConfig(config)
		// A permanent delete bypasses trash routing even when soft delete is on.
		deleteFn := backend.DeleteObject
		if input.Permanent {
			deleteFn = backend.DeleteObjectHard
		}
		err := deleteFn(
			ctx,
			input.Bucket,
			input.Key,
			input.IsDirectory,
			input.TaskID,
		)
		if err == nil {
			bucketmount.NotifyExternalDelete(config, input.Bucket, input.Key, input.IsDirectory)
		}
		return map[string]any{"ok": true}, http.StatusOK, err
	case "rename_object":
		newPath := joinWebapiChildPath(webapiParentDirectoryOf(input.Key), input.NewName)
		err := storageops.ForConfig(config).MoveObject(
			ctx, input.Bucket, input.Key, newPath, input.IsDirectory, input.TaskID,
		)
		if err == nil {
			bucketmount.NotifyExternalRename(config, input.Bucket, input.Key, newPath, input.IsDirectory)
		}
		return map[string]any{"ok": true}, http.StatusOK, err
	case "copy_object":
		err := storageops.ForConfig(config).CopyObject(
			ctx,
			input.Bucket,
			input.SourceKey,
			input.TargetKey,
			input.IsDirectory,
			input.TaskID,
		)
		if err == nil {
			bucketmount.NotifyExternalUpload(config, input.Bucket, input.TargetKey, input.IsDirectory)
		}
		return map[string]any{"ok": true}, http.StatusOK, err
	case "move_object":
		err := storageops.ForConfig(config).MoveObject(
			ctx,
			input.Bucket,
			input.SourceKey,
			input.TargetKey,
			input.IsDirectory,
			input.TaskID,
		)
		if err == nil {
			bucketmount.NotifyExternalRename(config, input.Bucket, input.SourceKey, input.TargetKey, input.IsDirectory)
		}
		return map[string]any{"ok": true}, http.StatusOK, err
	case "list_trash_page":
		result, err := storageops.ForConfig(config).ListTrashPage(
			ctx,
			input.Bucket,
			input.NextToken,
			input.PageSize,
		)
		return result, http.StatusOK, err
	case "restore_trash_item":
		err := storageops.ForConfig(config).RestoreTrashItem(
			ctx,
			input.Bucket,
			input.TrashID,
		)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "delete_trash_item":
		err := storageops.ForConfig(config).DeleteTrashItem(
			ctx,
			input.Bucket,
			input.TrashID,
		)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "clear_trash":
		err := storageops.ForConfig(config).ClearTrash(ctx, input.Bucket)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "create_share":
		result, err := shareops.Create(
			config,
			input.Bucket,
			input.Key,
			input.Name,
			input.DurationSec,
		)
		return result, http.StatusOK, err
	case "list_shares":
		result, err := shareops.List(config)
		return result, http.StatusOK, err
	case "refresh_share":
		result, err := shareops.Refresh(config, input.ID, input.DurationSec)
		return result, http.StatusOK, err
	case "delete_share":
		err := shareops.Delete(config, input.ID)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "list_transfer_jobs":
		return s3ops.ListTransferSnapshots(), http.StatusOK, nil
	case "list_remote_tasks":
		result, err := listWebRemoteTasks(input)
		return result, http.StatusOK, err
	case "get_remote_task":
		result, err := getWebRemoteTask(input)
		return result, http.StatusOK, err
	case "cancel_remote_task":
		result, err := controlWebRemoteTask(input, "cancel")
		return result, http.StatusOK, err
	case "retry_remote_task":
		result, err := controlWebRemoteTask(input, "retry")
		return result, http.StatusOK, err
	case "trigger_remote_task":
		result, err := controlWebRemoteTask(input, "trigger")
		return result, http.StatusOK, err
	case "clear_remote_task_history":
		result, err := clearWebRemoteTaskHistory(input)
		return result, http.StatusOK, err
	case "cancel_transfer":
		if bucketmount.CancelQueuedTransfer(input.TaskID) {
			return map[string]any{"ok": true}, http.StatusOK, nil
		}
		return map[string]any{"ok": s3ops.CancelTransfer(input.TaskID)}, http.StatusOK, nil
	case "trigger_transfer":
		return map[string]any{"ok": bucketmount.TriggerQueuedTransfer(input.TaskID)}, http.StatusOK, nil
	case "mount_bucket":
		return bucketmount.BucketMountStatus{
			Mounted:   true,
			Bucket:    strings.TrimSpace(input.Bucket),
			MountPath: "",
			ServerURL: "/webdav/" + strings.Trim(strings.TrimSpace(input.Bucket), "/") + "/",
			Port:      0,
		}, http.StatusOK, nil
	case "get_bucket_mount_status", "open_bucket_mount":
		return bucketmount.BucketMountStatus{
			Mounted:   true,
			Bucket:    strings.TrimSpace(input.Bucket),
			MountPath: "",
			ServerURL: "/webdav/" + strings.Trim(strings.TrimSpace(input.Bucket), "/") + "/",
			Port:      0,
		}, http.StatusOK, nil
	case "unmount_bucket":
		return bucketmount.BucketMountStatus{
			Mounted:   false,
			Bucket:    strings.TrimSpace(input.Bucket),
			MountPath: "",
			ServerURL: "/webdav/" + strings.Trim(strings.TrimSpace(input.Bucket), "/") + "/",
			Port:      0,
		}, http.StatusOK, nil
	case "cleanup_mounts":
		return map[string]any{"ok": true}, http.StatusOK, s.webdav.Reset()
	case "cleanup_stale_windows_processes":
		return map[string]any{"ok": true, "count": 0}, http.StatusOK, nil
	case "get_cache_stats":
		stats, err := storageconfig.GetCacheStats(config)
		return stats, http.StatusOK, err
	case "clean_cache":
		result, err := storageconfig.CleanCache(
			config,
			storageconfig.CleanCacheRequest{ClearAll: input.ClearAll},
		)
		return result, http.StatusOK, err
	default:
		return nil, http.StatusNotFound, fmt.Errorf("unsupported bridge method %q", method)
	}
}

func (s *Server) saveConfig(
	config storageconfig.RemoteStorageConfig,
) (storageconfig.BootstrapState, error) {
	if err := storageconfig.SaveProfile("default", config); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	_ = storageconfig.SetActiveProfile("default")
	s.sessions.Reset()
	if err := s.webdav.Reset(); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	return loadBootstrapState()
}

func setActiveWebProfile(name string) (storageconfig.BootstrapState, error) {
	if err := storageconfig.SetActiveProfile(name); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	return loadBootstrapState()
}

func (s *Server) establishSession(
	w http.ResponseWriter,
	r *http.Request,
) error {
	s.sessions.Delete(s.sessionToken(r))
	token, expiresAt, err := s.sessions.Create()
	if err != nil {
		return err
	}
	s.setSessionCookie(w, r, token, expiresAt)
	return nil
}

func decodeBody(body io.ReadCloser, target any) error {
	defer body.Close()
	raw, err := io.ReadAll(body)
	if err != nil {
		return err
	}
	trimmed := strings.TrimSpace(string(raw))
	if trimmed == "" || trimmed == "null" {
		return nil
	}
	if err := json.Unmarshal(raw, target); err != nil {
		return fmt.Errorf("invalid request payload")
	}
	return nil
}

// webapiParentDirectoryOf returns the prefix portion of a slash-joined object
// key, used when computing the parent path of an out-of-mount mutation target.
func webapiParentDirectoryOf(key string) string {
	trimmed := strings.Trim(strings.TrimSpace(key), "/")
	idx := strings.LastIndex(trimmed, "/")
	if idx < 0 {
		return ""
	}
	return trimmed[:idx]
}

// joinWebapiChildPath joins a parent prefix with a single relative name,
// mirroring how the mount layer composes virtual paths for rename targets.
func joinWebapiChildPath(parent, name string) string {
	cleanParent := strings.Trim(strings.TrimSpace(parent), "/")
	cleanName := strings.Trim(strings.TrimSpace(name), "/")
	switch {
	case cleanParent == "":
		return cleanName
	case cleanName == "":
		return cleanParent
	default:
		return cleanParent + "/" + cleanName
	}
}
