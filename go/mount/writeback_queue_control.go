// Writeback queue control helpers own cancellation, rename, and shutdown paths.
package mount

import (
	"fmt"
	"log"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	s3ops "remote-storage/go/s3"
)

const writebackDrainLogInterval = 3 * time.Second

func (q *writebackQueue) cancel(virtualPath string) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	if entry, ok := q.entries[clean]; ok {
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, clean)
		entry.discard = true
		s3ops.CancelTransfer(entry.taskID)
		q.discardEntryLocalState(entry)
		_ = q.store.delete(clean)
		return true
	}
	for _, entry := range q.running {
		if entry.virtualPath != clean {
			continue
		}
		entry.discard = true
		s3ops.CancelTransfer(entry.taskID)
		q.discardEntryLocalState(entry)
		_ = q.store.delete(clean)
		return true
	}
	return false
}

func (q *writebackQueue) cancelAtOrBelow(virtualPath string, isDir bool) {
	q.mu.Lock()
	defer q.mu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	if !isDir {
		if entry, ok := q.entries[clean]; ok {
			if entry.timer != nil {
				entry.timer.Stop()
			}
			entry.discard = true
			q.discardEntryLocalState(entry)
			s3ops.CancelTransfer(entry.taskID)
			delete(q.entries, clean)
			_ = q.store.delete(clean)
		}
		for _, entry := range q.running {
			if entry.virtualPath != clean {
				continue
			}
			entry.discard = true
			q.discardEntryLocalState(entry)
			s3ops.CancelTransfer(entry.taskID)
		}
		return
	}
	prefix := ensureDirSuffix(clean)
	for key, entry := range q.entries {
		if strings.HasPrefix(key, prefix) {
			if entry.timer != nil {
				entry.timer.Stop()
			}
			entry.discard = true
			q.discardEntryLocalState(entry)
			s3ops.CancelTransfer(entry.taskID)
			delete(q.entries, key)
			_ = q.store.delete(key)
		}
	}
	for _, entry := range q.running {
		if strings.HasPrefix(entry.virtualPath, prefix) {
			entry.discard = true
			q.discardEntryLocalState(entry)
			s3ops.CancelTransfer(entry.taskID)
		}
	}
}

func (q *writebackQueue) rename(oldVirtualPath, newVirtualPath string, isDir bool) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	oldClean := cleanVirtualPath(oldVirtualPath)
	newClean := cleanVirtualPath(newVirtualPath)
	renamed := false
	if !isDir {
		entry, ok := q.entries[oldClean]
		if !ok {
			return false
		}
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, oldClean)
		entry.virtualPath = newClean
		q.armTimerLocked(entry, q.quietPeriodLocked())
		q.entries[newClean] = entry
		q.persistEntryLocked(entry)
		_ = q.store.delete(oldClean)
		q.projectSyncState(entry.virtualPath, false)
		return true
	}

	oldPrefix := ensureDirSuffix(oldClean)
	newPrefix := ensureDirSuffix(newClean)
	for key, entry := range q.entries {
		if !strings.HasPrefix(key, oldPrefix) {
			continue
		}
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, key)
		entry.virtualPath = newPrefix + strings.TrimPrefix(key, oldPrefix)
		nextKey := entry.virtualPath
		q.armTimerLocked(entry, q.quietPeriodLocked())
		q.entries[nextKey] = entry
		q.persistEntryLocked(entry)
		_ = q.store.delete(key)
		q.projectSyncState(entry.virtualPath, false)
		renamed = true
	}
	return renamed
}

func (q *writebackQueue) hasPendingAtOrBelow(virtualPath string, isDir bool) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	if !isDir {
		_, ok := q.entries[clean]
		return ok
	}
	prefix := ensureDirSuffix(clean)
	for key := range q.entries {
		if strings.HasPrefix(key, prefix) {
			return true
		}
	}
	return false
}

func (q *writebackQueue) cancelTask(taskID string) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	for key, entry := range q.entries {
		if entry.taskID != taskID {
			continue
		}
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, key)
		entry.discard = true
		s3ops.CancelTransfer(entry.taskID)
		q.discardEntryLocalState(entry)
		_ = q.store.delete(key)
		return true
	}
	if entry, ok := q.running[taskID]; ok {
		entry.discard = true
		s3ops.CancelTransfer(entry.taskID)
		q.discardEntryLocalState(entry)
		_ = q.store.delete(entry.virtualPath)
		return true
	}
	return false
}

func (q *writebackQueue) triggerTask(taskID string) bool {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return false
	}
	var entry *pendingWriteback
	for _, candidate := range q.entries {
		if candidate.taskID != taskID {
			continue
		}
		entry = candidate
		if entry.timer != nil {
			entry.timer.Stop()
		}
		entry.queued = true
		break
	}
	queue := q.queue
	q.mu.Unlock()
	if entry == nil {
		return false
	}
	queue <- entry
	return true
}

