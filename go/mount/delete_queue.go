// Delete queue makes mounted deletes local-first while remote cleanup continues in the background.
package mount

import (
	"context"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	s3ops "remote-storage/go/s3"
)

const deleteWorkerCount = 2

type deleteQueue struct {
	access *bucketAccess

	mu      sync.Mutex
	entries map[string]*pendingDelete
	queue   chan *pendingDelete
	closed  bool
	wg      sync.WaitGroup
}

type pendingDelete struct {
	taskID      string
	virtualPath string
	isDir       bool
	hardDelete  bool
}

func newDeleteQueue(access *bucketAccess) *deleteQueue {
	q := &deleteQueue{
		access:  access,
		entries: map[string]*pendingDelete{},
		queue:   make(chan *pendingDelete, 128),
	}
	for i := 0; i < deleteWorkerCount; i++ {
		q.wg.Add(1)
		go q.worker()
	}
	return q
}

func (q *deleteQueue) enqueue(virtualPath string, isDir bool, hardDelete bool) {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return
	}

	q.mu.Lock()
	if q.closed || q.isCoveredByParentLocked(clean) {
		q.mu.Unlock()
		return
	}
	if existing, ok := q.entries[clean]; ok {
		if isDir && !existing.isDir {
			s3ops.CancelTransfer(existing.taskID)
		} else {
			q.mu.Unlock()
			return
		}
	}
	if isDir {
		q.cancelDescendantsLocked(clean)
	}
	entry := &pendingDelete{
		taskID:      "mount-delete-" + uuid.NewString(),
		virtualPath: clean,
		isDir:       isDir,
		hardDelete:  hardDelete,
	}
	q.entries[clean] = entry
	s3ops.QueueTransfer(entry.taskID, "delete", q.access.bucket, clean, "", 0)
	queue := q.queue
	q.mu.Unlock()

	queue <- entry
}

func (q *deleteQueue) worker() {
	defer q.wg.Done()

	for entry := range q.queue {
		if entry == nil {
			return
		}
		if !q.claim(entry) {
			continue
		}
		if err := q.flushNow(entry); err != nil {
			log.Printf(
				"[mount/delete] bucket=%q path=%q isDir=%t hard=%t error=%v",
				q.access.bucket,
				entry.virtualPath,
				entry.isDir,
				entry.hardDelete,
				err,
			)
		}
	}
}

func (q *deleteQueue) claim(entry *pendingDelete) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	current, ok := q.entries[entry.virtualPath]
	if !ok || current.taskID != entry.taskID {
		return false
	}
	delete(q.entries, entry.virtualPath)
	return true
}

func (q *deleteQueue) flushNow(entry *pendingDelete) (err error) {
	ctx, cancel := context.WithTimeout(context.Background(), q.access.transferTimeout)
	defer cancel()

	ctx, transferCancel := context.WithCancel(ctx)
	s3ops.StartQueuedTransfer(entry.taskID, "delete", q.access.bucket, entry.virtualPath, "", 0, transferCancel)
	defer func() { s3ops.FinishQueuedTransfer(entry.taskID, err) }()
	return q.runDelete(ctx, entry)
}

func (q *deleteQueue) shutdown() {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return
	}
	q.closed = true
	queue := q.queue
	q.mu.Unlock()
	for i := 0; i < deleteWorkerCount; i++ {
		queue <- nil
	}
	q.wg.Wait()
}

func (q *deleteQueue) isCoveredByParentLocked(clean string) bool {
	for key, entry := range q.entries {
		if !entry.isDir {
			continue
		}
		if strings.HasPrefix(clean, ensureDirSuffix(key)) {
			return true
		}
	}
	return false
}

func (q *deleteQueue) cancelDescendantsLocked(clean string) {
	prefix := ensureDirSuffix(clean)
	for key, entry := range q.entries {
		if !strings.HasPrefix(key, prefix) {
			continue
		}
		s3ops.CancelTransfer(entry.taskID)
		delete(q.entries, key)
	}
}

func (q *deleteQueue) runDelete(ctx context.Context, entry *pendingDelete) error {
	deleteFunc := q.access.backend.DeleteObject
	if entry.hardDelete {
		deleteFunc = q.access.backend.DeleteObjectHard
	}
	err := deleteFunc(ctx, q.access.bucket, q.access.remoteKeyForMutation(entry.virtualPath, entry.isDir), entry.isDir, entry.taskID)
	if err == nil || entry.isDir || entry.hardDelete || !isRetryableCopySourceError(err) {
		return err
	}
	for attempt := 0; attempt < 4; attempt++ {
		select {
		case <-ctx.Done():
			return err
		case <-time.After(750 * time.Millisecond):
		}
		retryErr := deleteFunc(ctx, q.access.bucket, q.access.remoteKeyForMutation(entry.virtualPath, entry.isDir), entry.isDir, entry.taskID)
		if retryErr == nil {
			return nil
		}
		err = retryErr
		if !isRetryableCopySourceError(err) {
			return err
		}
	}
	return err
}

func isRetryableCopySourceError(err error) bool {
	if err == nil {
		return false
	}
	text := err.Error()
	return strings.Contains(text, "CopyObject") && strings.Contains(text, "InvalidArgument")
}
