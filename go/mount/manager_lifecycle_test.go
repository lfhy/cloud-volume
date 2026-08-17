// Manager lifecycle tests keep a failed stop attached to its original queue.
package mount

import (
	"errors"
	"path/filepath"
	"testing"

	storageconfig "remote-storage/go/config"
	"remote-storage/go/mount/metadata"
)

type stopFailureMountBackend struct{}

func (stopFailureMountBackend) Initialize(*mountSession) error { return nil }
func (stopFailureMountBackend) Start(*mountSession) error      { return nil }
func (stopFailureMountBackend) Stop(session *mountSession) error {
	// Match the macOS retry contract: the mount remains live after a failed stop.
	session.mounted = true
	session.stopping = false
	return errors.New("injected stop failure")
}
func (stopFailureMountBackend) IsActive(*mountSession) (bool, error) { return true, nil }
func (stopFailureMountBackend) CleanupStale(*mountSession) error     { return nil }

type inactiveStopFailureMountBackend struct{ stopFailureMountBackend }

func (inactiveStopFailureMountBackend) IsActive(*mountSession) (bool, error) { return false, nil }

type cleanupFailureMountBackend struct{ stopCalls int }

func (*cleanupFailureMountBackend) Initialize(*mountSession) error { return nil }
func (*cleanupFailureMountBackend) Start(*mountSession) error      { return nil }
func (b *cleanupFailureMountBackend) Stop(*mountSession) error {
	b.stopCalls++
	return nil
}
func (*cleanupFailureMountBackend) IsActive(*mountSession) (bool, error) { return false, nil }
func (*cleanupFailureMountBackend) CleanupStale(*mountSession) error {
	return errors.New("injected cleanup-stale failure")
}

type startFailureMountBackend struct{ stopCalls int }

func (*startFailureMountBackend) Initialize(*mountSession) error { return nil }
func (*startFailureMountBackend) Start(*mountSession) error {
	return errors.New("injected start failure")
}
func (b *startFailureMountBackend) Stop(*mountSession) error {
	b.stopCalls++
	return nil
}
func (*startFailureMountBackend) IsActive(*mountSession) (bool, error) { return false, nil }
func (*startFailureMountBackend) CleanupStale(*mountSession) error     { return nil }

type retainedStartFailureMountBackend struct{ startFailureMountBackend }

func (b *retainedStartFailureMountBackend) Stop(session *mountSession) error {
	b.stopCalls++
	session.mounted = true
	session.stopping = false
	return errors.New("injected cleanup stop failure")
}

func TestMountConfigChangeKeepsSessionWhenStopFails(t *testing.T) {
	access := newTestBucketAccess(t)
	config := storageconfig.RemoteStorageConfig{Endpoint: "https://old.example", Bucket: "bucket"}.Normalized()
	session := &mountSession{
		config:  config,
		bucket:  "bucket",
		mounted: true,
		access:  access,
		backend: stopFailureMountBackend{},
	}
	manager := &manager{
		sessions:   map[string]*mountSession{"bucket": session},
		lastProbes: map[string]mountProbeSnapshot{},
	}

	changed := config
	changed.Endpoint = "https://new.example"
	if _, err := manager.mountBucket(changed, "bucket", MountOptions{}); err == nil {
		t.Fatal("config change unexpectedly replaced a session whose stop failed")
	}
	if manager.sessions["bucket"] != session || !session.mounted || session.stopping {
		t.Fatal("failed stop discarded the original live session")
	}
}

func TestCleanupMountsKeepsRetryableSessionOnStopFailure(t *testing.T) {
	access := newTestBucketAccess(t)
	session := &mountSession{
		bucket:  "bucket",
		mounted: true,
		access:  access,
		backend: stopFailureMountBackend{},
	}
	manager := &manager{
		sessions:   map[string]*mountSession{"bucket": session},
		lastProbes: map[string]mountProbeSnapshot{},
	}

	if err := manager.cleanupMounts(); err == nil {
		t.Fatal("cleanup unexpectedly succeeded after a retryable stop failure")
	}
	if manager.sessions["bucket"] != session || !session.mounted || session.stopping {
		t.Fatal("cleanup discarded the session that remained mounted")
	}
}

