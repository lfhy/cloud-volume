// Directory sync queue coalesces placeholder directory writes so large local
// tree copies do not launch one remote create goroutine per discovered folder.
package mount

import (
	"context"
	"log"
	"sync"

	"github.com/panjf2000/ants/v2"
)

const dirSyncWorkerCount = 2

type dirSyncQueue struct {
	access *bucketAccess

	mu      sync.Mutex
	pending map[string]bool
	closed  bool
	queue   chan string
	pool    *ants.Pool
	wg      sync.WaitGroup
}

func newDirSyncQueue(access *bucketAccess) *dirSyncQueue {
	pool, err := ants.NewPool(dirSyncWorkerCount)
	if err != nil {
		panic(err)
	}
	q := &dirSyncQueue{
		access:  access,
		pending: map[string]bool{},
		queue:   make(chan string, 512),
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

	q.mu.Lock()
	if q.closed || q.pending[clean] {
		q.mu.Unlock()
		return
	}
	q.pending[clean] = true
	queue := q.queue
	q.mu.Unlock()

	queue <- clean
}

func (q *dirSyncQueue) dispatch() {
	defer q.wg.Done()
	for virtualPath := range q.queue {
		path := virtualPath
		q.wg.Add(1)
		err := q.pool.Submit(func() {
			defer q.wg.Done()
			q.flush(path)
		})
		if err == nil {
			continue
		}
		q.wg.Done()
		q.finish(path)
		log.Printf(
			"[mount/dir-sync] bucket=%q path=%q pool-submit-error=%v",
			q.access.bucket,
			path,
			err,
		)
	}
}

func (q *dirSyncQueue) flush(virtualPath string) {
	ctx, cancel := context.WithTimeout(context.Background(), q.access.requestTimeout)
	defer cancel()
	if err := q.access.createRemoteDirectory(ctx, virtualPath); err != nil {
		log.Printf("[mount/dir-sync] bucket=%q path=%q error=%v", q.access.bucket, virtualPath, err)
	}
	q.finish(virtualPath)
}

func (q *dirSyncQueue) finish(virtualPath string) {
	q.mu.Lock()
	delete(q.pending, virtualPath)
	q.mu.Unlock()
}

func (q *dirSyncQueue) shutdown() {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return
	}
	q.closed = true
	close(q.queue)
	q.mu.Unlock()

	q.wg.Wait()
	q.pool.Release()
}
