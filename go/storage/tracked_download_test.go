// Download tracking tests keep non-S3 task ownership and byte reporting pinned.
package storage

import (
	"context"
	"io"
	"strings"
	"testing"

	s3ops "remote-storage/go/s3"
)

func TestTrackedDownloadPublishesProfileAndBytes(t *testing.T) {
	const taskID = "shared-download-tracker"
	s3ops.ForgetTransfer(taskID)
	t.Cleanup(func() { s3ops.ForgetTransfer(taskID) })

	ctx, finish := beginTrackedDownload(
		context.Background(),
		"bucket-a",
		"remote.txt",
		"/tmp/remote.txt",
		int64(len("payload")),
		taskID,
		"profile-download",
	)
	_, err := io.ReadAll(&trackedDownloadReader{
		ctx: ctx, reader: strings.NewReader("payload"), taskID: taskID,
	})
	finish(err)
	if err != nil {
		t.Fatalf("tracked download error = %v", err)
	}
	snapshot, ok := s3ops.GetTransferSnapshot(taskID)
	if !ok || snapshot.Status != "done" || snapshot.ProfileID != "profile-download" ||
		snapshot.BytesCompleted != int64(len("payload")) || snapshot.TotalBytes != int64(len("payload")) {
		t.Fatalf("download snapshot = %#v", snapshot)
	}
}
