// Object move helpers support tracked full-path moves across directories.
package s3

import (
	"context"
	"strings"

	storageconfig "remote-storage/go/config"
)

// MoveObject copies a file or prefix to a new full target key and removes the source.
func MoveObject(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
) error {
	return MoveObjectWithTask(
		cfg,
		bucket,
		sourceKey,
		targetKey,
		isDirectory,
		"",
	)
}

// MoveObjectWithTask moves an object tree while reporting progress to the transfer monitor.
func MoveObjectWithTask(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
	taskID string,
) error {
	return MoveObjectContextWithTask(
		Ctx(),
		cfg,
		bucket,
		sourceKey,
		targetKey,
		isDirectory,
		taskID,
	)
}

// MoveObjectContext copies a file or prefix to a new full target key with caller context.
func MoveObjectContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
) error {
	return MoveObjectContextWithTask(
		ctx,
		cfg,
		bucket,
		sourceKey,
		targetKey,
		isDirectory,
		"",
	)
}

// MoveObjectContextWithTask copies and deletes through a tracked task-aware path.
// Item totals for the copy phase are reported up front so delete sweeps that
// reuse the same task keep a single consistent item bar across both phases.
func MoveObjectContextWithTask(
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
	if taskID != "" {
		PlanTransferPhaseItems(taskID, transferPhaseCopy, int64(len(plan.entries)))
	}
	runCtx, task := beginObjectTransferTask(
		ctx,
		taskID,
		"move",
		cfg.ProfileID,
		bucket,
		sourceKey,
		targetKey,
		plan.totalBytes,
	)
	defer func() { task.finish(err) }()
	if err = executeObjectCopyPlan(
		runCtx,
		client,
		bucket,
		plan,
		task,
		isDirectory,
	); err != nil {
		return err
	}
	// Delete the keys captured when the plan was built. Re-listing the source
	// prefix here can observe keys that were already removed mid-sweep and
	// silently skip them, which previously left stale objects behind on moves.
	// The cleanup is its own progress phase: reset the item bar so it shows
	// 0/N for the deletions instead of accumulating past the copy total.
	if taskID != "" {
		resetTransferPhaseItems(taskID)
		PlanTransferPhaseItems(taskID, transferPhaseDelete, int64(len(plan.deleteKeys)))
		SetTransferStatusDetail(taskID, "deleting")
	}
	return deleteObjectKeysHardWithTask(runCtx, client, bucket, plan.deleteKeys, taskID)
}

func ensureRemoteDirSuffix(value string) string {
	trimmed := strings.TrimSuffix(strings.TrimSpace(value), "/")
	if trimmed == "" {
		return ""
	}
	return trimmed + "/"
}
