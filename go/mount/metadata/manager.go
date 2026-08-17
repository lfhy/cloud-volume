// Namespace registry maps stable profile identities to durable metadata roots.
package metadata

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
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
// Callers must persist and supply ProfileID; the fallback exists only for
// diagnostics/tests and must not create durable namespaces for saved profiles.
func NamespaceID(config storageconfig.RemoteStorageConfig, bucket string) string {
	normalized := config.Normalized()
	profile := normalized.ProfileID
	if profile == "" {
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

// AcquireHandle pairs a retained service with the manager handle used to
// release it. Holding the handle prevents premature worker/database shutdown.
type AcquireHandle struct {
	Service *Service
	manager *Manager
}

// ErrNoProfileID marks configs that lack the immutable identity required to
// open a durable namespace; callers treat it as "fall back to direct listing".
var ErrNoProfileID = errors.New("metadata: profile has no profileId")

// Acquire returns a retained service handle, creating its bbolt namespace on
// demand. A missing ProfileID is an error: a namespace derived from mutable
// fallback fields would silently split/merge accounts after identity assignment.
func (m *Manager) Acquire(config storageconfig.RemoteStorageConfig, bucket string) (*AcquireHandle, error) {
	normalized := config.Normalized()
	if normalized.ProfileID == "" {
		return nil, ErrNoProfileID
	}
	id := NamespaceID(normalized, bucket)
	m.mu.Lock()
	defer m.mu.Unlock()
	var managed *managedService
	if existing, ok := m.services[id]; ok {
		existing.refs++
		// Refresh per-acquisition policy so a later bucket read-only or quiet
		// setting change is honored by the retained namespace service.
		existing.service.SetQuietPeriod(quietDuration(normalized))
		existing.service.SetReadOnly(normalized.BucketSettingsFor(bucket).ReadOnly)
		managed = existing
	} else {
		service, err := m.openService(id, normalized, bucket)
		if err != nil {
			return nil, err
		}
		managed = service
	}
	return &AcquireHandle{Service: managed.service, manager: m}, nil
}

func (m *Manager) openService(id string, normalized storageconfig.RemoteStorageConfig, bucket string) (*managedService, error) {
	root := filepath.Join(m.baseDir, id)
	if err := os.MkdirAll(root, 0o755); err != nil {
		return nil, err
	}
	store, err := OpenStore(Namespace{ID: id, Root: root, Config: normalized, Bucket: bucket})
	if err != nil {
		return nil, err
	}
	// The namespace already encodes RootPrefix. Clear it before building the
	// provider backend, otherwise scopedBackend would prefix keys twice.
	backendCfg := normalized
	backendCfg.RootPrefix = ""
	service := NewService(store, storageops.ForConfig(backendCfg))
	service.SetQuietPeriod(quietDuration(normalized))
	service.SetReadOnly(normalized.BucketSettingsFor(bucket).ReadOnly)
	managed := &managedService{service: service, worker: NewWorker(service), refs: 1}
	m.services[id] = managed
	return managed, nil
}

// Release drops one Acquire handle. Unbalanced calls are ignored so a stray
// release cannot close a namespace another holder still uses.
func (m *Manager) Release(handle *AcquireHandle) {
	if handle == nil || handle.Service == nil || handle.manager != m {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	for id, managed := range m.services {
		if managed.service != handle.Service {
			continue
		}
		managed.refs--
		if managed.refs > 0 {
			return
		}
		delete(m.services, id)
		managed.worker.Stop()
		_ = managed.service.Close()
		return
	}
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

// DrainAll attempts to finish every due operation before app exit. Workers run
// concurrently so one slow provider cannot serialize every namespace into the
// exit timeout; the first failure is reported.
func (m *Manager) DrainAll(ctx context.Context) error {
	m.mu.Lock()
	workers := make([]*Worker, 0, len(m.services))
	for _, managed := range m.services {
		workers = append(workers, managed.worker)
	}
	m.mu.Unlock()
	results := make([]error, len(workers))
	var wg sync.WaitGroup
	for index, worker := range workers {
		wg.Add(1)
		go func(target *Worker, slot int) {
			defer wg.Done()
			results[slot] = target.Drain(ctx)
		}(worker, index)
	}
	wg.Wait()
	for _, err := range results {
		if err != nil {
			return err
		}
	}
	return nil
}

func quietDuration(config storageconfig.RemoteStorageConfig) time.Duration {
	seconds := config.Normalized().WritebackQuietSeconds
	if seconds <= 0 {
		seconds = 10
	}
	return time.Duration(seconds) * time.Second
}
