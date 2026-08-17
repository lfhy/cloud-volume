// Page mutation handlers use metadata first and retain direct fallback only for legacy profiles.
package main

import (
	"context"
	"encoding/json"
	"strings"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	bucketmetadata "remote-storage/go/mount/metadata"
	storageops "remote-storage/go/storage"
)

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
	Permanent   bool                              `json:"permanent"`
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

func createDirectory(args json.RawMessage) (any, error) {
	var input createDirectoryArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	path := joinChildPath(input.Prefix, input.Name)
	var projection bucketmetadata.PathProjection
	if handled, err := metadataMutationFunc(metadataMutationRequest{
		Kind: metadataMutationCreateDirectory, Config: input.Config, Bucket: input.Bucket, Path: path, Projection: &projection,
	}); handled || err != nil {
		if err != nil {
			return nil, err
		}
		bucketmount.ProjectMetadataUpload(input.Config, input.Bucket, projection, true)
		return map[string]any{"ok": true}, nil
	}
	if err := storageops.ForConfig(input.Config).CreateDirectory(
		context.Background(), input.Bucket, input.Prefix, input.Name,
	); err != nil {
		return nil, err
	}
	bucketmount.NotifyExternalUpload(input.Config, input.Bucket, path, true)
	broadcastPeerMutation(input.Config, input.Bucket, path, "upload")
	return map[string]any{"ok": true}, nil
}

func deleteObject(args json.RawMessage) (any, error) {
	var input objectMutationArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	var projection bucketmetadata.PathProjection
	if handled, err := metadataMutationFunc(metadataMutationRequest{
		Kind: metadataMutationDelete, Config: input.Config, Bucket: input.Bucket, Path: input.Key,
		TaskID: input.TaskID, Permanent: input.Permanent, Projection: &projection,
	}); handled || err != nil {
		if err != nil {
			return nil, err
		}
		bucketmount.ProjectMetadataDelete(input.Config, input.Bucket, projection, input.IsDirectory)
		return map[string]any{"ok": true}, nil
	}
	backend := storageops.ForConfig(input.Config)
	deleteFn := backend.DeleteObject
	if input.Permanent {
		deleteFn = backend.DeleteObjectHard
	}
	if err := deleteFn(context.Background(), input.Bucket, input.Key, input.IsDirectory, input.TaskID); err != nil {
		return nil, err
	}
	bucketmount.NotifyExternalDelete(input.Config, input.Bucket, input.Key, input.IsDirectory)
	broadcastPeerMutation(input.Config, input.Bucket, input.Key, "delete")
	return map[string]any{"ok": true}, nil
}

func renameObject(args json.RawMessage) (any, error) {
	var input renameObjectArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	newPath := joinChildPath(parentDirectoryOf(input.Key), input.NewName)
	var projection bucketmetadata.PathProjection
	if handled, err := metadataMutationFunc(metadataMutationRequest{
		Kind: metadataMutationRename, Config: input.Config, Bucket: input.Bucket, Path: input.Key, TargetPath: newPath, Projection: &projection,
	}); handled || err != nil {
		if err != nil {
			return nil, err
		}
		bucketmount.ProjectMetadataRename(input.Config, input.Bucket, input.Key, projection, input.IsDirectory)
		return map[string]any{"ok": true}, nil
	}
	if err := storageops.ForConfig(input.Config).RenameObject(
		context.Background(), input.Bucket, input.Key, input.IsDirectory, input.NewName,
	); err != nil {
		return nil, err
	}
	bucketmount.NotifyExternalRename(input.Config, input.Bucket, input.Key, newPath, input.IsDirectory)
	broadcastPeerMutation(input.Config, input.Bucket, newPath, "rename")
	return map[string]any{"ok": true}, nil
}

func uploadFile(args json.RawMessage) (any, error) {
	var input uploadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	var projection bucketmetadata.PathProjection
	if handled, err := metadataMutationFunc(metadataMutationRequest{
		Kind: metadataMutationWriteFile, Config: input.Config, Bucket: input.Bucket, Path: input.Key,
		LocalPath: input.LocalPath, TaskID: input.TaskID, Projection: &projection,
	}); handled || err != nil {
		if err != nil {
			return nil, err
		}
		bucketmount.ProjectMetadataUpload(input.Config, input.Bucket, projection, false)
		return map[string]any{"ok": true}, nil
	}
	backend := storageops.ForConfig(input.Config)
	if err := backend.UploadFile(context.Background(), input.Bucket, input.Key, input.LocalPath, input.TaskID); err != nil {
		return nil, err
	}
	bucketmount.NotifyExternalUpload(input.Config, input.Bucket, input.Key, false)
	if info, err := backend.HeadObject(context.Background(), input.Bucket, input.Key); err == nil {
		bucketmount.RememberPeerContent(input.Config, input.Bucket, input.Key, input.LocalPath, info)
	}
	broadcastPeerMutation(input.Config, input.Bucket, input.Key, "upload")
	return map[string]any{"ok": true}, nil
}

func uploadDirectory(args json.RawMessage) (any, error) {
	var input uploadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := rejectUnsupportedMetadataMutation(input.Config, "directory upload"); err != nil {
		return nil, err
	}
	backend := storageops.ForConfig(input.Config)
	go func() {
		_ = storageops.UploadDirectory(context.Background(), backend, input.Bucket, input.Key, input.LocalPath, input.TaskID)
		bucketmount.NotifyExternalUpload(input.Config, input.Bucket, input.Key, true)
		broadcastPeerMutation(input.Config, input.Bucket, input.Key, "upload")
	}()
	bucketmount.NotifyExternalUpload(input.Config, input.Bucket, parentDirectoryOf(input.Key), false)
	return map[string]any{"ok": true}, nil
}

func parentDirectoryOf(key string) string {
	trimmed := strings.Trim(strings.TrimSpace(key), "/")
	idx := strings.LastIndex(trimmed, "/")
	if idx < 0 {
		return ""
	}
	return trimmed[:idx]
}

func joinChildPath(parent, name string) string {
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
