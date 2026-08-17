package main

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	storageconfig "remote-storage/go/config"
	bridgelog "remote-storage/go/logging"
	bucketmount "remote-storage/go/mount"
	s3ops "remote-storage/go/s3"
	storageops "remote-storage/go/storage"
)

// invokeBridgeMethod translates JSON RPC-like method names into typed Go operations.
func invokeBridgeMethod(method string, args json.RawMessage) (any, error) {
	if result, handled, err := invokeWindowsWinFspBridgeMethod(method); handled {
		return result, err
	}

	switch method {
	case "get_build_info":
		return getBuildInfo()
	case "resolve_system_proxy":
		return resolveSystemProxy()
	case "load_bootstrap_state":
		return loadBootstrapState()
	case "save_config":
		return saveConfig(args)
	case "update_proxy_settings":
		return updateProxySettings(args)
	case "migrate_default":
		return migrateAndBootstrap()
	// Profile management.
	case "list_profiles":
		return listProfiles()
	case "load_profile":
		return loadProfile(args)
	case "save_profile":
		return saveProfile(args)
	case "validate_account_credentials":
		return validateAccountCredentials(args)
	case "start_baidu_pan_authorization":
		return startBaiduPanAuthorization()
	case "authorize_baidu_pan":
		return authorizeBaiduPan(args)
	case "delete_profile":
		return deleteProfile(args)
	case "reset_user_config":
		return resetUserConfig(args)
	case "set_active_profile":
		return setActiveProfile(args)
	case "reorder_profiles":
		return reorderProfiles(args)
	case "reorder_buckets":
		return reorderBuckets(args)
	case "list_bucket_order":
		return listBucketOrder()
	case "load_config_backup_settings":
		return loadConfigBackupSettings()
	case "save_config_backup_settings":
		return saveConfigBackupSettings(args)
	case "backup_config_now":
		return backupConfigNow()
	case "list_config_backups":
		return listConfigBackups()
	case "restore_config_backup":
		return restoreConfigBackup(args)
	case "delete_config_backup":
		return deleteConfigBackup(args)
	case "list_config_backups_with_target":
		return listConfigBackupsWithTarget(args)
	case "restore_config_backup_with_target":
		return restoreConfigBackupWithTarget(args)
	case "verify_backup_password":
		return verifyBackupPassword(args)
	// Storage operations.
	case "list_buckets":
		return listBuckets(args)
	case "get_bucket_quota":
		return getBucketQuota(args)
	case "list_objects":
		return listObjects(args)
	case "list_object_page":
		return listObjectPage(args)
	case "metadata_namespace_status":
		return metadataNamespaceStatus(args)
	case "head_object":
		return headObject(args)
	case "directory_access":
		return directoryAccess(args)
	case "create_directory":
		return createDirectory(args)
	case "delete_object":
		return deleteObject(args)
	case "list_trash":
		return listTrash(args)
	case "list_trash_page":
		return listTrashPage(args)
	case "restore_trash_item":
		return restoreTrashItem(args)
	case "delete_trash_item":
		return deleteTrashItem(args)
	case "clear_trash":
		return clearTrash(args)
	case "create_share":
		return createShare(args)
	case "list_shares":
		return listShares(args)
	case "refresh_share":
		return refreshShare(args)
	case "delete_share":
		return deleteShare(args)
	case "rename_object":
		return renameObject(args)
	case "copy_object":
		return copyObject(args)
	case "move_object":
		return moveObject(args)
	case "upload_file":
		return uploadFile(args)
	case "upload_directory":
		return uploadDirectory(args)
	case "download_file":
		return downloadFile(args)
	case "list_transfer_jobs":
		return listTransferJobs()
	case "cancel_transfer":
		return cancelTransfer(args)
	case "trigger_transfer":
		return triggerTransfer(args)
	// Bucket mounts.
	case "mount_bucket":
		return mountBucket(args)
	case "unmount_bucket":
		return unmountBucket(args)
	case "get_bucket_mount_status":
		return getBucketMountStatus(args)
	case "open_bucket_mount":
		return openBucketMount(args)
	case "cleanup_mounts":
		return cleanupMounts()
	case "get_active_mount_count":
		return getActiveMountCount()
	case "list_available_drive_letters":
		return listAvailableDriveLetters()
	case "cleanup_stale_windows_processes":
		return cleanupStaleWindowsProcesses()
	case "get_cache_stats":
		return getCacheStats(args)
	case "open_cache_directory":
		return openCacheDirectory(args)
	case "clean_cache":
		return cleanCache(args)
	case "cache_index_find":
		return cacheIndexFind(args)
	case "cache_index_upsert":
		return cacheIndexUpsert(args)
	case "cache_index_remove":
		return cacheIndexRemove(args)
	case "cache_index_remove_prefix":
		return cacheIndexRemovePrefix(args)
	// Directory sync profiles.
	case "list_sync_profiles":
		return listSyncProfiles(args)
	case "save_sync_profile":
		return saveSyncProfile(args)
	case "delete_sync_profile":
		return deleteSyncProfile(args)
	case "trigger_sync_profile":
		return triggerSyncProfile(args)
	case "get_log_level":
		return getLogLevel()
	case "set_log_level":
		return setLogLevel(args)
	case "write_flutter_log":
		return writeFlutterLog(args)
	// In-app update (download + install + relaunch).
	case "install_app":
		return installApp(args)
	// Match the correct release asset for this platform (Go-side, not frontend).
	case "match_platform_asset":
		return matchPlatformAsset(args)
	// P2P LAN peer discovery and control.
	case "get_p2p_status":
		return p2pStatus()
	case "set_p2p_enabled":
		return setP2PEnabled(args)
	default:
		return nil, fmt.Errorf("unsupported bridge method %q", method)
	}
}