func TestStatusProbeKeepsSessionWhenInactiveStopFails(t *testing.T) {
	access := newTestBucketAccess(t)
	session := &mountSession{
		bucket:  "bucket",
		mounted: true,
		access:  access,
		backend: inactiveStopFailureMountBackend{},
	}
	manager := &manager{
		sessions:   map[string]*mountSession{"bucket": session},
		lastProbes: map[string]mountProbeSnapshot{},
	}

	status, err := manager.getBucketMountStatus("bucket")
	if err != nil {
		t.Fatalf("get mount status: %v", err)
	}
	if manager.sessions["bucket"] != session || !status.Mounted || session.stopping {
		t.Fatal("status probe discarded the session after a retryable stop failure")
	}
	if status.LastError == "" {
		t.Fatal("status probe did not retain the stop failure")
	}
}

func TestStartMountSessionReleasesAccessAfterCleanupStaleFailure(t *testing.T) {
	manager := metadata.NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := storageconfig.RemoteStorageConfig{
		ProfileID:      "cleanup-profile",
		CacheDirectory: t.TempDir(),
	}
	handle, err := manager.AcquireWithBackend(config, "bucket", mountTestBackend{})
	if err != nil {
		t.Fatal(err)
	}
	access := &bucketAccess{metadataHandle: handle}
	backend := &cleanupFailureMountBackend{}
	session := &mountSession{bucket: "bucket", access: access, backend: backend}

	if err := startMountSession(session); err == nil {
		t.Fatal("start unexpectedly succeeded after CleanupStale failure")
	}
	if session.access != nil {
		t.Fatal("failed mount retained bucket access")
	}
	if backend.stopCalls != 0 {
		t.Fatalf("CleanupStale failure called Stop %d times, want 0", backend.stopCalls)
	}
	if services := manager.List(); len(services) != 0 {
		t.Fatalf("failed mount retained metadata namespace: %+v", services)
	}
}

func TestStartMountSessionStopsPartialStartAndReleasesAccess(t *testing.T) {
	manager := metadata.NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := storageconfig.RemoteStorageConfig{
		ProfileID:      "start-profile",
		CacheDirectory: t.TempDir(),
	}
	handle, err := manager.AcquireWithBackend(config, "bucket", mountTestBackend{})
	if err != nil {
		t.Fatal(err)
	}
	backend := &startFailureMountBackend{}
	session := &mountSession{
		bucket:  "bucket",
		access:  &bucketAccess{metadataHandle: handle},
		backend: backend,
	}

	if err := startMountSession(session); err == nil {
		t.Fatal("start unexpectedly succeeded")
	}
	if backend.stopCalls != 1 {
		t.Fatalf("partial start Stop calls = %d, want 1", backend.stopCalls)
	}
	if session.access != nil || len(manager.List()) != 0 {
		t.Fatalf("partial start leaked access or metadata: access=%v services=%+v", session.access, manager.List())
	}
}

func TestStartMountSessionRetainsAccessWhenPartialStartStopFails(t *testing.T) {
	manager := metadata.NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := storageconfig.RemoteStorageConfig{
		ProfileID:      "retained-start-profile",
		CacheDirectory: t.TempDir(),
	}
	handle, err := manager.AcquireWithBackend(config, "bucket", mountTestBackend{})
	if err != nil {
		t.Fatal(err)
	}
	access := &bucketAccess{metadataHandle: handle}
	backend := &retainedStartFailureMountBackend{}
	session := &mountSession{bucket: "bucket", access: access, backend: backend}

	if err := startMountSession(session); err == nil {
		t.Fatal("start unexpectedly succeeded")
	}
	if backend.stopCalls != 1 {
		t.Fatalf("partial start Stop calls = %d, want 1", backend.stopCalls)
	}
	if session.access != access || !session.mounted || session.stopping {
		t.Fatalf("partial-start stop failure did not retain live session: %+v", session)
	}
	if len(manager.List()) != 1 {
		t.Fatalf("retained session lost metadata namespace: %+v", manager.List())
	}
	if session.lastError == "" {
		t.Fatal("retained session did not expose cleanup failure")
	}
	_ = session.access.close()
}
