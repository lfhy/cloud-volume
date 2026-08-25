// SFTP backend integration tests using the in-process mock SSH/SFTP server.
package storage

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

// sftpTestConfig builds a RemoteStorageConfig pointing at the mock SFTP server.
func sftpTestConfig(addr, user, pass string) storageconfig.RemoteStorageConfig {
	return storageconfig.RemoteStorageConfig{
		StorageType:      storageconfig.StorageTypeSFTP,
		Endpoint:         addr,
		FTPUsername:      user,
		FTPPassword:      pass,
		HasFTPPassword:   true,
		MappedBucketName: "SFTP",
	}
}

func TestSFTPDisablesSpeculativeMountPrefetch(t *testing.T) {
	backend := newSFTPBackend(sftpTestConfig("127.0.0.1:22", "u", "p"))
	if SupportsMountPrefetch(backend) {
		t.Fatal("SFTP mount prefetch should stay disabled")
	}
	if SupportsMountRemotePolling(backend) {
		t.Fatal("SFTP mount remote polling should stay disabled")
	}
}

func TestSFTPClientHonorsCanceledContextBeforeDial(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	backend := sftpBackend{cfg: sftpTestConfig("203.0.113.1:22", "u", "p")}
	_, _, err := backend.sftpClient(ctx)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("sftpClient error = %v, want context canceled", err)
	}
}

func TestSFTPListObjectsPage(t *testing.T) {
	srv := newMockSFTPServer(t, "sftpuser", "sftppass")
	defer srv.Stop()

	backend := newSFTPBackend(sftpTestConfig(srv.endpoint(), "sftpuser", "sftppass"))

	// Seed a file and directory by uploading through the backend itself.
	if err := backend.UploadReader(nil, "SFTP", "hello.txt", strings.NewReader("hello sftp"), 10, "", "hello.txt"); err != nil {
		t.Fatalf("seed upload error: %v", err)
	}
	if err := backend.CreateDirectory(nil, "SFTP", "", "docs"); err != nil {
		t.Fatalf("seed mkdir docs: %v", err)
	}

	page, err := backend.ListObjectsPage(nil, "SFTP", "", "", 200)
	if err != nil {
		t.Fatalf("ListObjectsPage error: %v", err)
	}
	if len(page.Items) != 2 {
		t.Fatalf("expected 2 root entries, got %d: %+v", len(page.Items), page.Items)
	}
	// Directory first.
	if !page.Items[0].IsDir || page.Items[0].Key != "docs/" {
		t.Fatalf("first item = %+v, want docs/", page.Items[0])
	}
	if page.Items[1].IsDir || page.Items[1].Key != "hello.txt" {
		t.Fatalf("second item = %+v, want hello.txt", page.Items[1])
	}
}

func TestSFTPUploadAndRead(t *testing.T) {
	srv := newMockSFTPServer(t, "u", "p")
	defer srv.Stop()

	backend := newSFTPBackend(sftpTestConfig(srv.endpoint(), "u", "p"))
	if err := backend.UploadReader(nil, "SFTP", "data/test.bin", strings.NewReader("hello sftp"), 10, "", "test.bin"); err != nil {
		t.Fatalf("UploadReader error: %v", err)
	}
	data, err := backend.ReadObjectRange(nil, "SFTP", "data/test.bin", 6, 4)
	if err != nil {
		t.Fatalf("ReadObjectRange error: %v", err)
	}
	if string(data) != "sftp" {
		t.Fatalf("data = %q, want 'sftp'", string(data))
	}
}

func TestSFTPUploadFileFinishesQueuedTransfer(t *testing.T) {
	srv := newMockSFTPServer(t, "u", "p")
	defer srv.Stop()

	localPath := filepath.Join(t.TempDir(), "tracked.txt")
	if err := os.WriteFile(localPath, []byte("tracked upload"), 0o644); err != nil {
		t.Fatalf("write upload source: %v", err)
	}
	taskID := "sftp-upload-file-finishes-queued-transfer"
	s3ops.QueueTransfer(taskID, "upload", "SFTP", "tracked.txt", localPath, 14)
	t.Cleanup(func() { s3ops.ForgetTransfer(taskID) })

	backend := newSFTPBackend(sftpTestConfig(srv.endpoint(), "u", "p"))
	if err := backend.UploadFile(nil, "SFTP", "tracked.txt", localPath, taskID); err != nil {
		t.Fatalf("UploadFile error: %v", err)
	}
	assertCompletedUploadSnapshot(t, taskID, 14)
}

