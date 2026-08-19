// Shared upload-tracking assertions keep provider task lifecycle tests consistent.
package storage

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"

	s3ops "remote-storage/go/s3"
)

func TestRunTrackedUploadFinishesFailedTask(t *testing.T) {
	taskID := "shared-upload-tracker-finishes-failure"
	s3ops.QueueTransfer(taskID, "upload", "test", "failed.txt", "", 7)
	t.Cleanup(func() { s3ops.ForgetTransfer(taskID) })
	wantErr := errors.New("provider rejected upload")

	err := runTrackedUpload(
		context.Background(),
		"test",
		"failed.txt",
		"",
		strings.NewReader("payload"),
		7,
		taskID,
		func(_ context.Context, body io.Reader) error {
			if _, readErr := io.Copy(io.Discard, body); readErr != nil {
				return readErr
			}
			return wantErr
		},
		"profile-upload",
	)
	if !errors.Is(err, wantErr) {
		t.Fatalf("runTrackedUpload error = %v, want %v", err, wantErr)
	}
	snapshot, ok := s3ops.GetTransferSnapshot(taskID)
	if !ok || snapshot.Status != "failed" || snapshot.Error != wantErr.Error() || snapshot.ProfileID != "profile-upload" {
		t.Fatalf("failed transfer snapshot = %#v, ok=%t", snapshot, ok)
	}
}

func TestRunTrackedMutationPublishesProfiledMove(t *testing.T) {
	const taskID = "shared-mutation-tracker"
	s3ops.ForgetTransfer(taskID)
	t.Cleanup(func() { s3ops.ForgetTransfer(taskID) })

	err := runTrackedMutation(
		context.Background(),
		"move",
		"bucket-a",
		"old.txt",
		"new.txt",
		taskID,
		"profile-mutation",
		func(context.Context) error {
			snapshot, ok := s3ops.GetTransferSnapshot(taskID)
			if !ok || snapshot.Status != "running" || snapshot.ProfileID != "profile-mutation" ||
				snapshot.TargetPath != "new.txt" {
				t.Fatalf("running mutation snapshot = %#v", snapshot)
			}
			return nil
		},
	)
	if err != nil {
		t.Fatalf("runTrackedMutation error = %v", err)
	}
	snapshot, ok := s3ops.GetTransferSnapshot(taskID)
	if !ok || snapshot.Status != "done" || snapshot.Type != "move" {
		t.Fatalf("completed mutation snapshot = %#v", snapshot)
	}
}

func assertCompletedUploadSnapshot(t *testing.T, taskID string, size int64) {
	t.Helper()

	snapshot, ok := s3ops.GetTransferSnapshot(taskID)
	if !ok {
		t.Fatal("tracked transfer snapshot missing")
	}
	if snapshot.Status != "done" {
		t.Fatalf("transfer status = %q, want done", snapshot.Status)
	}
	if snapshot.BytesCompleted != snapshot.TotalBytes || snapshot.TotalBytes != size {
		t.Fatalf(
			"transfer bytes = %d/%d, want %d/%d",
			snapshot.BytesCompleted,
			snapshot.TotalBytes,
			size,
			size,
		)
	}
}
