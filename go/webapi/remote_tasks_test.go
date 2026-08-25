// Web remote-task tests pin the authenticated projection adapter's pure wire helpers.
package webapi

import (
	"errors"
	"net/http"
	"testing"

	storageconfig "remote-storage/go/config"
	bucketmetadata "remote-storage/go/mount/metadata"
	s3ops "remote-storage/go/s3"
)

func TestWebTaskSyncRequiresActiveProfileID(t *testing.T) {
	if _, err := webTaskSyncProfileID(storageconfig.RemoteStorageConfig{}); !errors.Is(err, bucketmetadata.ErrNotFound) {
		t.Fatalf("empty task-sync profile error = %v, want ErrNotFound", err)
	}
	profileID, err := webTaskSyncProfileID(storageconfig.RemoteStorageConfig{ProfileID: " profile-a "})
	if err != nil || profileID != "profile-a" {
		t.Fatalf("normalized task-sync profile = %q, %v", profileID, err)
	}
	if got := webTaskSyncErrorStatus(bucketmetadata.ErrNotFound); got != http.StatusNotFound {
		t.Fatalf("missing-profile status = %d, want %d", got, http.StatusNotFound)
	}
	if got := webTaskSyncErrorStatus(errors.New("worker failed")); got != http.StatusInternalServerError {
		t.Fatalf("worker error status = %d, want %d", got, http.StatusInternalServerError)
	}
}

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

func TestWebRuntimeTaskWireCarriesLocalAndMultipartDetails(t *testing.T) {
	wire := webRuntimeTaskWire(s3ops.TransferSnapshot{
		ID: "download-1", Type: "download", Bucket: "bucket-a", Key: "remote.bin",
		LocalPath: "/tmp/remote.bin", Status: "running", StatusDetail: "downloading",
		CurrentFileKey: "remote.bin", CurrentFileBytesCompleted: 4, CurrentFileTotalBytes: 8,
		CurrentRange: "bytes=0-7", CurrentPart: 1, TotalParts: 4,
	})
	if wire["localPath"] != "/tmp/remote.bin" {
		t.Fatalf("local path = %#v", wire)
	}
	progress := wire["progress"].(map[string]any)
	if progress["currentFileBytesCompleted"] != int64(4) || progress["currentPart"] != int32(1) {
		t.Fatalf("multipart progress = %#v", progress)
	}
}

func TestWebMountReadSnapshotUsesActiveProfileScope(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("USERPROFILE", t.TempDir())
	config := storageconfig.DefaultConfig()
	config.ProfileID = "profile-mounted-read"
	if err := storageconfig.SaveProfile("default", config); err != nil {
		t.Fatalf("save active profile: %v", err)
	}
	const taskID = "mount-read-web-profile"
	s3ops.QueueTransfer(taskID, "download", "bucket-a", "root/charge.tar", "", 11)
	s3ops.SetTransferProfile(taskID, config.ProfileID)
	s3ops.SetTransferStatusDetail(taskID, "mount_read")
	s3ops.SetTransferTarget(taskID, "bytes=0-10")
	t.Cleanup(func() { s3ops.ForgetTransfer(taskID) })

	result, err := listWebRemoteTasks(invokeEnvelope{Bucket: "bucket-a", IncludeHistory: true})
	if err != nil {
		t.Fatalf("list remote tasks: %v", err)
	}
	page, ok := result.(webRemoteTaskPage)
	if !ok {
		t.Fatalf("list result = %T, want webRemoteTaskPage", result)
	}
	var listed map[string]any
	for _, item := range page.Items {
		candidate, _ := item.(map[string]any)
		if candidate["id"] == "transfer:"+taskID {
			listed = candidate
			break
		}
	}
	if listed == nil || listed["phaseDetail"] != "mount_read" {
		t.Fatalf("listed mount read = %#v", listed)
	}

	detail, err := getWebRemoteTask(invokeEnvelope{TaskID: "transfer:" + taskID, Bucket: "bucket-a"})
	if err != nil {
		t.Fatalf("get remote task: %v", err)
	}
	got, ok := detail.(map[string]any)
	if !ok || got["sourcePath"] != "root/charge.tar" || got["targetPath"] != "bytes=0-10" {
		t.Fatalf("mounted read detail = %#v", detail)
	}
}
