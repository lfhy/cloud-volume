// Shared download tracking keeps non-S3 providers visible in RemoteTask views.
package storage

import (
	"context"
	"io"
	"strings"

	s3ops "remote-storage/go/s3"
)

type trackedDownloadReader struct {
	ctx    context.Context
	reader io.Reader
	taskID string
}

func (r *trackedDownloadReader) Read(p []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	n, err := r.reader.Read(p)
	if n > 0 {
		s3ops.AdvanceTransfer(r.taskID, int64(n))
	}
	return n, err
}

// beginTrackedDownload returns an operation context and a terminal reporter.
// An empty task ID preserves the lightweight direct-provider path.
func beginTrackedDownload(
	ctx context.Context,
	bucket, key, localPath string,
	total int64,
	taskID, profileID string,
) (context.Context, func(error)) {
	if ctx == nil {
		ctx = context.Background()
	}
	if strings.TrimSpace(taskID) == "" {
		return ctx, func(error) {}
	}
	trackedCtx, cancel := context.WithCancel(ctx)
	s3ops.StartQueuedTransfer(taskID, "download", bucket, key, localPath, total, cancel)
	s3ops.SetTransferProfile(taskID, profileID)
	return trackedCtx, func(err error) {
		s3ops.FinishQueuedTransfer(taskID, err)
		cancel()
	}
}
