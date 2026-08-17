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
	backend     Backend
	policyMu    sync.RWMutex
	quiet       time.Duration
	readOnly    bool
	operationMu sync.RWMutex
	chunkMu     sync.Mutex
}

// NewService wires a durable store to one provider backend.
func NewService(store *Store, backend Backend) *Service {
	service := &Service{store: store, backend: backend, quiet: 10 * time.Second}
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

// Backend exposes the provider backend for remote worker execution.
func (s *Service) Backend() Backend { return s.backend }