// --- Storage operations ---

type bucketArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

// listBucketsArgs carries the optional force flag that lets an explicit user
// refresh bypass the negative cache and retry a recently-failed account.
type listBucketsArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Force  bool                              `json:"force,omitempty"`
}

type objectListArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
	Prefix string                            `json:"prefix"`
}

type objectHeadArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
	Key    string                            `json:"key"`
}

type directoryAccessArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
	Prefix string                            `json:"prefix"`
}

type downloadArgs struct {
	Config    storageconfig.RemoteStorageConfig `json:"config"`
	Bucket    string                            `json:"bucket"`
	Key       string                            `json:"key"`
	LocalPath string                            `json:"localPath"`
	TaskID    string                            `json:"taskId"`
}

type transferTaskArgs struct {
	TaskID string `json:"taskId"`
}

// bridgeListBucketsTimeout bounds the per-account bucket list call. S3 client
// construction probes JWanFS gateway reachability and, for an unreachable
// endpoint, can otherwise stall on the OS-level TCP timeout (~1-2 minutes).
// This bound keeps one bad account from blocking the whole multi-account
// load, which Flutter aggregates concurrently with per-account isolation.
const bridgeListBucketsTimeout = 30 * time.Second

func listBuckets(args json.RawMessage) (any, error) {
	var input listBucketsArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	bridgelog.Infof(
		"[bridge/storage] list_buckets storage_type=%q profile=%q force=%t",
		input.Config.StorageType,
		input.Config.DisplayName,
		input.Force,
	)
	ctx, cancel := context.WithTimeout(context.Background(), bridgeListBucketsTimeout)
	defer cancel()
	// Dedup concurrent callers and apply a short negative cache so one
	// unreachable account fails fast (~8s) instead of stalling the multi-account
	// load for 15-45s, and does not re-dial on every page reload. An explicit
	// user refresh (force) bypasses the negative cache so a fixed account can be
	// retried immediately.
	backend := storageops.ForConfig(input.Config)
	return storageops.ListBucketsDedup(ctx, input.Config, backend.ListBuckets, input.Force)
}

func listObjects(args json.RawMessage) (any, error) {
	var input objectListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if page, handled, err := metadataListFunc(objectPageArgs{
		Config: input.Config, Bucket: input.Bucket, Prefix: input.Prefix, PageSize: 1000,
	}); handled || err != nil {
		if err != nil {
			return nil, err
		}
		return objectInfosFromWire(page.Items), nil
	}
	page, err := storageops.ForConfig(input.Config).ListObjectsPage(
		context.Background(),
		input.Bucket,
		input.Prefix,
		"",
		1000,
	)
	if err != nil {
		return nil, err
	}
	return page.Items, nil
}

func headObject(args json.RawMessage) (any, error) {
	var input objectHeadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if item, handled, err := metadataHeadFunc(input); handled || err != nil {
		return item, err
	}
	return storageops.ForConfig(input.Config).HeadObject(context.Background(), input.Bucket, input.Key)
}

func directoryAccess(args json.RawMessage) (any, error) {
	var input directoryAccessArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageops.ForConfig(input.Config).DirectoryAccess(context.Background(), input.Bucket, input.Prefix)
}

func downloadFile(args json.RawMessage) (any, error) {
	var input downloadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).DownloadFile(
		context.Background(),
		input.Bucket,
		input.Key,
		input.LocalPath,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func listTransferJobs() (any, error) {
	return s3ops.ListTransferSnapshots(), nil
}

func cancelTransfer(args json.RawMessage) (any, error) {
	var input transferTaskArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if input.TaskID == "" {
		return nil, fmt.Errorf("missing transfer task id")
	}
	if bucketmount.CancelQueuedTransfer(input.TaskID) {
		return map[string]any{"ok": true}, nil
	}
	return map[string]any{"ok": s3ops.CancelTransfer(input.TaskID)}, nil
}

func triggerTransfer(args json.RawMessage) (any, error) {
	var input transferTaskArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if input.TaskID == "" {
		return nil, fmt.Errorf("missing transfer task id")
	}
	return map[string]any{"ok": bucketmount.TriggerQueuedTransfer(input.TaskID)}, nil
}
