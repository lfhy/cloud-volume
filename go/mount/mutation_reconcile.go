// Remote move reconciliation turns persisted mutation records into state-driven retries.
package mount

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"time"

	"github.com/google/uuid"

	s3ops "remote-storage/go/s3"
)

// reconcileRemoteMove converges one persisted rename record to a terminal
// state using observed provider state instead of memory-only closure retries:
//
//	source   destination   action
//	absent   present       complete without another provider mutation
//	present  absent        MoveObject, then re-probe both paths
//	present  present       CopyObject merge, DeleteObjectHard source, re-probe
//	absent   absent        retain the record; state conflict, retry later
func (a *bucketAccess) reconcileRemoteMove(
	ctx context.Context,
	record mutationRecord,
) (err error) {
	if a == nil {
		return fmt.Errorf("missing bucket access")
	}
	ctx, finishTransfer := a.beginMutationTransferAttempt(ctx, record)
	defer func() { finishTransfer(err) }()
	oldClean := cleanVirtualPath(record.OldVirtualPath)
	newClean := cleanVirtualPath(record.NewVirtualPath)
	if oldClean == "" || newClean == "" {
		return fmt.Errorf("mutation record %q has empty paths", record.ID)
	}

	sourceExists, err := a.probeRemotePath(ctx, oldClean, record.IsDirectory)
	if err != nil {
		return err
	}
	destinationExists, err := a.probeRemotePath(ctx, newClean, record.IsDirectory)
	if err != nil {
		return err
	}

	switch {
	case !sourceExists && destinationExists:
		// The move already reached its remote postcondition (a previous
		// copy succeeded and the delete either succeeded or was never needed).
		return nil
	case sourceExists && !destinationExists:
		if err := a.backend.MoveObject(
			ctx,
			a.bucket,
			a.remoteKeyForMutation(oldClean, record.IsDirectory),
			a.remoteKeyForMutation(newClean, record.IsDirectory),
			record.IsDirectory,
			record.TaskID,
		); err != nil {
			return err
		}
	case sourceExists && destinationExists:
		// Ambiguous retry: copy may have finished while the source delete
		// failed. Merge-then-hard-delete converges without resurrecting data.
		if err := a.backend.CopyObject(
			ctx,
			a.bucket,
			a.remoteKeyForMutation(oldClean, record.IsDirectory),
			a.remoteKeyForMutation(newClean, record.IsDirectory),
			record.IsDirectory,
			record.TaskID,
		); err != nil {
			return err
		}
		if err := a.backend.DeleteObjectHard(
			ctx,
			a.bucket,
			a.remoteKeyForMutation(oldClean, record.IsDirectory),
			record.IsDirectory,
			record.TaskID,
		); err != nil {
			return err
		}
	default:
		// Neither path exists: the remote state contradicts the captured
		// intent. Keep retrying with a state-conflict error rather than
		// guessing; a later external change can make one side observable.
		return fmt.Errorf(
			"move %q: %w: %q and %q are both absent",
			record.ID,
			errMutationStateConflict,
			oldClean,
			newClean,
		)
	}

	// Verify the postcondition before declaring success so a tombstone is
	// never written for an unverified provider result.
	sourceAfter, err := a.probeRemotePath(ctx, oldClean, record.IsDirectory)
	if err != nil {
		return err
	}
	if sourceAfter {
		return fmt.Errorf("move left source %q present after mutation", oldClean)
	}
	destinationAfter, err := a.probeRemotePath(ctx, newClean, record.IsDirectory)
	if err != nil {
		return err
	}
	if !destinationAfter {
		return fmt.Errorf("move left destination %q absent after mutation", newClean)
	}
	return nil
}

