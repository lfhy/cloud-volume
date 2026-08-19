// Web remote-task tests pin the authenticated projection adapter's pure wire helpers.
package webapi

import (
	"testing"

	s3ops "remote-storage/go/s3"
)

func TestWebRemoteTaskNamespaceParsesQualifiedID(t *testing.T) {
	if got := webRemoteTaskNamespace("sync:profile-hash:gam91cm91cC0x"); got != "profile-hash" {
		t.Fatalf("namespace = %q", got)
	}
	if got := webRemoteTaskNamespace("bad-id"); got != "" {
		t.Fatalf("malformed namespace = %q", got)
	}
}

func TestWebRuntimeTaskMatchesProfile(t *testing.T) {
	snapshot := s3ops.TransferSnapshot{ProfileID: "profile-a", Bucket: "bucket-a", Status: "running"}
	if !webRuntimeTaskMatches(snapshot, invokeEnvelope{ProfileID: "profile-a"}) {
		t.Fatal("matching profile was rejected")
	}
	if webRuntimeTaskMatches(snapshot, invokeEnvelope{ProfileID: "profile-b"}) {
		t.Fatal("different profile was accepted")
	}
}

func TestWebRuntimeTaskWireKeepsMountReadFileAndRangeDistinct(t *testing.T) {
	wire := webRuntimeTaskWire(s3ops.TransferSnapshot{
		ID: "mount-read-1", Type: "download", Bucket: "bucket-a",
		Key: "root/charge.tar", TargetPath: "bytes=1048576-1572863",
		Status: "done", StatusDetail: "mount_read",
	})
	if wire["sourcePath"] != "root/charge.tar" || wire["targetPath"] != "bytes=1048576-1572863" {
		t.Fatalf("mount-read paths = %#v", wire)
	}
	if wire["phaseDetail"] != "mount_read" {
		t.Fatalf("mount-read phase detail = %#v", wire["phaseDetail"])
	}
}
