// Writeback queue delays mounted file uploads until the local file stays quiet for a while.
package mount

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/google/uuid"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

const (
	writebackRetryBaseDelay = 15 * time.Second
	writebackRetryMaxDelay  = 2 * time.Minute
)

func (q *writebackQueue) setQuietPeriod(config storageconfig.RemoteStorageConfig) {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.quiet = time.Duration(config.Normalized().WritebackQuietSeconds) * time.Second
}

func (q *writebackQueue) quietPeriod() time.Duration {
	q.mu.Lock()
	defer q.mu.Unlock()
	return q.quietPeriodLocked()
}

func (q *writebackQueue) quietPeriodLocked() time.Duration {
	if q.quiet <= 0 {
		return 10 * time.Second
	}
	return q.quiet
}

func (q *writebackQueue) enqueue(virtualPath, localPath string, size int64) {
	var modTimeUnixNano int64
	info, err := os.Stat(localPath)
	if err == nil && info.IsDir() {
		return
	}
	if err == nil {
		size = info.Size()
		modTimeUnixNano = info.ModTime().UnixNano()
	}

	q.mu.Lock()
	defer q.mu.Unlock()

	if q.closed {
		return
	}
	clean := cleanVirtualPath(virtualPath)
	taskID := "mount-writeback-" + uuid.NewString()
	if existing, ok := q.entries[clean]; ok {
		if existing.timer != nil {
			existing.timer.Stop()
		}
		taskID = existing.taskID
	}
	q.supersedeRunningLocked(clean, localPath)
	entry := &pendingWriteback{
		scope:           q.scope,
		taskID:          taskID,
		virtualPath:     clean,
		localPath:       localPath,
		size:            size,
		modTimeUnixNano: modTimeUnixNano,
		generation:      q.generation,
	}
	q.armTimerLocked(entry, q.quietPeriodLocked())
	q.entries[clean] = entry
	q.persistEntryLocked(entry)
	log.Printf(
		"[mount/writeback] enqueue bucket=%q path=%q local_path=%q size=%d due_at=%s",
		q.bucketName(),
		entry.virtualPath,
		entry.localPath,
		entry.size,
		entry.dueAt.Format(time.RFC3339Nano),
	)
	s3opsQueueTransferForEntry(q.currentAccess(), entry)
	s3ops.SetTransferStatusDetail(entry.taskID, "sync_wait")
	q.projectSyncState(entry.virtualPath, false)
}

func (q *writebackQueue) supersedeRunningLocked(virtualPath, localPath string) {
	for taskID, entry := range q.running {
		if entry.virtualPath != virtualPath {
			continue
		}
		entry.discard = true
		s3ops.CancelTransfer(taskID)
		s3ops.ForgetTransfer(taskID)
		if entry.localPath != "" {
			access := q.currentAccess()
			if access != nil {
				_ = s3ops.DiscardResumableUpload(access.config, entry.localPath)
			}
		}
		break
	}
}

func (q *writebackQueue) dispatch() {
	defer q.wg.Done()
	for {
		select {
		case <-q.stop:
			return
		case entry := <-q.queue:
			if entry == nil {
				continue
			}
			q.wg.Add(1)
			err := q.pool.Submit(func() {
				defer q.wg.Done()
				q.flush(entry)
			})
			if err == nil {
				continue
			}
			q.wg.Done()
			log.Printf(
				"[mount/writeback] pool-submit bucket=%q path=%q error=%v",
				q.bucketName(),
				entry.virtualPath,
				err,
			)
			q.requeue(entry, writebackRetryBaseDelay)
		}
	}
}

func (q *writebackQueue) armTimerLocked(
	entry *pendingWriteback,
	delay time.Duration,
) {
	if entry.timer != nil {
		entry.timer.Stop()
	}
	entry.dueAt = time.Now().Add(delay)
	entry.timer = time.AfterFunc(delay, func() {
		q.enqueueReady(entry.virtualPath)
	})
}

