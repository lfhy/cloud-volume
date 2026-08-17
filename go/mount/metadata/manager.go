// Namespace registry maps stable profile identities to durable metadata roots.
package metadata

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

// Manager owns one Service/Worker pair per active namespace.
type Manager struct {
	mu       sync.Mutex
	baseDir  string
	services map[string]*managedService
}

type managedService struct {
	service *Service
	worker  *Worker
	refs    int
}

// NewManager creates the process-wide namespace registry.
func NewManager(baseDir string) *Manager {
	return &Manager{baseDir: filepath.Join(baseDir, "v1"), services: map[string]*managedService{}}
}

// DefaultManager resolves the shared manager rooted under the app runtime dir.
func DefaultManager() (*Manager, error) {
	runtimeDir, err := storageconfig.RuntimeDir()
	if err != nil {
		return nil, err
	}
	return NewManager(filepath.Join(runtimeDir, "metadata")), nil
}

// NamespaceID derives a collision-safe namespace from account and view identity.
func NamespaceID(config storageconfig.RemoteStorageConfig, bucket string) string {
	normalized := config.Normalized()
	profile := normalized.ProfileID

	if profile == "" {
		// Older in-flight configs can still bootstrap metadata before a
		// persisted ProfileID exists; derive one from immutable backend fields.
		profile = "unversioned-" + strings.ToLower(normalized.StorageType+"-"+normalized.Endpoint+"-"+normalized.AccessKeyID)
	}
	raw := strings.Join([]string{
		profile,
		normalized.StorageType,
		normalized.Endpoint,
		normalized.Bucket,
		normalized.RootPrefix,
		bucket,
	}, "\x00")
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:16])
}

// Acquire returns a retained service, creating its bbolt namespace on demand.
func (m *Manager) Acquire(config storageconfig.RemoteStorageConfig, bucket string) (*Service, error) {
	id := NamespaceID(config, bucket)
	m.mu.Lock()
	defer m.mu.Unlock()
	if existing, ok := m.services[id]; ok {
		existing.refs++
		return existing.service, nil
	}
	root := filepath.Join(m.baseDir, id)
	if err := os.MkdirAll(root, 0o755); err != nil {
		return nil, err
	}
	store, err := OpenStore(Namespace{ID: id, Root: root, Config: config.Normalized(), Bucket: bucket})
	if err != nil {
		return nil, err
	}
	backend := storageops.ForConfig(config.Normalized())
	service := NewService(store, backend)
	service.SetQuietPeriod(quietDuration(config))
	service.SetReadOnly(config.BucketSettingsFor(bucket).ReadOnly)
	managed := &managedService{service: service, worker: NewWorker(service)}
	m.services[id] = managed
	return service, nil
}

// Release drops one reference, stopping the worker when the last holder leaves.
func (m *Manager) Release(config storageconfig.RemoteStorageConfig, bucket string) {
	id := NamespaceID(config, bucket)
	m.mu.Lock()
	managed, ok := m.services[id]
	if !ok {
		m.mu.Unlock()
		return
	}
	managed.refs--
	if managed.refs > 0 {
		m.mu.Unlock()
		return
	}
	delete(m.services, id)
	m.mu.Unlock()
	managed.worker.Stop()
	_ = managed.service.Close()
}

// RemoveNamespace deletes one namespace database and stops its workers.
func (m *Manager) RemoveNamespace(config storageconfig.RemoteStorageConfig, bucket string) error {
	id := NamespaceID(config, bucket)
	m.mu.Lock()
	managed, ok := m.services[id]
	if ok {
		delete(m.services, id)
	}
	m.mu.Unlock()
	if ok {
		managed.worker.Stop()
		_ = managed.service.Close()
	}
	return os.RemoveAll(filepath.Join(m.baseDir, id))
}

// List returns diagnostics for every open namespace.
func (m *Manager) List() []Status {
	m.mu.Lock()
	services := make([]*Service, 0, len(m.services))
	for _, managed := range m.services {
		services = append(services, managed.service)
	}
	m.mu.Unlock()
	result := make([]Status, 0, len(services))
	for _, service := range services {
		result = append(result, service.Status())
	}
	return result
}

// DrainAll attempts to finish every due operation before app exit.
func (m *Manager) DrainAll(ctx context.Context) error {
	m.mu.Lock()
	workers := make([]*Worker, 0, len(m.services))
	for _, managed := range m.services {
		workers = append(workers, managed.worker)
	}
	m.mu.Unlock()
	var firstErr error
	for _, worker := range workers {
		if err := worker.Drain(ctx); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

func quietDuration(config storageconfig.RemoteStorageConfig) time.Duration {
	seconds := config.Normalized().WritebackQuietSeconds
	if seconds <= 0 {
		seconds = 10
	}
	return time.Duration(seconds) * time.Second
}
