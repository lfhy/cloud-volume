// WebDAV read task tests keep physical range reads tied to their account identity.
package mount

import (
	"context"
	"testing"
	"time"

	s3ops "remote-storage/go/s3"
)

type webDAVReadTaskBackend struct{ mountTestBackend }

func (webDAVReadTaskBackend) ReadObjectRange(
	context.Context, string, string, int64, int64,
) ([]byte, error) {
	return []byte("remote-data"), nil
}

func TestWebDAVReadTransferCarriesProfileIdentity(t *testing.T) {
	access := newTestBucketAccess(t)
	access.config.ProfileID = "profile-mounted-read"
	access.transferTimeout = time.Second
	access.backend = webDAVReadTaskBackend{}
	access.cache.storeObject("root/charge.tar", s3ops.ObjectInfo{
		Key: "root/charge.tar", Size: int64(len("remote-data")),
	})

	file, err := newReadableWebDAVFile(context.Background(), access, "root/charge.tar")
	if err != nil {
		t.Fatalf("open mounted read: %v", err)
	}
	buffer := make([]byte, 1)
	if _, err := file.Read(buffer); err != nil {
		_ = file.Close()
		t.Fatalf("read mounted file: %v", err)
	}
	taskID := file.transferTaskID
	if taskID == "" {
		_ = file.Close()
		t.Fatal("mounted read did not create a physical transfer task")
	}
	t.Cleanup(func() { s3ops.ForgetTransfer(taskID) })

	snapshot, ok := s3ops.GetTransferSnapshot(taskID)
	if !ok {
		_ = file.Close()
		t.Fatal("mounted read transfer snapshot disappeared")
	}
	if snapshot.ProfileID != access.config.ProfileID {
		_ = file.Close()
		t.Fatalf("snapshot profile = %q, want %q", snapshot.ProfileID, access.config.ProfileID)
	}
	if snapshot.StatusDetail != "mount_read" || snapshot.TargetPath != "bytes=0-10" {
		_ = file.Close()
		t.Fatalf("mounted read snapshot = %+v", snapshot)
	}
	if err := file.Close(); err != nil {
		t.Fatalf("close mounted read: %v", err)
	}
}
