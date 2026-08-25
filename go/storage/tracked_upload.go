// Shared upload tracking keeps provider backends aligned with the transfer queue.
package storage

import (
	"context"
	"io"
	"strings"

	s3ops "remote-storage/go/s3"
)

type trackedUploadReader struct {
	ctx    context.Context
	reader io.Reader
	taskID string
}

func (r *trackedUploadReader) Read(p []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	n, err := r.reader.Read(p)
	if n > 0 {
		s3ops.AdvanceTransfer(r.taskID, int64(n))
	}
	return n, err
}

func runTrackedUpload(
	ctx context.Context,
	bucket, key, localPath string,
	body io.Reader,
	size int64,
	taskID string,
	upload func(context.Context, io.Reader) error,
	profileIDs ...string,
) error {
	if ctx == nil {
		ctx = context.Background()
	}
	if strings.TrimSpace(taskID) == "" {
		return upload(ctx, body)
	}
	trackedCtx, cancel := context.WithCancel(ctx)
	s3ops.StartQueuedTransfer(taskID, "upload", bucket, key, localPath, size, cancel)
	if len(profileIDs) > 0 {
		s3ops.SetTransferProfile(taskID, profileIDs[0])
	}
	err := upload(trackedCtx, &trackedUploadReader{
		ctx:    trackedCtx,
		reader: body,
		taskID: taskID,
	})
	s3ops.FinishQueuedTransfer(taskID, err)
	cancel()
	return err
}
