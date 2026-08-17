// Service wires durable metadata storage to a provider and local write policy.
package metadata

import "time"

// Service exposes read/write APIs to page and mount adapters.
type Service struct {
	store    *Store
	backend  Backend
	quiet    time.Duration
	readOnly bool
}

// NewService wires a durable store to one provider backend.
func NewService(store *Store, backend Backend) *Service {
	return &Service{store: store, backend: backend, quiet: 10 * time.Second}
}

// SetQuietPeriod configures local-write coalescing before remote work.
func (s *Service) SetQuietPeriod(value time.Duration) {
	if value > 0 {
		s.quiet = value
	}
}

// SetReadOnly rejects desired-tree writes for read-only buckets.
func (s *Service) SetReadOnly(value bool) { s.readOnly = value }

// Store exposes the underlying store for lifecycle ownership.
func (s *Service) Store() *Store { return s.store }

// Backend exposes the provider backend for remote worker execution.
func (s *Service) Backend() Backend { return s.backend }
