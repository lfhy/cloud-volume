// Service wires durable metadata storage to a provider and local write policy.
package metadata

import (
	"log"
	"sync"
	"time"
)

// Service exposes read/write APIs to page and mount adapters.
type Service struct {
	store                 *Store
	backendMu             sync.RWMutex
	backend               Backend
	policyMu              sync.RWMutex
	quiet                 time.Duration
	readOnly              bool
	operationMu           sync.RWMutex
	remoteQuietMu         sync.Mutex
	remoteQuietUntilNano  int64
	pathWriteMu           sync.Mutex
	chunkMu               sync.Mutex
	chunkTouch            map[string]int64
	chunkProtectionDirty  bool
	chunkProtectionTimer  *time.Timer
	chunkProtectionClosed bool
	workerMu              sync.RWMutex
	worker                *Worker
	// groupCacheInvalidate is an optional hook the Manager installs so a
	// journal state transition also drops its memoized task-group snapshot.
	groupCacheInvalidate func()
	// changeMu/changeListeners carry op-change notifications to subscribers
	// (bridge task push channel) without exposing internal worker state.
	changeMu        sync.Mutex
	changeListeners map[chan struct{}]bool
}

// SubscribeTaskChanges registers a listener that receives coalesced state
// ticks. Unsubscribe closes its channel so fan-in goroutines cannot leak.
func (s *Service) SubscribeTaskChanges() (func(), chan struct{}) {
	notify := make(chan struct{}, 1)
	s.changeMu.Lock()
	if s.changeListeners == nil {
		s.changeListeners = map[chan struct{}]bool{}
	}
	s.changeListeners[notify] = true
	s.changeMu.Unlock()
	var once sync.Once
	unsubscribe := func() {
		once.Do(func() {
			s.changeMu.Lock()
			if _, exists := s.changeListeners[notify]; exists {
				delete(s.changeListeners, notify)
				close(notify)
			}
			s.changeMu.Unlock()
		})
	}
	return unsubscribe, notify
}

// NotifyTaskChanged wakes every subscriber once; dropped signals are safe
// because subscribers treat this as "re-fetch now", not a payload. It also
// drops the manager group cache hook when installed, so a push-triggered
// poll cannot read a stale memoized snapshot.
func (s *Service) NotifyTaskChanged() {
	if s.groupCacheInvalidate != nil {
		s.groupCacheInvalidate()
	}
	s.changeMu.Lock()
	for ch := range s.changeListeners {
		select {
		case ch <- struct{}{}:
		default:
		}
	}
	s.changeMu.Unlock()
}

// closeTaskChangeListeners releases bridge fan-in subscriptions when this
// namespace is closed between task-page polls. A closed service cannot emit a
// useful future event, and leaving its listeners open retains it indefinitely.
func (s *Service) closeTaskChangeListeners() {
	s.changeMu.Lock()
	for notify := range s.changeListeners {
		close(notify)
	}
	s.changeListeners = nil
	s.changeMu.Unlock()
}

// NewService wires a durable store to one provider backend.
func NewService(store *Store, backend Backend) *Service {
	service := &Service{
		store: store, backend: backend, quiet: 10 * time.Second,
		chunkTouch: map[string]int64{},
	}
	if err := service.SweepChunkStore(); err != nil {
		log.Printf("[metadata/chunks] startup sweep namespace=%q err=%v", store.namespace.ID, err)
	}
	service.rebuildRemoteQuietDeadline()
	return service
}

// SetQuietPeriod configures local-write coalescing before remote work.
func (s *Service) SetQuietPeriod(value time.Duration) {
	if value > 0 {
		s.policyMu.Lock()
		s.quiet = value
		s.policyMu.Unlock()
		s.rebuildRemoteQuietDeadline()
	}
}

// SetReadOnly rejects desired-tree writes for read-only buckets.
func (s *Service) SetReadOnly(value bool) {
	s.policyMu.Lock()
	s.readOnly = value
	s.policyMu.Unlock()
}

// SetBackend publishes refreshed account transport settings for future remote
// operations while an already-started provider request keeps its own snapshot.
func (s *Service) SetBackend(backend Backend) {
	if backend == nil {
		return
	}
	s.backendMu.Lock()
	s.backend = backend
	s.backendMu.Unlock()
}

func (s *Service) backendSnapshot() Backend {
	s.backendMu.RLock()
	defer s.backendMu.RUnlock()
	return s.backend
}

// setPolicy publishes the paired manager-owned settings together so an
// existing namespace never observes a partially refreshed configuration.
func (s *Service) setPolicy(quiet time.Duration, readOnly bool) {
	s.policyMu.Lock()
	quietChanged := quiet > 0
	if quiet > 0 {
		s.quiet = quiet
	}
	s.readOnly = readOnly
	s.policyMu.Unlock()
	if quietChanged {
		s.rebuildRemoteQuietDeadline()
	}
}

func (s *Service) policy() (time.Duration, bool) {
	s.policyMu.RLock()
	defer s.policyMu.RUnlock()
	return s.quiet, s.readOnly
}

func (s *Service) quietPeriod() time.Duration {
	quiet, _ := s.policy()
	return quiet
}

func (s *Service) isReadOnly() bool {
	_, readOnly := s.policy()
	return readOnly
}

// Store exposes the underlying store for lifecycle ownership.
func (s *Service) Store() *Store { return s.store }

// NamespaceID returns the durable namespace identity used in platform object
// projections without exposing the rest of the storage implementation.
func (s *Service) NamespaceID() string {
	if s == nil || s.store == nil {
		return ""
	}
	return s.store.namespace.ID
}

// Backend exposes the current provider backend for remote worker execution.
func (s *Service) Backend() Backend { return s.backendSnapshot() }

// setWorker attaches the namespace worker so task control can cancel a live op.
func (s *Service) setWorker(worker *Worker) {
	s.workerMu.Lock()
	s.worker = worker
	s.workerMu.Unlock()
}

func (s *Service) taskWorker() *Worker {
	s.workerMu.RLock()
	defer s.workerMu.RUnlock()
	return s.worker
}

// Close stops deferred manifest work before releasing the backing database.
func (s *Service) Close() error {
	s.closeTaskChangeListeners()
	s.chunkMu.Lock()
	if !s.chunkProtectionClosed {
		if s.chunkProtectionDirty {
			// A normal shutdown can cheaply shrink the temporary conservative
			// window. If this fails, retain the marker: overprotection is safe.
			if err := s.syncChunkProtectionLocked(); err != nil {
				log.Printf("[metadata/chunks] protection-close namespace=%q err=%v", s.store.namespace.ID, err)
			}
		}
		s.chunkProtectionClosed = true
		s.stopChunkProtectionTimerLocked()
	}
	s.chunkMu.Unlock()
	return s.store.Close()
}
