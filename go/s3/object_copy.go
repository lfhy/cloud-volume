// Object copy helpers expose a tracked copy path that shares the transfer hook with move.
package s3

import (
	"context"

	storageconfig "remote-storage/go/config"
)

func CopyObject(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
	taskID string,
) error {
	return CopyObjectContext(Ctx(), cfg, bucket, sourceKey, targetKey, isDirectory, taskID)
}

func CopyObjectContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
	taskID string,
) (err error) {
	client := NewClient(cfg)
	plan, err := buildObjectTransferPlan(
		ctx,
		client,
		bucket,
		sourceKey,
		targetKey,
		isDirectory,
	)
	if err != nil || len(plan.entries) == 0 {
		return err
	}
	runCtx, task := beginObjectTransferTask(
		ctx,
		taskID,
		"copy",
		cfg.ProfileID,
		bucket,
		sourceKey,
		targetKey,
		plan.totalBytes,
	)
	defer func() { task.finish(err) }()
	return executeObjectCopyPlan(runCtx, client, bucket, plan, task, isDirectory)
}
