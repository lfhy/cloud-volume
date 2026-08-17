// Writeback restore rebuilds upload entries and mutation records on queue startup.
package mount

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	s3ops "remote-storage/go/s3"
)

func (q *writebackQueue) restorePersistedEntries() error {
	records, err := q.store.list()
	if err != nil {
		return err
	}
	restoredRecords, dormantRecords := q.filterRestorableRecords(records)
	persistedRecords := append(dormantRecords, restoredRecords...)
	if err := q.store.replaceWithMerged(persistedRecords); err != nil {
		return err
	}
	now := time.Now()
	for _, record := range restoredRecords {
		entry := record.toPendingWriteback()
		if entry.virtualPath == "" || entry.taskID == "" {
			continue
		}
		q.entries[entry.virtualPath] = entry
		if access := q.currentAccess(); access != nil {
			access.cache.storeLocalFile(entry.virtualPath, entry.localPath, s3ops.ObjectInfo{
				Key:          entry.virtualPath,
				Size:         entry.size,
				LastModified: time.Unix(0, entry.modTimeUnixNano).Format("2006-01-02 15:04:05"),
			})
		}
		s3opsQueueTransferForEntry(q.currentAccess(), entry)
		delay := time.Until(entry.dueAt)
		if entry.dueAt.IsZero() || delay < 0 {
			delay = 0
			entry.dueAt = now
		}
		q.armTimerLocked(entry, delay)
	}
	return nil
}

func (q *writebackQueue) filterRestorableRecords(
	records []writebackRecord,
) ([]writebackRecord, []writebackRecord) {
	access := q.currentAccess()
	if access == nil {
		return records, nil
	}
	restored := make([]writebackRecord, 0, len(records))
	dormant := make([]writebackRecord, 0, len(records))
	for _, record := range records {
		if record.Scope != q.scope {
			log.Printf(
				"[mount/writeback] restore-defer-scope bucket=%q path=%q",
				q.bucketName(),
				record.VirtualPath,
			)
			dormant = append(dormant, record)
			continue
		}
		if !q.canRestoreRecord(access, record) {
			continue
		}
		restored = append(restored, record)
	}
	return restored, dormant
}

func (q *writebackQueue) canRestoreRecord(
	access *bucketAccess,
	record writebackRecord,
) bool {
	localPath := filepath.Clean(record.LocalPath)
	if localPath == "." || localPath == "" {
		return false
	}
	sessionRoot := filepath.Clean(access.sessionRoot)
	cacheRoot := filepath.Clean(access.cacheRoot)
	if !isPathWithin(localPath, sessionRoot) && !isPathWithin(localPath, cacheRoot) {
		return false
	}
	info, err := os.Stat(localPath)
	if err != nil || info.IsDir() {
		return false
	}
	return true
}

func isPathWithin(path, root string) bool {
	cleanPath := filepath.Clean(path)
	cleanRoot := filepath.Clean(root)
	if cleanPath == cleanRoot {
		return true
	}
	return strings.HasPrefix(cleanPath, cleanRoot+string(os.PathSeparator))
}

func (q *writebackQueue) pendingPaths() []string {
	q.mu.Lock()
	defer q.mu.Unlock()

	paths := make([]string, 0, len(q.entries)+len(q.running))
	for path := range q.entries {
		paths = append(paths, path)
	}
	for _, entry := range q.running {
		paths = append(paths, entry.virtualPath)
	}
	return paths
}

func (q *writebackQueue) restorePersistedMutations() error {
	if q.mutations == nil {
		return nil
	}
	live, err := q.mutations.Restore()
	if err != nil {
		return fmt.Errorf("restore mutation store: %w", err)
	}
	access := q.currentAccess()
	sessionRoot := ""
	if access != nil {
		sessionRoot = access.sessionRoot
	}

	q.mu.Lock()
	restoredOps := make([]*queuedWritebackRename, 0, len(live))
	maxGeneration := q.generation
	ids := make([]string, 0, len(live))
	for id, record := range live {
		if record.Scope != q.scope {
			log.Printf(
				"[mount/writeback] rename-restore-skip-scope bucket=%q id=%s",
				q.bucketName(),
				id,
			)
			continue
		}
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		record := live[id]
		ensureLocalMutationRoots(&record, sessionRoot)
		barrier := &writebackBarrier{generation: record.UploadGeneration}
		q.barriers = append(q.barriers, barrier)
		q.sourceRebases = append(q.sourceRebases, writebackSourceRebase{
			generation: record.UploadGeneration,
			oldRoot:    filepath.Clean(record.OldLocalPath),
			newRoot:    filepath.Clean(record.NewLocalPath),
			isDir:      record.IsDirectory,
		})
		if record.UploadGeneration > maxGeneration {
			maxGeneration = record.UploadGeneration
		}
		// Rebase queued upload sources captured before the move onto their
		// post-move local paths; their remote keys stay pre-move until the
		// reconciled rename executes, matching the live-queue semantics.
		q.rebasePendingSourcesLocked(q.sourceRebases[len(q.sourceRebases)-1])
		if access != nil {
			beginMutationTransferTask(record, access.bucket, record.NewLocalPath)
		}
		live[id] = record
		// Restored records carry no closure: the reconciler alone converges
		// them from observed provider state.
		restoredOps = append(restoredOps, &queuedWritebackRename{
			barrier:    barrier,
			record:     record,
			oldVirtual: record.OldVirtualPath,
			newVirtual: record.NewVirtualPath,
			oldLocal:   record.OldLocalPath,
			newLocal:   record.NewLocalPath,
			isDir:      record.IsDirectory,
		})
	}
	q.generation = maxGeneration + 1
	renameQueue := q.renameQueue
	q.mu.Unlock()

	if err := q.mutations.Compact(live); err != nil {
		return err
	}
	for _, op := range restoredOps {
		log.Printf(
			"[mount/writeback] rename-restored bucket=%q old=%q new=%q generation=%d id=%s",
			q.bucketName(),
			op.oldVirtual,
			op.newVirtual,
			op.record.UploadGeneration,
			op.record.ID,
		)
		select {
		case renameQueue <- op:
		case <-q.stop:
			return nil
		}
	}
	return nil
}
