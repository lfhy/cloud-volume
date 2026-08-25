// Manager bulk sync scopes pending-task scheduling to the requested profile and bucket.
package metadata

// TriggerPendingTasksFor skips the quiet period for all pending metadata tasks
// in scope. Empty filters intentionally cover every retained namespace.
func (m *Manager) TriggerPendingTasksFor(profileID, bucket string) (int, error) {
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
	triggered := 0
	for _, service := range services {
		count, err := service.TriggerPendingTasks()
		if err != nil {
			return triggered, err
		}
		triggered += count
	}
	m.InvalidateTaskGroupCache()
	return triggered, nil
}
