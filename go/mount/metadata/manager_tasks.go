// Manager task APIs expose durable projections and controls independently of
// namespace acquisition/lifecycle code.
package metadata

import (
	"errors"
	"time"
)

// ListTasks returns the effective journal tasks for one active namespace.
func (m *Manager) ListTasks(namespace string) ([]Task, error) {
	m.mu.Lock()
	for id, managed := range m.services {
		if id == namespace || managed.service.NamespaceID() == namespace {
			m.mu.Unlock()
			return managed.service.ListTasks()
		}
	}
	m.mu.Unlock()
	return nil, ErrNotFound
}

// ListTaskGroup returns tasks and their aggregate state for one namespace.
func (m *Manager) ListTaskGroup(namespace string) (TaskGroup, error) {
	m.mu.Lock()
	for id, managed := range m.services {
		if id == namespace || managed.service.NamespaceID() == namespace {
			m.mu.Unlock()
			return managed.service.ListTaskGroup()
		}
	}
	m.mu.Unlock()
	return TaskGroup{}, ErrNotFound
}

// ListTaskGroups returns a consistent projection for every retained namespace.
func (m *Manager) ListTaskGroups() ([]TaskGroup, error) {
	m.mu.Lock()
	services := make([]*Service, 0, len(m.services))
	for _, managed := range m.services {
		services = append(services, managed.service)
	}
	m.mu.Unlock()
	result := make([]TaskGroup, 0, len(services))
	for _, service := range services {
		group, err := service.ListTaskGroup()
		if err != nil {
			return nil, err
		}
		result = append(result, group)
	}
	return result, nil
}

// GetTask returns one namespace-qualified task from an active namespace.
func (m *Manager) GetTask(namespace, taskID string) (Task, error) {
	m.mu.Lock()
	for id, managed := range m.services {
		if id == namespace || managed.service.NamespaceID() == namespace {
			m.mu.Unlock()
			return managed.service.GetTask(taskID)
		}
	}
	m.mu.Unlock()
	return Task{}, ErrNotFound
}

func (m *Manager) resolveTaskService(taskID string) (*Service, error) {
	namespace := taskIDNamespace(taskID)
	if namespace == "" {
		return nil, ErrNotFound
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	for id, managed := range m.services {
		if id == namespace || managed.service.NamespaceID() == namespace {
			return managed.service, nil
		}
	}
	return nil, ErrNotFound
}

// CancelTask rolls back a pending task or marks an in-flight one reconciling.
func (m *Manager) CancelTask(taskID string) (Task, error) {
	service, err := m.resolveTaskService(taskID)
	if err != nil {
		return Task{}, err
	}
	return service.CancelTask(taskID)
}

// RetryTask re-arms a failed task for the next worker pass.
func (m *Manager) RetryTask(taskID string) (Task, error) {
	service, err := m.resolveTaskService(taskID)
	if err != nil {
		return Task{}, err
	}
	return service.RetryTask(taskID)
}

// TriggerTask skips the quiet/retry delay without bypassing dependencies.
func (m *Manager) TriggerTask(taskID string) (Task, error) {
	service, err := m.resolveTaskService(taskID)
	if err != nil {
		return Task{}, err
	}
	return service.TriggerTask(taskID)
}

// ClearTaskHistory removes terminal journal entries older than before across
// all retained namespaces.
func (m *Manager) ClearTaskHistory(before time.Time) (int, error) {
	return m.ClearTaskHistoryFor("", "", before)
}

// ClearTaskHistoryFor limits compaction to the requested profile and bucket.
// Empty filters intentionally mean all retained namespaces.
func (m *Manager) ClearTaskHistoryFor(profileID, bucket string, before time.Time) (int, error) {
	m.mu.Lock()
	services := make([]*Service, 0, len(m.services))
	for _, managed := range m.services {
		namespace := managed.service.store.namespace
		if profileID != "" && namespace.Config.ProfileID != profileID {
			continue
		}
		if bucket != "" && namespace.Bucket != bucket {
			continue
		}
		services = append(services, managed.service)
	}
	m.mu.Unlock()
	removed := 0
	for _, service := range services {
		count, err := service.ClearTaskHistory(before)
		if err != nil {
			return removed, err
		}
		removed += count
	}
	return removed, nil
}

// ClearTaskHistoryIDsFor removes explicitly selected terminal tasks within a
// profile/bucket scope. Runtime transfer IDs are intentionally ignored here;
// their in-memory adapter owns removal separately.
func (m *Manager) ClearTaskHistoryIDsFor(profileID, bucket string, taskIDs []string) (int, error) {
	removed := 0
	seen := make(map[string]struct{}, len(taskIDs))
	for _, taskID := range taskIDs {
		if _, ok := seen[taskID]; ok {
			continue
		}
		seen[taskID] = struct{}{}
		service, err := m.resolveTaskService(taskID)
		if errors.Is(err, ErrNotFound) {
			continue
		}
		if err != nil {
			return removed, err
		}
		namespace := service.store.namespace
		if profileID != "" && namespace.Config.ProfileID != profileID {
			continue
		}
		if bucket != "" && namespace.Bucket != bucket {
			continue
		}
		count, err := service.ClearTaskHistoryIDs([]string{taskID})
		if err != nil {
			return removed, err
		}
		removed += count
	}
	return removed, nil
}

// CompactTaskHistory applies the product's 30-day retention policy during a
// task refresh. Explicit clear operations use the scoped method above.
func (m *Manager) CompactTaskHistory() (int, error) {
	return m.ClearTaskHistoryFor("", "", time.Now().Add(-30*24*time.Hour))
}
