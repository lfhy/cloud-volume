// Writeback queue control helpers own cancellation, rename, and shutdown paths.
package mount

import (
	"fmt"
	"strings"

	s3ops "remote-storage/go/s3"
)

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

func (q *writebackQueue) rename(oldVirtualPath, newVirtualPath string, isDir bool) (bool, error) {
	q.mu.Lock()
	defer q.mu.Unlock()

	oldClean := cleanVirtualPath(oldVirtualPath)
	newClean := cleanVirtualPath(newVirtualPath)
	access := q.currentAccess()
	if !isDir {
		entry, ok := q.entries[oldClean]
		if !ok {
			return false, nil
		}
		if access != nil {
			if err := access.cache.renameLocalFile(oldClean, newClean, false, access.cacheRoot); err != nil {
				return false, fmt.Errorf("move pending cache file: %w", err)
			}
			access.cache.invalidatePath(oldClean)
			access.cache.invalidatePath(newClean)
		}
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, oldClean)
		entry.virtualPath = newClean
		q.rebaseEntryLocalPathLocked(access, entry)
		q.armTimerLocked(entry, q.quietPeriodLocked())
		q.entries[newClean] = entry
		q.persistEntryLocked(entry)
		_ = q.store.delete(oldClean)
		q.projectSyncState(entry.virtualPath, false)
		return true, nil
	}

	oldPrefix := ensureDirSuffix(oldClean)
	newPrefix := ensureDirSuffix(newClean)
	entries := make(map[string]*pendingWriteback)
	for key, entry := range q.entries {
		if !strings.HasPrefix(key, oldPrefix) {
			continue
		}
		entries[key] = entry
	}
	if len(entries) == 0 {
		return false, nil
	}
	if access != nil {
		if err := access.cache.renameLocalFile(oldClean, newClean, true, access.cacheRoot); err != nil {
			return false, fmt.Errorf("move pending cache directory: %w", err)
		}
		access.cache.invalidatePath(oldClean)
		access.cache.invalidatePath(newClean)
	}
	for key, entry := range entries {
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, key)
		entry.virtualPath = newPrefix + strings.TrimPrefix(key, oldPrefix)
		nextKey := entry.virtualPath
		q.rebaseEntryLocalPathLocked(access, entry)
		q.armTimerLocked(entry, q.quietPeriodLocked())
		q.entries[nextKey] = entry
		q.persistEntryLocked(entry)
		_ = q.store.delete(key)
		q.projectSyncState(entry.virtualPath, false)
	}
	return true, nil
}

// rebaseEntryLocalPathLocked picks up the cache's physical move while the
// queue lock keeps a timer-driven flush from observing an intermediate path.
func (q *writebackQueue) rebaseEntryLocalPathLocked(access *bucketAccess, entry *pendingWriteback) {
	if access == nil || entry == nil {
		return
	}
	if local, ok := access.cache.localFile(entry.virtualPath); ok {
		entry.localPath = local.localPath
	}
}

func (q *writebackQueue) hasPendingAtOrBelow(virtualPath string, isDir bool) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	if !isDir {
		if _, ok := q.entries[clean]; ok {
			return true
		}
		for _, entry := range q.running {
			if entry.virtualPath == clean {
				return true
			}
		}
		return false
	}
	prefix := ensureDirSuffix(clean)
	for key := range q.entries {
		if strings.HasPrefix(key, prefix) {
			return true
		}
	}
	for _, entry := range q.running {
		if strings.HasPrefix(entry.virtualPath, prefix) {
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
	q.mu.Unlock()
	if entry == nil {
		return false
	}
	select {
	case q.queue <- entry:
		return true
	case <-q.stop:
		return false
	}
}

func (q *writebackQueue) shutdown() error {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return nil
	}
	q.closed = true
	close(q.stop)
	for key, entry := range q.entries {
		if entry.timer != nil {
			entry.timer.Stop()
		}
		entry.queued = false
		delete(q.entries, key)
	}
	q.mu.Unlock()

	q.renameWG.Wait()
	q.wg.Wait()
	q.closeResources()
	return nil
}
