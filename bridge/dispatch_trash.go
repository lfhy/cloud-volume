package main

import (
	"encoding/json"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

// Trash bridge methods expose app-level soft delete and recovery flows to Flutter.
type trashListArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
}

type trashMutationArgs struct {
	Config  storageconfig.RemoteStorageConfig `json:"config"`
	Bucket  string                            `json:"bucket"`
	TrashID string                            `json:"trashId"`
}

func listTrash(args json.RawMessage) (any, error) {
	var input trashListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	page, err := storageops.ForConfig(input.Config).ListTrashPage(
		nil,
		input.Bucket,
		"",
		1000,
	)
	if err != nil {
		return nil, err
	}
	return page.Items, nil
}

func restoreTrashItem(args json.RawMessage) (any, error) {
	var input trashMutationArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).RestoreTrashItem(
		nil,
		input.Bucket,
		input.TrashID,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func deleteTrashItem(args json.RawMessage) (any, error) {
	var input trashMutationArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).DeleteTrashItem(
		nil,
		input.Bucket,
		input.TrashID,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func clearTrash(args json.RawMessage) (any, error) {
	var input trashListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).ClearTrash(nil, input.Bucket); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}
