// Writeback queue drain helpers force persisted uploads to finish before a mount stops.
package mount

import (
	"context"
	"fmt"
	"log"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	s3ops "remote-storage/go/s3"
)

const writebackDrainLogInterval = 3 * time.Second

func (q *writebackQueue) drain() error {
	return q.drainContext(context.Background())
}

// drainPath forces writes for one rename source to settle before the provider
// move can run. It leaves unrelated bucket uploads on their normal schedule.
func (q *writebackQueue) drainPath(
	ctx context.Context,
	virtualPath string,
	isDir bool,
) error {
	if q == nil {
		return nil
	}
	if ctx == nil {
		ctx = context.Background()
	}
	for {
		ready, pending, running, err := q.preparePathDrainPass(virtualPath, isDir)
		if err != nil {
			return err
		}
		if pending == 0 && running == 0 {
			return nil
		}
		for index, entry := range ready {
			if err := q.enqueueDrainEntry(ctx, entry); err != nil {
				q.resumeUnsentDrainEntries(ready[index:])
				return err
			}
		}
		if err := waitForWritebackDrain(ctx, writebackBarrierPollInterval); err != nil {
			return err
		}
	}
}

// drainContext forces queued uploads through the normal dispatcher until it is
// idle. A caller that must keep a live mount on timeout can cancel its wait
// without shutting down the queue or discarding the persisted entries.
func (q *writebackQueue) drainContext(ctx context.Context) error {
	if q == nil {
		return nil
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return err
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
		if err := ctx.Err(); err != nil {
			return err
		}
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
			for index, entry := range ready {
				if err := q.enqueueDrainEntry(ctx, entry); err != nil {
					q.resumeUnsentDrainEntries(ready[index:])
					return err
				}
			}
		} else {
			now := time.Now()
			if !lastWaitLog.IsZero() && now.Sub(lastWaitLog) < writebackDrainLogInterval {
				if err := waitForWritebackDrain(ctx, 100*time.Millisecond); err != nil {
					return err
				}
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
		if err := waitForWritebackDrain(ctx, 100*time.Millisecond); err != nil {
			return err
		}
	}
}

func waitForWritebackDrain(ctx context.Context, delay time.Duration) error {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-timer.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
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

func (q *writebackQueue) preparePathDrainPass(
	virtualPath string,
	isDir bool,
) ([]*pendingWriteback, int, int, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.closed {
		return nil, 0, 0, fmt.Errorf("writeback queue is closed")
	}

	ready := make([]*pendingWriteback, 0)
	pending := 0
	for _, entry := range q.entries {
		if entry == nil || !writebackPathMatches(entry.virtualPath, virtualPath, isDir) {
			continue
		}
		pending++
		if entry.queued {
			continue
		}
		if entry.timer != nil {
			entry.timer.Stop()
			entry.timer = nil
		}
		entry.queued = true
		entry.dueAt = time.Now()
		q.persistEntryLocked(entry)
		ready = append(ready, entry)
	}

	running := 0
	for _, entry := range q.running {
		if entry != nil && writebackPathMatches(entry.virtualPath, virtualPath, isDir) {
			running++
		}
	}
	return ready, pending, running, nil
}

func writebackPathMatches(entryPath, virtualPath string, isDir bool) bool {
	entryClean := cleanVirtualPath(entryPath)
	clean := cleanVirtualPath(virtualPath)
	if entryClean == clean {
		return true
	}
	return isDir && strings.HasPrefix(entryClean, ensureDirSuffix(clean))
}

func (q *writebackQueue) enqueueDrainEntry(ctx context.Context, entry *pendingWriteback) error {
	if entry == nil {
		return nil
	}
	select {
	case q.queue <- entry:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	case <-q.stop:
		return fmt.Errorf("writeback queue is closed")
	}
}

// resumeUnsentDrainEntries restores the normal timer path after a bounded
// drain stops before every due entry reaches the dispatcher.
func (q *writebackQueue) resumeUnsentDrainEntries(entries []*pendingWriteback) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.closed {
		return
	}
	for _, entry := range entries {
		if entry == nil {
			continue
		}
		current, ok := q.entries[entry.virtualPath]
		if ok && current == entry {
			current.queued = false
			q.armTimerLocked(current, 0)
			q.persistEntryLocked(current)
		}
	}
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
