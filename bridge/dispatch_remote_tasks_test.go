// Remote-task bridge tests pin the namespace-qualified contract and physical
// snapshot projection without contacting a provider.
package main

import (
	"testing"

	s3ops "remote-storage/go/s3"
)

func TestRemoteTaskNamespaceParsesQualifiedAndLegacyIDs(t *testing.T) {
	if got := remoteTaskNamespace("sync:abc123:gam91cm91cC0x"); got != "abc123" {
		t.Fatalf("qualified namespace = %q", got)
	}
	if got := remoteTaskNamespace("abc123:7"); got != "abc123" {
		t.Fatalf("legacy namespace = %q", got)
	}
	if got := remoteTaskNamespace("sync:missing"); got != "" {
		t.Fatalf("malformed namespace = %q", got)
	}
}

func TestRuntimeTaskWireCarriesProfileAndPhysicalProgress(t *testing.T) {
	wire := runtimeTaskWire(s3ops.TransferSnapshot{
		ID: "sync-op", Type: "sync_upload", ProfileID: "profile-a", Bucket: "bucket-a",
		Key: "dir/file.txt", Status: "running", StatusDetail: "uploading",
		BytesCompleted: 4, TotalBytes: 8,
	})
	if wire["profileId"] != "profile-a" || wire["id"] != "transfer:sync-op" {
		t.Fatalf("runtime wire identity = %#v", wire)
	}
	progress, ok := wire["progress"].(map[string]any)
	if !ok || progress["bytesCompleted"] != int64(4) {
		t.Fatalf("runtime progress = %#v", wire["progress"])
	}
}

func TestRuntimeTaskWireKeepsMountReadFileAndRangeDistinct(t *testing.T) {
	wire := runtimeTaskWire(s3ops.TransferSnapshot{
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

func TestRuntimeTaskWireCarriesLocalAndMultipartDetails(t *testing.T) {
	wire := runtimeTaskWire(s3ops.TransferSnapshot{
		ID: "copy-1", Type: "copy", ProfileID: "profile-a", Bucket: "bucket-a",
		Key: "old.bin", TargetPath: "new.bin", LocalPath: "/tmp/download.bin",
		Status: "running", StatusDetail: "copying", Cancelable: true,
		CurrentFileKey: "new.bin", CurrentFileBytesCompleted: 4, CurrentFileTotalBytes: 8,
		CurrentRange: "bytes=0-7", CurrentPart: 1, TotalParts: 4,
	})
	if wire["localPath"] != "/tmp/download.bin" || wire["cancelable"] != true {
		t.Fatalf("runtime fields = %#v", wire)
	}
	progress := wire["progress"].(map[string]any)
	if progress["currentRange"] != "bytes=0-7" || progress["totalParts"] != int32(4) {
		t.Fatalf("runtime multipart progress = %#v", progress)
	}
}
