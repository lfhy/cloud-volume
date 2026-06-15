package main

import (
	"context"
	"encoding/json"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	storageops "remote-storage/go/storage"
)

// Paging bridge methods expose continuation-token listing for long directories and trash views.
type objectPageArgs struct {
	Config    storageconfig.RemoteStorageConfig `json:"config"`
	Bucket    string                            `json:"bucket"`
	Prefix    string                            `json:"prefix"`
	NextToken string                            `json:"nextToken"`
	PageSize  int32                             `json:"pageSize"`
}

type trashPageArgs struct {
	Config    storageconfig.RemoteStorageConfig `json:"config"`
	Bucket    string                            `json:"bucket"`
	NextToken string                            `json:"nextToken"`
	PageSize  int32                             `json:"pageSize"`
}

func listObjectPage(args json.RawMessage) (any, error) {
	var input objectPageArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if input.Config.Normalized().StorageType != storageconfig.StorageTypeWebDAV {
		if page, handled, err := bucketmount.ListMountedObjectPage(
			input.Config,
			input.Bucket,
			input.Prefix,
			input.NextToken,
			input.PageSize,
		); handled || err != nil {
			return page, err
		}
	}
	return storageops.ForConfig(input.Config).ListObjectsPage(
		context.Background(),
		input.Bucket,
		input.Prefix,
		input.NextToken,
		input.PageSize,
	)
}

func listTrashPage(args json.RawMessage) (any, error) {
	var input trashPageArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageops.ForConfig(input.Config).ListTrashPage(
		context.Background(),
		input.Bucket,
		input.NextToken,
		input.PageSize,
	)
}
