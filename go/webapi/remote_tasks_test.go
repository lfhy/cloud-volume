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
