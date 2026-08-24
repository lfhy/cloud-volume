// Task-change subscription tests pin dynamic namespace fan-in and teardown.
package metadata

import (
	"path/filepath"
	"testing"
	"time"
)

func TestServiceTaskChangeUnsubscribeClosesChannel(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	stop, changes := service.SubscribeTaskChanges()
	stop()
	if _, open := <-changes; open {
		t.Fatal("task-change channel stayed open after unsubscribe")
	}
}

func TestServiceCloseClosesTaskChangeListeners(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	_, changes := service.SubscribeTaskChanges()
	if err := service.Close(); err != nil {
		t.Fatalf("close service: %v", err)
	}
	if _, open := <-changes; open {
		t.Fatal("task-change channel stayed open after service close")
	}
}

func TestManagerTaskChangesIncludesLateNamespace(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	changes, stop := manager.SubscribeTaskChanges()
	defer stop()

	config := fakeConfig("task-change-profile")
	config.CacheDirectory = t.TempDir()
	handle, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
	if err != nil {
		t.Fatalf("acquire namespace: %v", err)
	}
	defer handle.Release()
	handle.Service.NotifyTaskChanged()

	select {
	case <-changes:
	case <-time.After(time.Second):
		t.Fatal("late namespace change did not reach manager subscription")
	}
}

func TestManagerTaskChangesReleasesClosedPollingNamespaces(t *testing.T) {
	manager := NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	_, stop := manager.SubscribeTaskChanges()
	defer stop()
	config := fakeConfig("task-change-poll-profile")
	config.CacheDirectory = t.TempDir()

	for index := 0; index < 3; index++ {
		handle, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
		if err != nil {
			t.Fatalf("acquire namespace %d: %v", index, err)
		}
		service := handle.Service
		service.changeMu.Lock()
		listenerCount := len(service.changeListeners)
		service.changeMu.Unlock()
		if listenerCount != 1 {
			t.Fatalf("namespace %d listener count = %d, want 1", index, listenerCount)
		}
		handle.Release()
		service.changeMu.Lock()
		listenerCount = len(service.changeListeners)
		service.changeMu.Unlock()
		if listenerCount != 0 {
			t.Fatalf("closed namespace %d listener count = %d, want 0", index, listenerCount)
		}
	}
}
