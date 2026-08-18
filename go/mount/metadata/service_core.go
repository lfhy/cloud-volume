// Service wires durable metadata storage to a provider and local write policy.
package metadata

import (
	"log"
	"sync"
	"time"
)

// Service exposes read/write APIs to page and mount adapters.
type Service struct {
	store       *Store
	backendMu   sync.RWMutex
	backend     Backend
	policyMu    sync.RWMutex
	quiet       time.Duration
	readOnly    bool
	operationMu sync.RWMutex
	pathWriteMu sync.Mutex
	chunkMu     sync.Mutex
	chunkTouch  map[string]int64
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
	return service
}

// SetQuietPeriod configures local-write coalescing before remote work.
func (s *Service) SetQuietPeriod(value time.Duration) {
	if value > 0 {
		s.policyMu.Lock()
		s.quiet = value
		s.policyMu.Unlock()
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
	if quiet > 0 {
		s.quiet = quiet
	}
	s.readOnly = readOnly
	s.policyMu.Unlock()
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