func TestSFTPHeadObject(t *testing.T) {
	srv := newMockSFTPServer(t, "u", "p")
	defer srv.Stop()

	backend := newSFTPBackend(sftpTestConfig(srv.endpoint(), "u", "p"))
	if err := backend.UploadReader(nil, "SFTP", "hello.txt", strings.NewReader("hello sftp"), 10, "", "hello.txt"); err != nil {
		t.Fatalf("seed upload: %v", err)
	}
	info, err := backend.HeadObject(nil, "SFTP", "hello.txt")
	if err != nil {
		t.Fatalf("HeadObject error: %v", err)
	}
	if info.Key != "hello.txt" || info.Size != 10 || info.IsDir {
		t.Fatalf("info = %+v, want hello.txt size=10", info)
	}
}

func TestSFTPCreateAndDeleteDirectory(t *testing.T) {
	srv := newMockSFTPServer(t, "u", "p")
	defer srv.Stop()

	backend := newSFTPBackend(sftpTestConfig(srv.endpoint(), "u", "p"))
	if err := backend.CreateDirectory(nil, "SFTP", "", "testdir"); err != nil {
		t.Fatalf("CreateDirectory error: %v", err)
	}
	info, err := backend.HeadObject(nil, "SFTP", "testdir")
	if err != nil {
		t.Fatalf("HeadObject(testdir) error: %v", err)
	}
	if !info.IsDir || info.LastModified == "" {
		t.Fatalf("directory stat = %+v, want directory with LastModified", info)
	}
	page, err := backend.ListObjectsPage(nil, "SFTP", "", "", 200)
	if err != nil {
		t.Fatalf("list after mkdir error: %v", err)
	}
	found := false
	for _, item := range page.Items {
		if item.Key == "testdir/" && item.IsDir {
			found = true
		}
	}
	if !found {
		t.Fatalf("testdir/ not found: %+v", page.Items)
	}
	if err := backend.UploadReader(nil, "SFTP", "testdir/nested.txt", strings.NewReader("nested"), 6, "", "nested.txt"); err != nil {
		t.Fatalf("seed nested file: %v", err)
	}
	if err := backend.DeleteObject(nil, "SFTP", "testdir", true, ""); err != nil {
		t.Fatalf("DeleteObject(testdir) error: %v", err)
	}
	page, err = backend.ListObjectsPage(nil, "SFTP", "", "", 200)
	if err != nil {
		t.Fatalf("list after recursive delete error: %v", err)
	}
	for _, item := range page.Items {
		if item.Key == "testdir/" {
			t.Fatalf("testdir/ remained after recursive delete: %+v", page.Items)
		}
	}
}

func TestSFTPRenameObject(t *testing.T) {
	srv := newMockSFTPServer(t, "u", "p")
	defer srv.Stop()

	backend := newSFTPBackend(sftpTestConfig(srv.endpoint(), "u", "p"))
	if err := backend.UploadReader(nil, "SFTP", "old.txt", strings.NewReader("rename me"), 9, "", "old.txt"); err != nil {
		t.Fatalf("seed upload: %v", err)
	}
	if err := backend.RenameObject(nil, "SFTP", "old.txt", false, "new.txt"); err != nil {
		t.Fatalf("RenameObject error: %v", err)
	}
	info, err := backend.HeadObject(nil, "SFTP", "new.txt")
	if err != nil {
		t.Fatalf("HeadObject(new.txt) after rename: %v", err)
	}
	if info.Key != "new.txt" {
		t.Fatalf("info.Key = %q, want new.txt", info.Key)
	}
}
