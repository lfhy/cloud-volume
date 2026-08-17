// Remote directory polling is the P0 cross-client change-discovery fallback.
package mount

import (
	"context"
	"log"
	"sort"
	"sync"
	"time"
)

const (
	remotePollActiveWindow = 45 * time.Second
	remotePollWarmWindow   = 3 * time.Minute
	defaultRemotePollDelay = 5 * time.Second
	remotePollWarmDelay    = 30 * time.Second
	remotePollIdleDelay    = 2 * time.Minute
	remotePollDirectoryCap = 12
)

// directoryActivityTracker records the small working set of directories the
// user has actually opened. P0 never enumerates a whole bucket in the
// background, which keeps idle mounts cheap even for large object stores.
// The tracker is a bounded observed-directory set, not a three-minute cache:
// entries are retained until the cap evicts the oldest one, so idle but
// observed directories keep refreshing on the two-minute cadence.
type directoryActivityTracker struct {
	mu      sync.Mutex
	dirs    map[string]time.Time
	changed chan struct{}
}

func newDirectoryActivityTracker() *directoryActivityTracker {
	return &directoryActivityTracker{
		dirs:    make(map[string]time.Time),
		changed: make(chan struct{}, 1),
	}
}

func (t *directoryActivityTracker) note(prefix string) {
	if t == nil {
		return
	}
	t.noteAt(prefix, time.Now())
}

func (t *directoryActivityTracker) noteAt(prefix string, at time.Time) {
	if t == nil {
		return
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.dirs == nil {
		t.dirs = make(map[string]time.Time)
	}
	t.dirs[cleanVirtualPath(prefix)] = at
	select {
	case t.changed <- struct{}{}:
	default:
	}
	if len(t.dirs) <= remotePollDirectoryCap {
		return
	}
	oldestPrefix := ""
	var oldest time.Time
	for candidate, seenAt := range t.dirs {
		if oldestPrefix == "" || seenAt.Before(oldest) {
			oldestPrefix, oldest = candidate, seenAt
		}
	}
	delete(t.dirs, oldestPrefix)
}

func (t *directoryActivityTracker) recent(now time.Time) []string {
	if t == nil {
		return nil
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	prefixes := make([]string, 0, len(t.dirs))
	for prefix := range t.dirs {
		prefixes = append(prefixes, prefix)
	}
	sort.Strings(prefixes)
	return prefixes
}

func (t *directoryActivityTracker) nextDelay(
	now time.Time,
	activeDelay time.Duration,
) time.Duration {
	if activeDelay <= 0 {
		activeDelay = defaultRemotePollDelay
	}
	if t == nil {
		return remotePollIdleDelay
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	mostRecent := time.Time{}
	for _, seenAt := range t.dirs {
		if seenAt.After(mostRecent) {
			mostRecent = seenAt
		}
	}
	// Cadence follows how recently the user touched any observed directory:
	// active work polls fast, quiet-but-recent work backs off, and a fully
	// idle mount settles to the slow two-minute refresh that still keeps
	// cross-client changes (for example Linux uploads) visible in Windows.
	switch {
	case mostRecent.IsZero() || now.Sub(mostRecent) > remotePollWarmWindow:
		return remotePollIdleDelay
	case now.Sub(mostRecent) <= remotePollActiveWindow:
		return activeDelay
	default:
		return remotePollWarmDelay
	}
}

func (t *directoryActivityTracker) changes() <-chan struct{} {
	if t == nil || t.changed == nil {
		return nil
	}
	return t.changed
}

func (a *bucketAccess) noteDirectoryActivity(prefix string) {
	if a != nil {
		a.directoryActivity.note(prefix)
	}
}

func (a *bucketAccess) pollRemoteDirectory(
	ctx context.Context,
	virtualPrefix string,
) error {
	if a == nil {
		return nil
	}
	if a.metadataService() != nil {
		items, err := a.metadataDirectory(ctx, virtualPrefix, true)
		if err != nil {
			return err
		}
		if a.externalMetadataDirectoryRefresh != nil {
			if err := a.externalMetadataDirectoryRefresh(cleanVirtualPath(virtualPrefix), items); err != nil {
				return err
			}
			return nil
		}
		if a.externalDirectoryRefresh != nil {
			if err := a.externalDirectoryRefresh(cleanVirtualPath(virtualPrefix), metadataObjectInfos(items)); err != nil {
				return err
			}
		}
		return nil
	}
	items, err := a.fetchDirectory(ctx, virtualPrefix)
	if err != nil {
		return err
	}
	a.cache.storeList(virtualPrefix, items)
	if a.externalDirectoryRefresh != nil {
		if err := a.externalDirectoryRefresh(cleanVirtualPath(virtualPrefix), items); err != nil {
			return err
		}
	}
	return nil
}

// remoteDirectoryPoller ties the active-directory tracker to a mount session.
// It is deliberately a cache refresh mechanism, not a second sync engine: the
// remote object store remains authoritative and local writeback is never pruned.
type remoteDirectoryPoller struct {
	access      *bucketAccess
	bucket      string
	activeDelay time.Duration
	ctx         context.Context
	cancel      context.CancelFunc
	stopCh      chan struct{}
	doneCh      chan struct{}
	once        sync.Once
}

func newRemoteDirectoryPoller(session *mountSession) *remoteDirectoryPoller {
	if session == nil || session.access == nil || !session.access.allowRemotePoll {
		return nil
	}
	ctx, cancel := context.WithCancel(context.Background())
	return &remoteDirectoryPoller{
		access:      session.access,
		bucket:      session.bucket,
		activeDelay: time.Duration(session.config.MountRemotePollSeconds) * time.Second,
		ctx:         ctx,
		cancel:      cancel,
		stopCh:      make(chan struct{}),
		doneCh:      make(chan struct{}),
	}
}

func (p *remoteDirectoryPoller) Start() {
	if p == nil || p.access == nil {
		return
	}
	go p.run()
}

func (p *remoteDirectoryPoller) Stop() {
	if p == nil {
		return
	}
	if p.cancel != nil {
		p.cancel()
	}
	p.once.Do(func() { close(p.stopCh) })
	<-p.doneCh
}

func (p *remoteDirectoryPoller) run() {
	defer close(p.doneCh)
	for {
		delay := p.access.directoryActivity.nextDelay(time.Now(), p.activeDelay)
		timer := time.NewTimer(delay)
		select {
		case <-p.stopCh:
			timer.Stop()
			return
		case <-p.access.directoryActivity.changes():
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
		case <-timer.C:
			p.pollOnce(p.ctx)
		}
	}
}

func (p *remoteDirectoryPoller) pollOnce(ctx context.Context) {
	if p == nil || p.access == nil {
		return
	}
	for _, prefix := range p.access.directoryActivity.recent(time.Now()) {
		if err := p.access.pollRemoteDirectory(ctx, prefix); err != nil {
			log.Printf("[mount/poll] refresh-error bucket=%q prefix=%q err=%v", p.bucket, prefix, err)
			continue
		}
		log.Printf("[mount/poll] refresh-done bucket=%q prefix=%q", p.bucket, prefix)
	}
}
