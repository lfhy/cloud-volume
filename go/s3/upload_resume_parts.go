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
	// Detach from the parent's deadline so a slow part does not poison its
	// siblings, then apply the part-size-aware timeout on the detached base.
	timeout := uploadTimeoutForBytes(partSize)
	return context.WithTimeout(context.WithoutCancel(ctx), timeout)
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

	// The concurrent pool only cancels on user-initiated failures. Per-part
	// timeouts are now isolated inside uploadSinglePendingPart (detached from
	// this ctx), so a slow part no longer cancels its siblings through ctx.
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
				// Honor user cancellation between parts, but do NOT let the
				// shared ctx become the per-part deadline.
				if ctx.Err() != nil {
					return
				}
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
	totalParts := partCount(state.FileSize, state.PartSize)
	if taskID != "" {
		SetTransferCurrentPart(taskID, key, part.partNumber, totalParts, offset, part.size)
	}
	section := io.NewSectionReader(file, offset, part.size)
	partInfo := resumablePartInfo{
		PartNumber: part.partNumber,
		Size:       part.size,
	}
	// Each attempt rebuilds the progress-wrapped body so backoff retries start
	// from the part's beginning and the progress counter stays accurate.
	perAttemptTimeout := uploadTimeoutForBytes(part.size)
	upload := func(attemptCtx context.Context) error {
		// Reset the section reader for each attempt so retries re-upload the
		// whole part instead of resuming from the previous attempt's offset.
		if _, err := section.Seek(0, io.SeekStart); err != nil {
			return err
		}
		var body io.ReadSeeker = section
		if taskID != "" {
			body = &contextReadSeeker{
				ctx:    attemptCtx,
				reader: section,
				onRead: func(n int) { AdvanceTransferCurrentPart(taskID, part.partNumber, int64(n)) },
			}
		}
		partOut, err := client.UploadPart(attemptCtx, &s3.UploadPartInput{
			Bucket:        &bucket,
			Key:           &key,
			UploadId:      &state.UploadID,
			PartNumber:    aws.Int32(part.partNumber),
			Body:          body,
			ContentLength: aws.Int64(part.size),
		})
		if err != nil {
			return err
		}
		partInfo.ETag = aws.ToString(partOut.ETag)
		return nil
	}
	if err := retryUploadPartWithTimeout(ctx, perAttemptTimeout, upload); err != nil {
		return resumablePartInfo{}, err
	}
	return partInfo, nil
}
