// Multipart upload resume helpers keep mount writeback uploads resumable across failures.
package s3

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

type resumableUploadState struct {
	Bucket          string              `json:"bucket"`
	Key             string              `json:"key"`
	LocalPath       string              `json:"localPath"`
	FileSize        int64               `json:"fileSize"`
	FileModUnixNano int64               `json:"fileModUnixNano"`
	PartSize        int64               `json:"partSize"`
	UploadID        string              `json:"uploadId"`
	CompletedParts  []resumablePartInfo `json:"completedParts"`
}

type resumablePartInfo struct {
	PartNumber int32  `json:"partNumber"`
	ETag       string `json:"etag"`
	Size       int64  `json:"size"`
}

// UploadFileContextResumable uploads a local file with resumable multipart state.
func UploadFileContextResumable(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key,
	localPath,
	taskID string,
	uploadWorkers int,
) (err error) {
	client := NewClient(cfg)
	file, err := os.Open(localPath)
	if err != nil {
		return fmt.Errorf("open local file: %w", err)
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return fmt.Errorf("stat local file: %w", err)
	}
	if ctx == nil {
		ctx = Ctx()
	}
	if taskID != "" {
		var cancel context.CancelFunc
		ctx, cancel = context.WithCancel(ctx)
		startTransfer(taskID, "upload", bucket, key, localPath, info.Size(), cancel)
		SetTransferProfile(taskID, cfg.ProfileID)
		defer func() { finishTransfer(taskID, err) }()
	}

	if info.Size() <= multipartUploadThreshold {
		_ = discardResumableUploadState(context.Background(), client, localPath)
		return uploadWholeObject(ctx, client, bucket, key, localPath, file, info.Size(), taskID)
	}

	state, err := loadOrCreateResumableUploadState(
		ctx,
		client,
		bucket,
		key,
		localPath,
		info,
	)
	if err != nil {
		return err
	}

	if taskID != "" {
		SeedTransferProgress(taskID, completedUploadBytes(state, info.Size()))
	}

	if err := uploadPendingParts(ctx, client, bucket, key, file, state, taskID, uploadWorkers); err != nil {
		if errors.Is(err, context.Canceled) {
			_ = abortResumableUpload(context.Background(), client, bucket, key, state.UploadID)
			_ = removeResumableUploadState(localPath)
		}
		return err
	}
	if err := completeMultipartUploadWithState(ctx, client, bucket, key, state); err != nil {
		return err
	}
	return removeResumableUploadState(localPath)
}

func loadOrCreateResumableUploadState(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key,
	localPath string,
	info os.FileInfo,
) (*resumableUploadState, error) {
	state, err := readResumableUploadState(localPath)
	if err == nil && resumableUploadStateMatches(state, bucket, key, localPath, info) {
		return state, nil
	}
	if err == nil {
		_ = abortResumableUpload(context.Background(), client, state.Bucket, state.Key, state.UploadID)
		_ = removeResumableUploadState(localPath)
	}
	createOut, err := client.CreateMultipartUpload(ctx, &s3.CreateMultipartUploadInput{
		Bucket: &bucket,
		Key:    &key,
	})
	if err != nil {
		return nil, err
	}
	state = &resumableUploadState{
		Bucket:          bucket,
		Key:             key,
		LocalPath:       localPath,
		FileSize:        info.Size(),
		FileModUnixNano: info.ModTime().UnixNano(),
		PartSize:        chooseMultipartUploadPartSize(info.Size()),
		UploadID:        aws.ToString(createOut.UploadId),
		CompletedParts:  []resumablePartInfo{},
	}
	if err := writeResumableUploadState(localPath, state); err != nil {
		_ = abortResumableUpload(context.Background(), client, bucket, key, state.UploadID)
		return nil, err
	}
	return state, nil
}

func completedUploadBytes(state *resumableUploadState, totalSize int64) int64 {
	var total int64
	for _, part := range state.CompletedParts {
		total += part.Size
	}
	if total > totalSize {
		return totalSize
	}
	return total
}

func completedPartMap(state *resumableUploadState) map[int32]resumablePartInfo {
	result := make(map[int32]resumablePartInfo, len(state.CompletedParts))
	for _, part := range state.CompletedParts {
		result[part.PartNumber] = part
	}
	return result
}

func upsertCompletedPart(state *resumableUploadState, next resumablePartInfo) {
	for index, part := range state.CompletedParts {
		if part.PartNumber != next.PartNumber {
			continue
		}
		state.CompletedParts[index] = next
		return
	}
	state.CompletedParts = append(state.CompletedParts, next)
}

func resumableUploadStateMatches(
	state *resumableUploadState,
	bucket,
	key,
	localPath string,
	info os.FileInfo,
) bool {
	partSize := chooseMultipartUploadPartSize(info.Size())
	if state != nil && state.PartSize > 0 {
		partSize = state.PartSize
	}
	return state != nil &&
		state.Bucket == bucket &&
		state.Key == key &&
		state.LocalPath == localPath &&
		state.FileSize == info.Size() &&
		state.FileModUnixNano == info.ModTime().UnixNano() &&
		state.PartSize == partSize &&
		state.UploadID != ""
}

func readResumableUploadState(localPath string) (*resumableUploadState, error) {
	data, err := os.ReadFile(uploadStatePath(localPath))
	if err != nil {
		return nil, err
	}
	var state resumableUploadState
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, err
	}
	if state.PartSize <= 0 {
		state.PartSize = legacyMultipartUploadPartSize
	}
	return &state, nil
}

func writeResumableUploadState(localPath string, state *resumableUploadState) error {
	data, err := json.Marshal(state)
	if err != nil {
		return err
	}
	return os.WriteFile(uploadStatePath(localPath), data, 0o644)
}

func removeResumableUploadState(localPath string) error {
	err := os.Remove(uploadStatePath(localPath))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func uploadStatePath(localPath string) string {
	return localPath + ".uploading.json"
}