// beginMutationTransferAttempt owns the whole reconcile pass so a copy plus
// source cleanup remains one visible move task instead of two terminal rows.
func (a *bucketAccess) beginMutationTransferAttempt(
	ctx context.Context,
	record mutationRecord,
) (context.Context, func(error)) {
	if ctx == nil {
		ctx = context.Background()
	}
	if record.TaskID == "" {
		return ctx, func(error) {}
	}
	if snapshot, exists := s3ops.GetTransferSnapshot(record.TaskID); exists && snapshot.Status == "running" {
		s3ops.SetTransferProfile(record.TaskID, a.config.ProfileID)
		s3ops.SetTransferTarget(record.TaskID, record.NewVirtualPath)
		return ctx, func(error) {}
	}
	transferCtx, cancel := context.WithCancel(ctx)
	s3ops.StartQueuedTransfer(
		record.TaskID,
		"move",
		a.bucket,
		record.OldVirtualPath,
		record.NewLocalPath,
		0,
		cancel,
	)
	s3ops.SetTransferProfile(record.TaskID, a.config.ProfileID)
	s3ops.SetTransferTarget(record.TaskID, record.NewVirtualPath)
	return transferCtx, func(err error) {
		s3ops.FinishQueuedTransfer(record.TaskID, err)
		cancel()
	}
}

// applyMutationSuccess updates local caches, peer knowledge, and broadcast
// state after a verified remote move.
func (a *bucketAccess) applyMutationSuccess(record mutationRecord) error {
	oldClean := cleanVirtualPath(record.OldVirtualPath)
	newClean := cleanVirtualPath(record.NewVirtualPath)
	if err := a.cache.renameLocalFile(oldClean, newClean, record.IsDirectory, a.cacheRoot); err != nil {
		return err
	}
	a.cache.invalidatePath(oldClean)
	a.cache.invalidatePath(newClean)
	ForgetPeerContent(a.config, a.bucket, oldClean)
	if hook := PeerBroadcastHook(); hook != nil {
		hook(BroadcastPayload{
			Config:      a.config,
			Bucket:      a.bucket,
			VirtualPath: newClean,
			OldPath:     oldClean,
			IsDir:       record.IsDirectory,
			Operation:   "rename",
		})
	}
	return nil
}

// ensureLocalMutationRoots repairs local cache/staging roots captured in a
// restored record. Absolute captured paths may point at a previous mount's
// directories; relative captures stay relative to the current session root.
func ensureLocalMutationRoots(record *mutationRecord, sessionRoot string) {
	if record == nil {
		return
	}
	fix := func(value string) string {
		cleaned := filepath.Clean(value)
		if cleaned == "" || cleaned == "." {
			return ""
		}
		if filepath.IsAbs(cleaned) {
			return cleaned
		}
		return filepath.Join(sessionRoot, cleaned)
	}
	record.OldLocalPath = fix(record.OldLocalPath)
	record.NewLocalPath = fix(record.NewLocalPath)
}

// newMutationID returns the stable identifier for one queued remote move.
func newMutationID() string {
	return "mutation-" + uuid.NewString()
}

// beginMutationTransferTask registers (or re-registers after restore) the
// shared transfer-monitor entry for a reconciled move.
func beginMutationTransferTask(record mutationRecord, bucket, localPath, profileID string) {
	if record.TaskID == "" {
		return
	}
	s3ops.QueueTransfer(
		record.TaskID,
		"move",
		bucket,
		record.OldVirtualPath,
		localPath,
		0,
	)
	s3ops.SetTransferProfile(record.TaskID, profileID)
	s3ops.SetTransferTarget(record.TaskID, record.NewVirtualPath)
	s3ops.SetTransferStatusDetail(record.TaskID, "sync_wait")
}

// mutationRetryDelay returns the next attempt delay for a record.
func mutationRetryDelay(record mutationRecord) time.Duration {
	return nextWritebackRetryDelay(record.RetryCount + 1)
}

// errMutationStateConflict marks the absent/absent reconcile row: the record
// is retained and retried instead of guessing user intent.
var errMutationStateConflict = errors.New("mutation state conflict")
