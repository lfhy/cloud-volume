// Metadata mutation routing makes page writes use the durable inode journal.
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

	bucketmetadata "remote-storage/go/mount/metadata"

	storageconfig "remote-storage/go/config"
)

type metadataMutationKind uint8

const (
	metadataMutationCreateDirectory metadataMutationKind = iota + 1
	metadataMutationWriteFile
	metadataMutationRename
	metadataMutationDelete
)

// metadataMutationRequest is the common page-to-inode write contract.
type metadataMutationRequest struct {
	Kind       metadataMutationKind
	Config     storageconfig.RemoteStorageConfig
	Bucket     string
	Path       string
	TargetPath string
	LocalPath  string
	TaskID     string
	Permanent  bool
	Projection *bucketmetadata.PathProjection
}

// metadataMutationFunc allows bridge tests to replace DefaultManager wiring.
var metadataMutationFunc = mutateFromMetadata

func swapMetadataMutationFunc(next func(metadataMutationRequest) (bool, error)) func(metadataMutationRequest) (bool, error) {
	previous := metadataMutationFunc
	metadataMutationFunc = next
	return previous
}

// mutateFromMetadata returns handled=false only when the saved profile lacks
// the immutable identity required to open a durable metadata namespace.
func mutateFromMetadata(input metadataMutationRequest) (bool, error) {
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return true, err
	}
	handle, err := manager.Acquire(input.Config, input.Bucket)
	if errors.Is(err, bucketmetadata.ErrNoProfileID) {
		return false, nil
	}
	if err != nil {
		return true, err
	}
	defer manager.Release(handle)
	return true, mutateViaHandle(handle, input)
}

func mutateViaHandle(handle *bucketmetadata.AcquireHandle, input metadataMutationRequest) error {
	if handle == nil || handle.Service == nil {
		return fmt.Errorf("metadata: mutation handle is unavailable")
	}
	service := handle.Service
	path := trimPrefixPath(input.Path)
	options := bucketmetadata.WriteOptions{Origin: "page", TaskID: input.TaskID, HardDelete: input.Permanent}
	switch input.Kind {
	case metadataMutationCreateDirectory:
		_, projection, err := service.CreateDirectoryPathWithProjection(context.Background(), path, options)
		setMutationProjection(input, projection)
		return err
	case metadataMutationWriteFile:
		file, err := os.Open(input.LocalPath)
		if err != nil {
			return err
		}
		defer file.Close()
		info, err := file.Stat()
		if err != nil {
			return err
		}
		if info.IsDir() {
			return fmt.Errorf("metadata: upload source is a directory: %s", input.LocalPath)
		}
		options.MTime = info.ModTime().Format("2006-01-02 15:04:05")
		_, _, projection, writeErr := service.WritePathWithProjection(context.Background(), path, file, info.Size(), options)
		setMutationProjection(input, projection)
		err = writeErr
		return err
	case metadataMutationRename:
		projection, err := service.RenamePathWithProjection(context.Background(), path, trimPrefixPath(input.TargetPath), options)
		setMutationProjection(input, projection)
		return err
	case metadataMutationDelete:
		projection, err := service.DeletePathWithProjection(context.Background(), path, options)
		setMutationProjection(input, projection)
		return err
	default:
		return fmt.Errorf("metadata: unsupported page mutation %d", input.Kind)
	}
}

func setMutationProjection(input metadataMutationRequest, projection bucketmetadata.PathProjection) {
	if input.Projection != nil {
		*input.Projection = projection
	}
}

// rejectUnsupportedMetadataMutation keeps a profile-scoped page mutation from
// bypassing the journal until its durable operation semantics are implemented.
func rejectUnsupportedMetadataMutation(config storageconfig.RemoteStorageConfig, operation string) error {
	if strings.TrimSpace(config.ProfileID) == "" {
		return nil
	}
	return fmt.Errorf("metadata: %s is not supported for profile-scoped namespaces", operation)
}
