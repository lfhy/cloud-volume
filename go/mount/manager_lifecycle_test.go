// Manager lifecycle tests keep a failed stop attached to its original queue.
package mount

import (
	"errors"
	"testing"

	storageconfig "remote-storage/go/config"
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
