// Multipart upload part planning and concurrent execution tune large writeback throughput.
package s3

import (
	"context"
	"io"
	"runtime"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

const (
	legacyMultipartUploadPartSize  = 8 << 20
	defaultMultipartUploadPartSize = 64 << 20
	multipartUploadThreshold       = 32 << 20
	minMultipartUploadWorkers      = 4
	maxMultipartUploadWorkers      = 10
	minUploadRateBytesPerSec       = 1 << 20
	partUploadGracePeriod          = 2 * time.Minute
	partUploadMinTimeout           = 5 * time.Minute
)

type pendingUploadPart struct {
	partNumber int32
	size       int64
}

func uploadPendingParts(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	file io.ReaderAt,
	state *resumableUploadState,
	taskID string,
	uploadWorkers int,
) error {
	completed := completedPartMap(state)
	totalParts := partCount(state.FileSize, state.PartSize)
	pending := pendingUploadParts(completed, totalParts, state.FileSize, state.PartSize)
	if len(pending) == 0 {
		return nil
	}
	if len(pending) == 1 {
		part, err := uploadSinglePendingPart(ctx, client, bucket, key, file, state, taskID, pending[0])
		if err != nil {
			return err
		}
		upsertCompletedPart(state, part)
		return writeResumableUploadState(state.LocalPath, state)
	}
	return uploadPendingPartsConcurrent(ctx, client, bucket, key, file, state, taskID, pending, uploadWorkers)
}

func chooseMultipartUploadPartSize(totalSize int64) int64 {
	switch {
	case totalSize >= 64<<30:
		return 256 << 20
	case totalSize >= 16<<30:
		return 128 << 20
	default:
		return defaultMultipartUploadPartSize
	}
}

func chooseMultipartUploadWorkers(_ int64, _ int64, requested int) int {
	if requested > 0 {
		return requested
	}
	workers := runtime.NumCPU()
	if workers < minMultipartUploadWorkers {
		return minMultipartUploadWorkers
	}
	if workers > maxMultipartUploadWorkers {
		return maxMultipartUploadWorkers
	}
	return workers
}

func partCount(totalSize int64, partSize int64) int32 {
	if totalSize <= 0 {
		return 0
	}
	if partSize <= 0 {
		partSize = defaultMultipartUploadPartSize
	}
	count := totalSize / partSize
	if totalSize%partSize != 0 {
		count++
	}
	return int32(count)
}

func partSizeFor(partNumber int32, totalSize int64, partSize int64) int64 {
	if partSize <= 0 {
		partSize = defaultMultipartUploadPartSize
	}
	offset := int64(partNumber-1) * partSize
	remaining := totalSize - offset
	if remaining > partSize {
		return partSize
	}
	return remaining
}

func withPerPartUploadTimeout(ctx context.Context, partSize int64) (context.Context, context.CancelFunc) {
	if ctx == nil {
		ctx = context.Background()
	}
	timeout := uploadTimeoutForBytes(partSize)
	return context.WithTimeout(ctx, timeout)
}

func uploadTimeoutForBytes(size int64) time.Duration {
	if size <= 0 {
		return partUploadMinTimeout
	}
	seconds := size / minUploadRateBytesPerSec
	if size%minUploadRateBytesPerSec != 0 {
		seconds++
	}
	timeout := time.Duration(seconds)*time.Second + partUploadGracePeriod
	if timeout < partUploadMinTimeout {
		return partUploadMinTimeout
	}
	return timeout
}

func pendingUploadParts(
	completed map[int32]resumablePartInfo,
	totalParts int32,
	totalSize int64,
	partSize int64,
) []pendingUploadPart {
	parts := make([]pendingUploadPart, 0, totalParts)
	for index := int32(1); index <= totalParts; index++ {
		expectedSize := partSizeFor(index, totalSize, partSize)
		if part, ok := completed[index]; ok && part.Size == expectedSize {
			continue
		}
		parts = append(parts, pendingUploadPart{
			partNumber: index,
			size:       expectedSize,
		})
	}
	return parts
}

func uploadPendingPartsConcurrent(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	file io.ReaderAt,
	state *resumableUploadState,
	taskID string,
	pending []pendingUploadPart,
	uploadWorkers int,
) error {
	workerCount := chooseMultipartUploadWorkers(state.FileSize, state.PartSize, uploadWorkers)
	if len(pending) < workerCount {
		workerCount = len(pending)
	}

	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	partCh := make(chan pendingUploadPart)
	resultCh := make(chan resumablePartInfo, len(pending))
	errCh := make(chan error, 1)
	var wg sync.WaitGroup

	for worker := 0; worker < workerCount; worker++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for part := range partCh {
				completedPart, err := uploadSinglePendingPart(
					ctx,
					client,
					bucket,
					key,
					file,
					state,
					taskID,
					part,
				)
				if err != nil {
					select {
					case errCh <- err:
						cancel()
					default:
					}
					return
				}
				select {
				case resultCh <- completedPart:
				case <-ctx.Done():
					return
				}
			}
		}()
	}

	go func() {
		defer close(partCh)
		for _, part := range pending {
			select {
			case partCh <- part:
			case <-ctx.Done():
				return
			}
		}
	}()

	completedCount := 0
	for completedCount < len(pending) {
		select {
		case err := <-errCh:
			wg.Wait()
			return err
		case part := <-resultCh:
			upsertCompletedPart(state, part)
			if err := writeResumableUploadState(state.LocalPath, state); err != nil {
				cancel()
				wg.Wait()
				return err
			}
			completedCount++
		}
	}
	cancel()
	wg.Wait()
	return nil
}

func uploadSinglePendingPart(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	file io.ReaderAt,
	state *resumableUploadState,
	taskID string,
	part pendingUploadPart,
) (resumablePartInfo, error) {
	offset := int64(part.partNumber-1) * state.PartSize
	section := io.NewSectionReader(file, offset, part.size)
	body := io.ReadSeeker(section)
	if taskID != "" {
		body = &contextReadSeeker{
			ctx:    ctx,
			reader: section,
			onRead: func(n int) { advanceTransfer(taskID, int64(n)) },
		}
	}
	partCtx, cancel := withPerPartUploadTimeout(ctx, part.size)
	defer cancel()

	partOut, err := client.UploadPart(partCtx, &s3.UploadPartInput{
		Bucket:        &bucket,
		Key:           &key,
		UploadId:      &state.UploadID,
		PartNumber:    aws.Int32(part.partNumber),
		Body:          body,
		ContentLength: aws.Int64(part.size),
	})
	if err != nil {
		return resumablePartInfo{}, err
	}
	return resumablePartInfo{
		PartNumber: part.partNumber,
		ETag:       aws.ToString(partOut.ETag),
		Size:       part.size,
	}, nil
}
