// Legacy mount task registration must retain its profile for unified filtering.
package mount

import (
	"testing"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

func TestLegacyMountTaskRegistrationBindsProfile(t *testing.T) {
	access := &bucketAccess{
		config: storageconfig.RemoteStorageConfig{ProfileID: "profile-mount"},
		bucket: "bucket-a",
	}
	entry := &pendingWriteback{taskID: "profiled-writeback", virtualPath: "draft.txt", size: 9}
	s3ops.ForgetTransfer(entry.taskID)
	t.Cleanup(func() { s3ops.ForgetTransfer(entry.taskID) })

	s3opsQueueTransferForEntry(access, entry)
	snapshot, ok := s3ops.GetTransferSnapshot(entry.taskID)
	if !ok || snapshot.ProfileID != "profile-mount" {
		t.Fatalf("writeback profile = %#v", snapshot)
	}
}

func TestLegacyMountRenameTaskUsesSourceAndTarget(t *testing.T) {
	const taskID = "profiled-rename"
	s3ops.ForgetTransfer(taskID)
	t.Cleanup(func() { s3ops.ForgetTransfer(taskID) })

	beginMutationTransferTask(
		mutationRecord{
			TaskID:         taskID,
			OldVirtualPath: "before.txt",
			NewVirtualPath: "after.txt",
		},
		"bucket-a",
		"/tmp/after.txt",
		"profile-mount",
	)
	snapshot, ok := s3ops.GetTransferSnapshot(taskID)
	if !ok || snapshot.ProfileID != "profile-mount" || snapshot.Key != "before.txt" ||
		snapshot.TargetPath != "after.txt" {
		t.Fatalf("rename snapshot = %#v", snapshot)
	}
}
