package main

import (
	"context"
	"encoding/json"
	"fmt"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	s3ops "remote-storage/go/s3"
	storageops "remote-storage/go/storage"
)

type saveConfigArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

type profileArgs struct {
	Name   string                            `json:"name"`
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

type profileNameArgs struct {
	Name string `json:"name"`
}

// invokeBridgeMethod translates JSON RPC-like method names into typed Go operations.
func invokeBridgeMethod(method string, args json.RawMessage) (any, error) {
	switch method {
	case "load_bootstrap_state":
		return loadBootstrapState()
	case "save_config":
		return saveConfig(args)
	case "migrate_default":
		return migrateAndBootstrap()
	// Profile management.
	case "list_profiles":
		return listProfiles()
	case "load_profile":
		return loadProfile(args)
	case "save_profile":
		return saveProfile(args)
	case "start_baidu_pan_authorization":
		return startBaiduPanAuthorization()
	case "authorize_baidu_pan":
		return authorizeBaiduPan(args)
	case "delete_profile":
		return deleteProfile(args)
	case "set_active_profile":
		return setActiveProfile(args)
	// Storage operations.
	case "list_buckets":
		return listBuckets(args)
	case "list_objects":
		return listObjects(args)
	case "list_object_page":
		return listObjectPage(args)
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
	case "clear_mount_cache":
		return clearMountCache()
	case "cleanup_stale_windows_processes":
		return cleanupStaleWindowsProcesses()
	default:
		return nil, fmt.Errorf("unsupported bridge method %q", method)
	}
}

func loadBootstrapState() (storageconfig.BootstrapState, error) {
	// Auto-migrate legacy config to profiles dir.
	_ = storageconfig.MigrateDefault()

	profiles, _ := storageconfig.ListProfiles()
	configured := len(profiles) > 0

	var config storageconfig.RemoteStorageConfig
	var configPath string
	if configured {
		activeName := profiles[0].Name
		for _, profile := range profiles {
			if profile.Active {
				activeName = profile.Name
				break
			}
		}
		config, _ = storageconfig.LoadProfile(activeName)
		p, _ := storageconfig.ProfileConfigPath(activeName)
		configPath = p
	} else {
		config = storageconfig.DefaultConfig()
		p, _ := storageconfig.DefaultConfigPath()
		configPath = p
	}
	publicConfig, err := config.WithResolvedCacheDirectory()
	if err != nil {
		return storageconfig.BootstrapState{}, err
	}

	return storageconfig.BootstrapState{
		ConfigPath: configPath,
		Configured: config.IsConfigured(),
		Config:     publicConfig,
		Profiles:   profiles,
	}, nil
}

func migrateAndBootstrap() (storageconfig.BootstrapState, error) {
	_ = storageconfig.MigrateDefault()
	return loadBootstrapState()
}

func saveConfig(args json.RawMessage) (storageconfig.BootstrapState, error) {
	var input saveConfigArgs
	if err := decodeArgs(args, &input); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	// Save to "default" profile.
	if err := storageconfig.SaveProfile("default", input.Config); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	_ = storageconfig.SetActiveProfile("default")
	return loadBootstrapState()
}

// --- Profile management ---

func listProfiles() (any, error) {
	_ = storageconfig.MigrateDefault()
	return storageconfig.ListProfiles()
}

func loadProfile(args json.RawMessage) (any, error) {
	var input profileNameArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	config, err := storageconfig.LoadProfile(input.Name)
	if err != nil {
		return nil, err
	}
	return config.WithResolvedCacheDirectory()
}

func saveProfile(args json.RawMessage) (any, error) {
	var input profileArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.SaveProfile(input.Name, input.Config); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func deleteProfile(args json.RawMessage) (any, error) {
	var input profileNameArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.DeleteProfile(input.Name); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func setActiveProfile(args json.RawMessage) (any, error) {
	var input profileNameArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.SetActiveProfile(input.Name); err != nil {
		return nil, err
	}
	return loadBootstrapState()
}

// --- Storage operations ---

type bucketArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
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

type createDirectoryArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
	Prefix string                            `json:"prefix"`
	Name   string                            `json:"name"`
}

type objectMutationArgs struct {
	Config      storageconfig.RemoteStorageConfig `json:"config"`
	Bucket      string                            `json:"bucket"`
	Key         string                            `json:"key"`
	IsDirectory bool                              `json:"isDirectory"`
	TaskID      string                            `json:"taskId"`
}

type renameObjectArgs struct {
	Config      storageconfig.RemoteStorageConfig `json:"config"`
	Bucket      string                            `json:"bucket"`
	Key         string                            `json:"key"`
	IsDirectory bool                              `json:"isDirectory"`
	NewName     string                            `json:"newName"`
}

type uploadArgs struct {
	Config    storageconfig.RemoteStorageConfig `json:"config"`
	Bucket    string                            `json:"bucket"`
	Key       string                            `json:"key"`
	LocalPath string                            `json:"localPath"`
	TaskID    string                            `json:"taskId"`
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

func listBuckets(args json.RawMessage) (any, error) {
	var input bucketArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageops.ForConfig(input.Config).ListBuckets(context.Background())
}

func listObjects(args json.RawMessage) (any, error) {
	var input objectListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
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
	return storageops.ForConfig(input.Config).HeadObject(context.Background(), input.Bucket, input.Key)
}

func directoryAccess(args json.RawMessage) (any, error) {
	var input directoryAccessArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageops.ForConfig(input.Config).DirectoryAccess(context.Background(), input.Bucket, input.Prefix)
}

func createDirectory(args json.RawMessage) (any, error) {
	var input createDirectoryArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).CreateDirectory(
		context.Background(),
		input.Bucket,
		input.Prefix,
		input.Name,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func deleteObject(args json.RawMessage) (any, error) {
	var input objectMutationArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).DeleteObject(
		context.Background(),
		input.Bucket,
		input.Key,
		input.IsDirectory,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func renameObject(args json.RawMessage) (any, error) {
	var input renameObjectArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).RenameObject(
		context.Background(),
		input.Bucket,
		input.Key,
		input.IsDirectory,
		input.NewName,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func uploadFile(args json.RawMessage) (any, error) {
	var input uploadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).UploadFile(
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

func uploadDirectory(args json.RawMessage) (any, error) {
	var input uploadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	backend := storageops.ForConfig(input.Config)
	go func() {
		_ = storageops.UploadDirectory(
			context.Background(),
			backend,
			input.Bucket,
			input.Key,
			input.LocalPath,
			input.TaskID,
		)
	}()
	return map[string]any{"ok": true}, nil
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
