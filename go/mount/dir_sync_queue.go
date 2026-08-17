// Directory sync queue coalesces placeholder writes and fences them across renames.
package mount

import (
	"context"
	"fmt"
	"log"
	"strings"
	"sync"

	"github.com/panjf2000/ants/v2"
)

const dirSyncWorkerCount = 2

type dirSyncEntry struct {
	path     string
	running  bool
	canceled bool
	done     chan struct{}
	doneOnce sync.Once
}

type dirSyncBarrier struct {
	entries       []*dirSyncEntry
	rebasedCreate bool
}

type dirSyncQueue struct {
	access *bucketAccess

	mu        sync.Mutex
	entries   map[string]*dirSyncEntry
	closed    bool
	errorPath string
	errorText string
	queue     chan *dirSyncEntry
	pool      *ants.Pool
	enqueueWG sync.WaitGroup
	wg        sync.WaitGroup
}

func newDirSyncQueue(access *bucketAccess) *dirSyncQueue {
	pool, err := ants.NewPool(dirSyncWorkerCount)
	if err != nil {
		panic(err)
	}
	q := &dirSyncQueue{
		access:  access,
		entries: map[string]*dirSyncEntry{},
		queue:   make(chan *dirSyncEntry, 512),
		pool:    pool,
	}
	q.wg.Add(1)
	go q.dispatch()
	return q
}

func (q *dirSyncQueue) enqueue(virtualPath string) {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return
	}

	entry := &dirSyncEntry{path: clean, done: make(chan struct{})}
	q.mu.Lock()
	if q.closed || q.entries[clean] != nil {
		q.mu.Unlock()
		return
	}
	q.entries[clean] = entry
	q.enqueueWG.Add(1)
	queue := q.queue
	q.mu.Unlock()

	queue <- entry
	q.enqueueWG.Done()
}

// rebaseAndFence moves queued creates below oldPath to newPath. Running entries
// retain their original path and are included in the returned barrier.
func (q *dirSyncQueue) rebaseAndFence(oldPath, newPath string, isDir bool) *dirSyncBarrier {
	oldClean := cleanVirtualPath(oldPath)
	newClean := cleanVirtualPath(newPath)
	barrier := &dirSyncBarrier{}
	if oldClean == "" || newClean == "" {
		return barrier
	}

	q.mu.Lock()
	defer q.mu.Unlock()
	seen := make(map[*dirSyncEntry]bool)
	for path, entry := range q.entries {
		if entry == nil || !dirSyncPathMatches(path, oldClean, isDir) {
			continue
		}
		target := rebaseDirSyncPath(path, oldClean, newClean)
		if existing := q.entries[target]; existing != nil && existing != entry {
			if entry.running && !seen[entry] {
				barrier.entries = append(barrier.entries, entry)
				seen[entry] = true
			} else if !entry.running {
				q.cancelLocked(entry)
				barrier.rebasedCreate = true
			}
			if !seen[existing] {
				barrier.entries = append(barrier.entries, existing)
				seen[existing] = true
			}
			continue
		}
		if entry.running {
			if !seen[entry] {
				barrier.entries = append(barrier.entries, entry)
				seen[entry] = true
			}
			continue
		}
		delete(q.entries, path)
		entry.path = target
		q.entries[target] = entry
		barrier.rebasedCreate = true
		if !seen[entry] {
			barrier.entries = append(barrier.entries, entry)
			seen[entry] = true
		}
	}
	// A pre-existing target create must finish before the rename as well.
	if target := q.entries[newClean]; target != nil && !seen[target] {
		barrier.entries = append(barrier.entries, target)
	}
	return barrier
}

func dirSyncPathMatches(path, oldPath string, isDir bool) bool {
	if path == oldPath {
		return true
	}
	return isDir && strings.HasPrefix(path, oldPath+"/")
}

func rebaseDirSyncPath(path, oldPath, newPath string) string {
	if path == oldPath {
		return newPath
	}
	return newPath + strings.TrimPrefix(path, oldPath)
}

func (q *dirSyncQueue) wait(ctx context.Context, barrier *dirSyncBarrier) error {
	if barrier == nil {
		return nil
	}
	for _, entry := range barrier.entries {
		if entry == nil || entry.done == nil {
			continue
		}
		select {
		case <-entry.done:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return nil
}

func (q *dirSyncQueue) dispatch() {
	defer q.wg.Done()
	for entry := range q.queue {
		if entry == nil {
			continue
		}
		q.mu.Lock()
		if entry.canceled {
			q.mu.Unlock()
			q.finish(entry)
			continue
		}
		entry.running = true
		q.mu.Unlock()

		q.wg.Add(1)
		err := q.pool.Submit(func() {
			defer q.wg.Done()
			q.flush(entry)
		})
		if err == nil {
			continue
		}
		q.wg.Done()
		q.recordFailure(entry.path, err)
		q.finish(entry)
		log.Printf(
			"[mount/dir-sync] bucket=%q path=%q pool-submit-error=%v",
			q.access.bucket,
			entry.path,
			err,
		)
	}
}

func (q *dirSyncQueue) flush(entry *dirSyncEntry) {
	q.mu.Lock()
	if entry.canceled {
		q.mu.Unlock()
		q.finish(entry)
		return
	}
	virtualPath := entry.path
	q.mu.Unlock()

	ctx, cancel := context.WithTimeout(context.Background(), q.access.requestTimeout)
	defer cancel()
	if err := q.access.createRemoteDirectory(ctx, virtualPath); err != nil {
		q.recordFailure(virtualPath, err)
		log.Printf("[mount/dir-sync] bucket=%q path=%q error=%v", q.access.bucket, virtualPath, err)
	} else {
		q.clearFailure(virtualPath)
	}
	q.finish(entry)
}

// lastError exposes the most recent in-process marker failure through the
// existing mount-status channel. Entries still finish their fences on failure
// so a failed marker cannot block every later writeback operation.
func (q *dirSyncQueue) lastError() string {
	if q == nil {
		return ""
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	return q.errorText
}

func (q *dirSyncQueue) recordFailure(virtualPath string, err error) {
	if q == nil || err == nil {
		return
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	q.errorPath = cleanVirtualPath(virtualPath)
	q.errorText = fmt.Sprintf("[dir-sync] 创建目录 %q 失败: %v", q.errorPath, err)
}

func (q *dirSyncQueue) clearFailure(virtualPath string) {
	if q == nil {
		return
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.errorPath != cleanVirtualPath(virtualPath) {
		return
	}
	q.errorPath = ""
	q.errorText = ""
}

func (q *dirSyncQueue) cancelLocked(entry *dirSyncEntry) {
	if entry == nil || entry.canceled {
		return
	}
	entry.canceled = true
	for path, candidate := range q.entries {
		if candidate == entry {
			delete(q.entries, path)
		}
	}
	if !entry.running {
		entry.doneOnce.Do(func() { close(entry.done) })
	}
}

func (q *dirSyncQueue) finish(entry *dirSyncEntry) {
	if entry == nil {
		return
	}
	q.mu.Lock()
	entry.running = false
	for path, candidate := range q.entries {
		if candidate == entry {
			delete(q.entries, path)
		}
	}
	entry.doneOnce.Do(func() { close(entry.done) })
	q.mu.Unlock()
}

func (q *dirSyncQueue) shutdown() {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return
	}
	q.closed = true
	q.mu.Unlock()

	q.enqueueWG.Wait()
	close(q.queue)
	q.wg.Wait()
	q.pool.Release()
}
