package mount

import (
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestMountSessionMatchesRequiresNormalizedConfigAndBucket(t *testing.T) {
	session := &mountSession{
		config: storageconfig.RemoteStorageConfig{
			Endpoint:         "https://example.com",
			Bucket:           "bucket-a",
			WindowsMountMode: storageconfig.WindowsMountModeCloudFilesCached,
		}.Normalized(),
		bucket: "bucket-a",
	}

	if !mountSessionMatches(session, storageconfig.RemoteStorageConfig{
		Endpoint:         " https://example.com ",
		Bucket:           "bucket-a",
		WindowsMountMode: storageconfig.WindowsMountModeCloudFilesCached,
	}, "bucket-a", MountOptions{}) {
		t.Fatalf("expected equivalent normalized config to reuse session")
	}

	if mountSessionMatches(session, storageconfig.RemoteStorageConfig{
		Endpoint:         "https://example.com",
		Bucket:           "bucket-a",
		WindowsMountMode: storageconfig.WindowsMountModeWebDAV,
	}, "bucket-a", MountOptions{}) {
		t.Fatalf("expected mount-mode change to force remount")
	}

	if mountSessionMatches(session, storageconfig.RemoteStorageConfig{
		Endpoint:         "https://example.com",
		Bucket:           "bucket-a",
		WindowsMountMode: storageconfig.WindowsMountModeCloudFilesCached,
	}, "bucket-b", MountOptions{}) {
		t.Fatalf("expected bucket change to force remount")
	}
}
