// Page mutation tests pin the bridge's metadata-first journal contract.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	bucketmetadata "remote-storage/go/mount/metadata"

	storageconfig "remote-storage/go/config"
)

func TestPageMutationsUseMetadataJournalAndDrainAfterRelease(t *testing.T) {
	backend := newBridgeFakeBackend()
	manager := bucketmetadata.NewManager(t.TempDir())
	defer manager.RemoveAllForTest()
	config := storageconfig.RemoteStorageConfig{
		ProfileID: "bridge-page-write-profile", CacheDirectory: t.TempDir(), WritebackQuietSeconds: 1,
	}
	restore := swapMetadataMutationFunc(metadataMutationWithBackend(manager, backend))
	defer swapMetadataMutationFunc(restore)

	invokePageMutation(t, createDirectory, createDirectoryArgs{Config: config, Bucket: "bucket", Name: "docs"})
	invokePageMutation(t, createDirectory, createDirectoryArgs{Config: config, Bucket: "bucket", Name: "archive"})
	localPath := filepath.Join(t.TempDir(), "draft.txt")
	if err := os.WriteFile(localPath, []byte("payload"), 0o644); err != nil {
		t.Fatal(err)
	}
	invokePageMutation(t, uploadFile, uploadArgs{
		Config: config, Bucket: "bucket", Key: "docs/draft.txt", LocalPath: localPath, TaskID: "page-upload",
	})
	invokePageMutation(t, renameObject, renameObjectArgs{
		Config: config, Bucket: "bucket", Key: "docs/draft.txt", NewName: "final.txt",
	})
	invokePageMutation(t, moveObject, objectTransferArgs{
		Config: config, Bucket: "bucket", SourceKey: "docs/final.txt", TargetKey: "archive/final.txt", TaskID: "page-move",
	})

	handle, err := manager.AcquireWithBackend(config, "bucket", backend)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := handle.Service.StatPath(context.Background(), "archive/final.txt"); err != nil {
		t.Fatalf("page move did not update Desired tree: %v", err)
	}
	handle.Release()
	invokePageMutation(t, deleteObject, objectMutationArgs{
		Config: config, Bucket: "bucket", Key: "archive/final.txt", TaskID: "page-delete", Permanent: true,
	})

	backend.mu.Lock()
	remoteCount := len(backend.objects)
	backend.mu.Unlock()
	if remoteCount != 0 {
		t.Fatalf("page admission mutated provider synchronously: %+v", backend.objects)
	}
	if services := manager.List(); len(services) != 1 {
		t.Fatalf("page handles released a pending namespace: %+v", services)
	}
	if err := manager.DrainAll(context.Background()); err != nil {
		t.Fatal(err)
	}
	backend.mu.Lock()
	hardDeletes := backend.hardDeleteCalls
	_, fileExists := backend.objects["archive/final.txt"]
	backend.mu.Unlock()
	if hardDeletes != 1 || fileExists {
		t.Fatalf("permanent page delete did not converge: hard=%d file=%t", hardDeletes, fileExists)
	}
	finalHandle, err := manager.AcquireWithBackend(config, "bucket", backend)
	if err != nil {
		t.Fatal(err)
	}
	finalHandle.Release()
	if services := manager.List(); len(services) != 0 {
		t.Fatalf("idle page namespace was not pruned: %+v", services)
	}
}

func TestProfileScopedCopyAndDirectoryUploadFailClosed(t *testing.T) {
	config := storageconfig.RemoteStorageConfig{ProfileID: "bridge-copy-profile"}
	copyArgs, err := json.Marshal(objectTransferArgs{Config: config, Bucket: "bucket", SourceKey: "old", TargetKey: "new"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := copyObject(copyArgs); err == nil || !strings.Contains(err.Error(), "not supported") {
		t.Fatalf("profile-scoped copy error = %v", err)
	}
	directoryArgs, err := json.Marshal(uploadArgs{Config: config, Bucket: "bucket", Key: "dir", LocalPath: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := uploadDirectory(directoryArgs); err == nil || !strings.Contains(err.Error(), "not supported") {
		t.Fatalf("profile-scoped directory upload error = %v", err)
	}
}

func TestMetadataMutationFallsBackOnlyWithoutProfileID(t *testing.T) {
	handled, err := mutateFromMetadata(metadataMutationRequest{
		Kind:   metadataMutationCreateDirectory,
		Config: storageconfig.RemoteStorageConfig{},
		Bucket: "bucket",
		Path:   "docs",
	})
	if err != nil || handled {
		t.Fatalf("missing profileId mutation handled=%t err=%v", handled, err)
	}
}

func metadataMutationWithBackend(
	manager *bucketmetadata.Manager, backend bucketmetadata.Backend,
) func(metadataMutationRequest) (bool, error) {
	return func(input metadataMutationRequest) (bool, error) {
		handle, err := manager.AcquireWithBackend(input.Config, input.Bucket, backend)
		if errors.Is(err, bucketmetadata.ErrNoProfileID) {
			return false, nil
		}
		if err != nil {
			return true, err
		}
		defer handle.Release()
		return true, mutateViaHandle(handle, input)
	}
}

func invokePageMutation(t *testing.T, handler func(json.RawMessage) (any, error), input any) {
	t.Helper()
	args, err := json.Marshal(input)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := handler(args); err != nil {
		t.Fatal(err)
	}
}
