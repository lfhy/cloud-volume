package main

import (
	"context"
	"encoding/json"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	bucketmetadata "remote-storage/go/mount/metadata"
	storageops "remote-storage/go/storage"
)

// Object transfer bridge methods expose tracked copy/move operations to Flutter.
type objectTransferArgs struct {
	Config      storageconfig.RemoteStorageConfig `json:"config"`
	Bucket      string                            `json:"bucket"`
	SourceKey   string                            `json:"sourceKey"`
	TargetKey   string                            `json:"targetKey"`
	IsDirectory bool                              `json:"isDirectory"`
	TaskID      string                            `json:"taskId"`
}

func copyObject(args json.RawMessage) (any, error) {
	var input objectTransferArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := rejectUnsupportedMetadataMutation(input.Config, "copy"); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).CopyObject(
		context.Background(),
		input.Bucket,
		input.SourceKey,
		input.TargetKey,
		input.IsDirectory,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	// Sync mount caches so the new copy at the target key becomes visible.
	bucketmount.NotifyExternalUpload(input.Config, input.Bucket, input.TargetKey, input.IsDirectory)
	broadcastPeerMutation(input.Config, input.Bucket, input.TargetKey, "upload")
	return map[string]any{"ok": true}, nil
}

func moveObject(args json.RawMessage) (any, error) {
	var input objectTransferArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	var projection bucketmetadata.PathProjection
	if handled, err := metadataMutationFunc(metadataMutationRequest{
		Kind: metadataMutationRename, Config: input.Config, Bucket: input.Bucket,
		Path: input.SourceKey, TargetPath: input.TargetKey, TaskID: input.TaskID, Projection: &projection,
	}); handled || err != nil {
		if err != nil {
			return nil, err
		}
		bucketmount.ProjectMetadataRename(input.Config, input.Bucket, input.SourceKey, projection, input.IsDirectory)
		return map[string]any{"ok": true}, nil
	}
	if err := storageops.ForConfig(input.Config).MoveObject(
		context.Background(),
		input.Bucket,
		input.SourceKey,
		input.TargetKey,
		input.IsDirectory,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	// Sync mount caches: source disappears and target appears.
	bucketmount.NotifyExternalRename(input.Config, input.Bucket, input.SourceKey, input.TargetKey, input.IsDirectory)
	broadcastPeerMutation(input.Config, input.Bucket, input.TargetKey, "rename")
	return map[string]any{"ok": true}, nil
}
