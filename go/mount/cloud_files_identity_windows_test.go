//go:build windows && cgo

// Cloud Files identity tests keep OID identity separate from remote freshness.
package mount

import (
	"testing"

	s3ops "remote-storage/go/s3"
)

func TestCloudFilesMetadataIdentityStaysStableWhenFingerprintChanges(t *testing.T) {
	first := cloudFilesMetadataPlaceholderInfo(metadataMountObject{
		info:  s3ops.ObjectInfo{Key: "docs/report.txt", Size: 3, ETag: "one"},
		inode: 42,
	}, "namespace")
	updated := cloudFilesMetadataPlaceholderInfo(metadataMountObject{
		info:  s3ops.ObjectInfo{Key: "docs/report.txt", Size: 3, ETag: "two"},
		inode: 42,
	}, "namespace")
	if first.FileID != updated.FileID {
		t.Fatalf("metadata OID identity changed: %q != %q", first.FileID, updated.FileID)
	}
	if first.Fingerprint == updated.Fingerprint {
		t.Fatal("remote overwrite did not change placeholder fingerprint")
	}
	if cloudFilesPlaceholderMatches(first, updated) {
		t.Fatal("same OID with new fingerprint did not request placeholder refresh")
	}
}