func (q *writebackQueue) enqueueReady(virtualPath string) {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return
	}
	entry, ok := q.entries[cleanVirtualPath(virtualPath)]
	if !ok || entry.queued {
		q.mu.Unlock()
		return
	}
	if q.generationBlockedLocked(entry.generation) {
		q.armTimerLocked(entry, writebackBarrierPollInterval)
		q.mu.Unlock()
		return
	}
	entry.queued = true
	s3ops.SetTransferStatusDetail(entry.taskID, "upload_wait")
	queue := q.queue
	q.mu.Unlock()
	log.Printf(
		"[mount/writeback] ready bucket=%q path=%q local_path=%q",
		q.bucketName(),
		entry.virtualPath,
		entry.localPath,
	)
	select {
	case queue <- entry:
	case <-q.stop:
	}
}

func (q *writebackQueue) claim(entry *pendingWriteback) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	current, ok := q.entries[entry.virtualPath]
	if !ok || current.taskID != entry.taskID || !current.queued {
		return false
	}
	if q.generationBlockedLocked(current.generation) {
		current.queued = false
		q.armTimerLocked(current, writebackBarrierPollInterval)
		return false
	}
	current.queued = false
	delete(q.entries, current.virtualPath)
	q.running[current.taskID] = current
	return true
}

func (q *writebackQueue) flush(entry *pendingWriteback) {
	if !q.claim(entry) {
		return
	}
	log.Printf(
		"[mount/writeback] flush-start bucket=%q path=%q local_path=%q size=%d",
		q.bucketName(),
		entry.virtualPath,
		entry.localPath,
		entry.size,
	)

	err := q.flushNow(entry)
	q.mu.Lock()
	delete(q.running, entry.taskID)
	discard := entry.discard
	q.mu.Unlock()
	if err != nil && !discard && !errors.Is(err, context.Canceled) {
		q.recordDrainError(err)
		log.Printf(
			"[mount/writeback] flush-error bucket=%q path=%q local_path=%q error=%v",
			q.bucketName(),
			entry.virtualPath,
			entry.localPath,
			err,
		)
		q.requeue(entry, nextWritebackRetryDelay(entry.retryCount+1))
		return
	}
	if discard {
		log.Printf("[mount/writeback] flush-discard bucket=%q path=%q", q.bucketName(), entry.virtualPath)
		return
	}
	log.Printf("[mount/writeback] flush-done bucket=%q path=%q", q.bucketName(), entry.virtualPath)
}

func (q *writebackQueue) requeue(entry *pendingWriteback, delay time.Duration) {
	q.mu.Lock()
	defer q.mu.Unlock()

	if q.closed || entry.discard {
		return
	}
	entry.retryCount++
	entry.queued = false
	q.entries[entry.virtualPath] = entry
	q.armTimerLocked(entry, delay)
	q.persistEntryLocked(entry)
	s3opsQueueTransferForEntry(q.currentAccess(), entry)
	s3ops.SetTransferStatusDetail(entry.taskID, "sync_wait")
	q.projectSyncState(entry.virtualPath, false)
}

