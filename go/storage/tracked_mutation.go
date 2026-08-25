// Mutation tracking gives non-S3 providers the same physical task snapshots as S3.
package storage

import (
	"context"
	"strings"

	s3ops "remote-storage/go/s3"
)

// runTrackedMutation owns a snapshot only when no outer queue already does.
// Mount queues start their task before calling a backend; page operations do
// not, so this helper makes both paths visible without replacing the outer
// cancellation context or finishing its lifecycle early.
func runTrackedMutation(
	ctx context.Context,
	kind, bucket, key, targetPath, taskID, profileID string,
	operation func(context.Context) error,
) (err error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if strings.TrimSpace(taskID) == "" {
		return operation(ctx)
	}
	if snapshot, exists := s3ops.GetTransferSnapshot(taskID); exists && snapshot.Status == "running" {
		s3ops.SetTransferProfile(taskID, profileID)
		if targetPath != "" {
			s3ops.SetTransferTarget(taskID, targetPath)
		}
		return operation(ctx)
	}

	trackedCtx, cancel := context.WithCancel(ctx)
	s3ops.StartQueuedTransfer(taskID, kind, bucket, key, "", 0, cancel)
	s3ops.SetTransferProfile(taskID, profileID)
	if targetPath != "" {
		s3ops.SetTransferTarget(taskID, targetPath)
	}
	defer func() {
		s3ops.FinishQueuedTransfer(taskID, err)
		cancel()
	}()
	if err := trackedCtx.Err(); err != nil {
		return err
	}
	return operation(trackedCtx)
}
