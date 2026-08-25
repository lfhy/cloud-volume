// Mount metadata-handle tests pin shared namespace ownership at session stop.
package mount

import (
	"path/filepath"
	"testing"

	storageconfig "remote-storage/go/config"
	"remote-storage/go/mount/metadata"
)

func TestBucketAccessMetadataHandleReleasesOnceAcrossStopPaths(t *testing.T) {
	manager := metadata.NewManager(filepath.Join(t.TempDir(), "metadata"))
	defer manager.RemoveAllForTest()
	config := storageconfig.RemoteStorageConfig{
		ProfileID:      "mount-profile",
		CacheDirectory: t.TempDir(),
	}
	handle, err := manager.Acquire(config, "bucket")
	if err != nil {
		t.Fatal(err)
	}
	access := &bucketAccess{metadataHandle: handle}

	access.release()
	access.release()
	if err := access.close(); err != nil {
		t.Fatal(err)
	}
	if services := manager.List(); len(services) != 0 {
		t.Fatalf("repeated stop paths retained metadata service: %+v", services)
	}
}
