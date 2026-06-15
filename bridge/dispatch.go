package main

import (
	"context"
	"encoding/json"
	"fmt"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	s3ops "remote-storage/go/s3"
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
	case "delete_profile":
		return deleteProfile(args)
	// S3 operations.
	case "list_buckets":
		return listBuckets(args)
	case "list_objects":
		return listObjects(args)
	case "list_object_page":
		return listObjectPage(args)
	case "head_object":
		return headObject(args)
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
		config, _ = storageconfig.LoadProfile(profiles[0].Name)
		p, _ := storageconfig.ProfileConfigPath(profiles[0].Name)
		configPath = p
	} else {
		config = storageconfig.DefaultConfig()
		p, _ := storageconfig.DefaultConfigPath()
		configPath = p
	}

	return storageconfig.BootstrapState{
		ConfigPath: configPath,
		Configured: config.IsConfigured(),
		Config:     config,
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
	return storageconfig.LoadProfile(input.Name)
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

// --- S3 operations ---

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
	return s3ops.ListBuckets(input.Config)
}

func listObjects(args json.RawMessage) (any, error) {
	var input objectListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return s3ops.ListObjects(input.Config, input.Bucket, input.Prefix)
}

func headObject(args json.RawMessage) (any, error) {
	var input objectHeadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return s3ops.HeadObject(input.Config, input.Bucket, input.Key)
}

func createDirectory(args json.RawMessage) (any, error) {
	var input createDirectoryArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := s3ops.CreateDirectory(
		input.Config,
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
	if err := s3ops.DeleteObjectContextWithTask(
		context.Background(),
		input.Config,
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
	if err := s3ops.RenameObject(
		input.Config,
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
	if err := s3ops.UploadFile(
		input.Config,
		input.Bucket,
		input.Key,
		input.LocalPath,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func downloadFile(args json.RawMessage) (any, error) {
	var input downloadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := s3ops.DownloadFile(
		input.Config,
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