func (q *writebackQueue) shutdown() error {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return nil
	}
	q.closed = true
	for key, entry := range q.entries {
		if entry.timer != nil {
			entry.timer.Stop()
		}
		entry.queued = false
		delete(q.entries, key)
	}
	queue := q.queue
	q.mu.Unlock()

	close(queue)
	q.wg.Wait()
	q.closeResources()
	return nil
}

func (q *writebackQueue) drain() error {
	if q == nil {
		return nil
	}

	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return fmt.Errorf("writeback queue is closed")
	}
	q.draining = true
	q.drainErr = nil
	q.mu.Unlock()
	defer func() {
		q.mu.Lock()
		q.draining = false
		q.mu.Unlock()
	}()

	lastWaitLog := time.Time{}
	for {
		ready, pending, running, err := q.prepareDrainPass()
		if err != nil {
			return err
		}
		if pending == 0 && running == 0 {
			log.Printf("[mount/writeback] drain-idle bucket=%q", q.bucketName())
			return nil
		}
		if len(ready) > 0 {
			log.Printf(
				"[mount/writeback] drain-trigger bucket=%q ready=%d pending=%d running=%d",
				q.bucketName(),
				len(ready),
				pending,
				running,
			)
			for _, entry := range ready {
				q.enqueueDrainEntry(entry)
			}
		} else {
			now := time.Now()
			if !lastWaitLog.IsZero() && now.Sub(lastWaitLog) < writebackDrainLogInterval {
				time.Sleep(100 * time.Millisecond)
				continue
			}
			lastWaitLog = now
			log.Printf(
				"[mount/writeback] drain-wait bucket=%q pending=%d running=%d files=%s",
				q.bucketName(),
				pending,
				running,
				q.drainRunningProgress(),
			)
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func nextWritebackRetryDelay(retryCount int) time.Duration {
	if retryCount <= 0 {
		return writebackRetryBaseDelay
	}
	delay := writebackRetryBaseDelay
	for attempt := 1; attempt < retryCount; attempt++ {
		if delay >= writebackRetryMaxDelay {
			return writebackRetryMaxDelay
		}
		delay *= 2
	}
	if delay > writebackRetryMaxDelay {
		return writebackRetryMaxDelay
	}
	return delay
}

func (q *writebackQueue) discardEntryLocalState(entry *pendingWriteback) {
	access := q.currentAccess()
	if access != nil {
		access.cache.removeLocalFile(entry.virtualPath, false)
		access.cache.invalidatePath(entry.virtualPath)
		_ = s3ops.DiscardResumableUpload(access.config, entry.localPath)
	}
}

func (q *writebackQueue) prepareDrainPass() ([]*pendingWriteback, int, int, error) {
	q.mu.Lock()
	defer q.mu.Unlock()

	if q.closed {
		return nil, 0, 0, fmt.Errorf("writeback queue is closed")
	}
	if q.drainErr != nil {
		return nil, len(q.entries), len(q.running), q.drainErr
	}
	ready := make([]*pendingWriteback, 0, len(q.entries))
	for _, entry := range q.entries {
		if entry == nil {
			continue
		}
		if entry.timer != nil {
			entry.timer.Stop()
			entry.timer = nil
		}
		if entry.queued {
			continue
		}
		entry.queued = true
		entry.dueAt = time.Now()
		q.persistEntryLocked(entry)
		ready = append(ready, entry)
	}
	return ready, len(q.entries), len(q.running), nil
}

func (q *writebackQueue) enqueueDrainEntry(entry *pendingWriteback) {
	if entry == nil {
		return
	}
	q.queue <- entry
}

func (q *writebackQueue) drainRunningProgress() string {
	q.mu.Lock()
	entries := make([]*pendingWriteback, 0, len(q.running))
	for _, entry := range q.running {
		entries = append(entries, entry)
	}
	q.mu.Unlock()

	if len(entries) == 0 {
		return "none"
	}

	parts := make([]string, 0, len(entries))
	for _, entry := range entries {
		parts = append(parts, formatDrainProgress(entry))
	}
	return strings.Join(parts, "; ")
}

func formatDrainProgress(entry *pendingWriteback) string {
	if entry == nil {
		return "unknown"
	}
	label := entry.virtualPath
	if label == "" {
		label = filepath.Base(entry.localPath)
	}
	if snapshot, ok := s3ops.GetTransferSnapshot(entry.taskID); ok {
		total := snapshot.TotalBytes
		done := snapshot.BytesCompleted
		if total > 0 {
			percent := float64(done) * 100 / float64(total)
			return label +
				" " +
				strconv.FormatInt(done, 10) +
				"/" +
				strconv.FormatInt(total, 10) +
				" (" +
				fmt.Sprintf("%.1f%%", percent) +
				")"
		}
		return label + " " + strconv.FormatInt(done, 10) + "/?"
	}
	if entry.size > 0 {
		return label + " 0/" + strconv.FormatInt(entry.size, 10) + " (0.0%)"
	}
	return label + " progress=unknown"
}
