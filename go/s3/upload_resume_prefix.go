// Resumable multipart prefix uploads let Linux autosync preflush completed sequential parts.
package s3

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"

	storageconfig "remote-storage/go/config"
)

// ChooseMultipartUploadPartSize exposes the shared large-file part planner to mount callers.
func ChooseMultipartUploadPartSize(totalSize int64) int64 {
	return chooseMultipartUploadPartSize(totalSize)
}

// DiscardResumableUpload removes local multipart state and aborts any remote multipart upload.
func DiscardResumableUpload(
	cfg storageconfig.RemoteStorageConfig,
	localPath string,
) error {
	return discardResumableUploadState(context.Background(), NewClient(cfg), localPath)
}

// UploadFilePrefixContextResumable uploads only the fully written prefix parts and leaves the multipart open.
func UploadFilePrefixContextResumable(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key,
	localPath string,
	info os.FileInfo,
	readySize int64,
	uploadWorkers int,
) error {
	if readySize <= 0 || info == nil {
		return nil
	}
	client := NewClient(cfg)
	file, err := os.Open(localPath)
	if err != nil {
		return fmt.Errorf("open local file: %w", err)
	}
	defer file.Close()

	if ctx == nil {
		ctx = Ctx()
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
	readyParts := partCount(readySize, state.PartSize)
	completed := completedPartMap(state)
	pending := pendingUploadParts(completed, readyParts, readySize, state.PartSize)
	if len(pending) == 0 {
		return nil
	}
	return uploadPendingPartsConcurrent(ctx, client, bucket, key, file, state, "", pending, uploadWorkers)
}

func sortCompletedParts(parts []resumablePartInfo) []types.CompletedPart {
	out := make([]types.CompletedPart, 0, len(parts))
	sort.Slice(parts, func(i, j int) bool {
		return parts[i].PartNumber < parts[j].PartNumber
	})
	for _, part := range parts {
		etag := part.ETag
		partNumber := part.PartNumber
		out = append(out, types.CompletedPart{
			ETag:       &etag,
			PartNumber: &partNumber,
		})
	}
	return out
}

func discardResumableUploadState(
	ctx context.Context,
	client *s3.Client,
	localPath string,
) error {
	state, err := readResumableUploadState(localPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	_ = abortResumableUpload(ctx, client, state.Bucket, state.Key, state.UploadID)
	return removeResumableUploadState(localPath)
}

func abortResumableUpload(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key,
	uploadID string,
) error {
	if uploadID == "" {
		return nil
	}
	_, err := client.AbortMultipartUpload(ctx, &s3.AbortMultipartUploadInput{
		Bucket:   &bucket,
		Key:      &key,
		UploadId: &uploadID,
	})
	return err
}

func completeMultipartUploadWithState(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	state *resumableUploadState,
) error {
	parts := sortCompletedParts(state.CompletedParts)
	_, err := client.CompleteMultipartUpload(ctx, &s3.CompleteMultipartUploadInput{
		Bucket:   &bucket,
		Key:      &key,
		UploadId: &state.UploadID,
		MultipartUpload: &types.CompletedMultipartUpload{
			Parts: parts,
		},
	})
	return err
}

func uploadWholeObject(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key,
	localPath string,
	file *os.File,
	totalBytes int64,
	taskID string,
) error {
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return err
	}
	body := io.Reader(file)
	if taskID != "" {
		body = &contextReader{
			ctx:    ctx,
			reader: file,
			onRead: func(n int) { advanceTransfer(taskID, int64(n)) },
		}
	}
	_, err := client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: &bucket,
		Key:    &key,
		Body:   body,
	})
	return err
}