func (q *writebackQueue) flushNow(entry *pendingWriteback) error {
	access := q.currentAccess()
	if access == nil {
		return fmt.Errorf("missing writeback access")
	}
	localPath := q.resolveEntryLocalPath(entry)
	info, err := os.Stat(localPath)
	if err != nil {
		if os.IsNotExist(err) {
			access.cache.removeLocalFile(entry.virtualPath, false)
			access.cache.invalidatePath(entry.virtualPath)
			_ = q.store.delete(entry.virtualPath)
			log.Printf(
				"[mount/writeback] flush-missing bucket=%q path=%q local_path=%q",
				q.bucketName(),
				entry.virtualPath,
				localPath,
			)
			return nil
		}
		return err
	}
	if info.IsDir() {
		return fmt.Errorf("writeback source became directory: %s", localPath)
	}
	if q.shouldRefreshEntry(entry, info) {
		return q.refreshEntryFromDisk(entry, info, q.quietPeriod())
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	err = access.backend.UploadFile(ctx, access.bucket, access.remoteKey(entry.virtualPath), localPath, entry.taskID)
	if err != nil {
		return err
	}
	if !q.isSuperseded(entry) {
		remoteInfo, headErr := access.backend.HeadObject(ctx, access.bucket, access.remoteKey(entry.virtualPath))
		if headErr != nil {
			// Upload already succeeded. A failed metadata probe must not turn that
			// writeback into a retry; it only makes this source unavailable to P2P.
			log.Printf("[mount/writeback] peer-source head bucket=%q path=%q error=%v", access.bucket, entry.virtualPath, headErr)
			remoteInfo = s3ops.ObjectInfo{Key: entry.virtualPath, Size: info.Size(), LastModified: info.ModTime().Format("2006-01-02 15:04:05")}
		} else {
			remoteInfo.Key = entry.virtualPath
			RememberPeerContent(access.config, access.bucket, entry.virtualPath, localPath, remoteInfo)
		}
		access.cache.clearLocalFileMarker(entry.virtualPath)
		access.cache.storeObject(entry.virtualPath, remoteInfo)
		access.cache.invalidatePath(entry.virtualPath)
		access.projectSyncState(entry.virtualPath, true)
		_ = q.store.delete(entry.virtualPath)
		if hook := PeerBroadcastHook(); hook != nil {
			hook(BroadcastPayload{
				Config:      access.config,
				Bucket:      access.bucket,
				VirtualPath: entry.virtualPath,
				Operation:   "upload",
				VersionHint: remoteInfo.LastModified,
			})
		}
	}
	return nil
}

func (q *writebackQueue) shouldRefreshEntry(entry *pendingWriteback, info os.FileInfo) bool {
	return entry.size != info.Size() || entry.modTimeUnixNano != info.ModTime().UnixNano()
}

func (q *writebackQueue) refreshEntryFromDisk(
	entry *pendingWriteback,
	info os.FileInfo,
	delay time.Duration,
) error {
	q.mu.Lock()
	defer q.mu.Unlock()

	if q.closed || entry.discard {
		return nil
	}
	current, ok := q.running[entry.taskID]
	if !ok || current != entry {
		return nil
	}
	refreshed := &pendingWriteback{
		scope:           entry.scope,
		taskID:          entry.taskID,
		virtualPath:     entry.virtualPath,
		localPath:       entry.localPath,
		size:            info.Size(),
		modTimeUnixNano: info.ModTime().UnixNano(),
		retryCount:      0,
		generation:      entry.generation,
	}
	delete(q.running, entry.taskID)
	q.entries[entry.virtualPath] = refreshed
	q.armTimerLocked(refreshed, delay)
	q.persistEntryLocked(refreshed)
	s3opsQueueTransferForEntry(q.currentAccess(), refreshed)
	q.projectSyncState(refreshed.virtualPath, false)
	return nil
}

func (q *writebackQueue) isSuperseded(entry *pendingWriteback) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	if entry.discard {
		return true
	}
	current, ok := q.entries[entry.virtualPath]
	return ok && current.taskID != entry.taskID
}

func (q *writebackQueue) persistEntryLocked(entry *pendingWriteback) {
	if entry == nil {
		return
	}
	if err := q.store.upsert(entry); err != nil {
		log.Printf(
			"[mount/writeback] persist bucket=%q path=%q error=%v",
			q.bucketName(),
			entry.virtualPath,
			err,
		)
	}
}

func (q *writebackQueue) bucketName() string {
	access := q.currentAccess()
	if access == nil {
		return ""
	}
	return access.bucket
}

func (q *writebackQueue) projectSyncState(virtualPath string, inSync bool) {
	access := q.currentAccess()
	if access == nil {
		return
	}
	access.projectSyncState(virtualPath, inSync)
}

func (q *writebackQueue) recordDrainError(err error) {
	if err == nil {
		return
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	if !q.draining || q.drainErr != nil {
		return
	}
	q.drainErr = err
}

func s3opsQueueTransferForEntry(access *bucketAccess, entry *pendingWriteback) {
	if access == nil || entry == nil {
		return
	}
	s3ops.QueueTransfer(
		entry.taskID,
		"upload",
		access.bucket,
		entry.virtualPath,
		entry.localPath,
		entry.size,
	)
	s3ops.SetTransferStatusDetail(entry.taskID, "sync_wait")
}
