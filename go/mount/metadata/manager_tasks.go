// Manager task APIs expose durable projections and controls independently of
// namespace acquisition/lifecycle code.
package metadata

import (
	"errors"
	"sync"
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

// SubscribeTaskChanges fans every namespace's change signals into one merged
// channel so the bridge push channel stays simple. The returned stop func is
// idempotent and safe to call from any goroutine.
func (m *Manager) SubscribeTaskChanges() (<-chan struct{}, func()) {
	var (
		mu          sync.Mutex
		stopped     bool
		subscribers = make(map[*Service]func())
	)
	merged := make(chan struct{}, 1)
	// register attaches one service to the merged fan-out; dynamic so
	// namespaces acquired after SubscribeTaskChanges still push ticks.
	register := func(service *Service) {
		mu.Lock()
		if stopped || subscribers[service] != nil {
			mu.Unlock()
			return
		}
		unsubscribe, notify := service.SubscribeTaskChanges()
		subscribers[service] = unsubscribe
		mu.Unlock()
		go func(source <-chan struct{}) {
			defer func() {
				mu.Lock()
				delete(subscribers, service)
				mu.Unlock()
			}()
			for range source {
				mu.Lock()
				done := stopped
				mu.Unlock()
				if done {
					return
				}
				select {
				case merged <- struct{}{}:
				default:
				}
			}
		}(notify)
	}
	stop := func() {
		mu.Lock()
		if stopped {
			mu.Unlock()
			return
		}
		stopped = true
		unsubscribers := make([]func(), 0, len(subscribers))
		for _, unsubscribe := range subscribers {
			unsubscribers = append(unsubscribers, unsubscribe)
		}
		subscribers = nil
		mu.Unlock()
		for _, unsubscribe := range unsubscribers {
			unsubscribe()
		}
	}
	// Register the hook and existing services under the same manager lock order
	// used by Acquire (m.mu -> taskChangeMu). This closes the narrow race where
	// a namespace could be acquired between an initial snapshot and hook setup.
	m.mu.Lock()
	m.taskChangeMu.Lock()
	if m.taskChangeHooks == nil {
		m.taskChangeHooks = make(map[int]func(*Service))
	}
	hookID := m.taskChangeNextID
	m.taskChangeNextID++
	m.taskChangeHooks[hookID] = register
	for _, managed := range m.services {
		register(managed.service)
	}
	m.taskChangeMu.Unlock()
	m.mu.Unlock()
	unlock := func() {
		m.taskChangeMu.Lock()
		delete(m.taskChangeHooks, hookID)
		m.taskChangeMu.Unlock()
		stop()
	}
	return merged, unlock
}

// attachNewNamespaces fans any service registered after a subscription into
// every live subscriber; called with m.mu already held by Acquire paths.
func (m *Manager) attachNewNamespaces(service *Service) {
	m.taskChangeMu.Lock()
	defer m.taskChangeMu.Unlock()
	for _, register := range m.taskChangeHooks {
		register(service)
	}
}

// A short TTL memo keeps overlapping UI pollers (task page, sidebar, sync
// cards) from each re-decoding the whole journal while a large copy is in
// flight; 250ms is far below human perception but above the poll overlap.
func (m *Manager) ListTaskGroups() ([]TaskGroup, error) {
	for {
		m.groupCacheMu.Lock()
		if m.groupCache != nil && time.Since(m.groupCacheAt) < 250*time.Millisecond {
			cached := m.groupCache
			m.groupCacheMu.Unlock()
			return cached, nil
		}
		version := m.groupCacheVersion
		m.groupCacheMu.Unlock()

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

		m.groupCacheMu.Lock()
		if version != m.groupCacheVersion {
			m.groupCacheMu.Unlock()
			// A task transition or acquire/release raced this build. Re-read
			// rather than publish a stale empty/nonempty task page for 250ms.
			continue
		}
		m.groupCache, m.groupCacheAt = result, time.Now()
		m.groupCacheMu.Unlock()
		return result, nil
	}
}

// InvalidateTaskGroupCache drops the memo so control actions (cancel/retry/
// trigger/clear) observe their own mutation immediately.
func (m *Manager) InvalidateTaskGroupCache() {
	m.groupCacheMu.Lock()
	m.groupCache = nil
	m.groupCacheVersion++
	m.groupCacheMu.Unlock()
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
	task, err := service.CancelTask(taskID)
	m.InvalidateTaskGroupCache()
	return task, err
}

// RetryTask re-arms a failed task for the next worker pass.
func (m *Manager) RetryTask(taskID string) (Task, error) {
	service, err := m.resolveTaskService(taskID)
	if err != nil {
		return Task{}, err
	}
	task, err := service.RetryTask(taskID)
	m.InvalidateTaskGroupCache()
	return task, err
}

// TriggerTask skips the quiet/retry delay without bypassing dependencies.
func (m *Manager) TriggerTask(taskID string) (Task, error) {
	service, err := m.resolveTaskService(taskID)
	if err != nil {
		return Task{}, err
	}
	task, err := service.TriggerTask(taskID)
	m.InvalidateTaskGroupCache()
	return task, err
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
	m.InvalidateTaskGroupCache()
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
	m.InvalidateTaskGroupCache()
	return removed, nil
}

// Task-history retention compaction throttling keeps list polling from doing
// repeated journal/index work on every request.
var (
	compactMu    sync.Mutex
	compactLast  = map[string]time.Time{}
	compactEvery = time.Hour
)

// CompactTaskHistoryThrottled applies the 30-day retention rule at most once
// per hour per profile/bucket scope. The first call (and the first call after
// an hour) still compacts; hot polling paths skip the expensive scan.
func (m *Manager) CompactTaskHistoryThrottled(profileID, bucket string) (int, error) {
	key := profileID + "\x00" + bucket
	compactMu.Lock()
	if last, ok := compactLast[key]; ok && time.Since(last) < compactEvery {
		compactMu.Unlock()
		return 0, nil
	}
	compactLast[key] = time.Now()
	compactMu.Unlock()
	return m.ClearTaskHistoryFor(profileID, bucket, time.Now().Add(-30*24*time.Hour))
}
