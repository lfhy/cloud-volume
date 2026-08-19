// Worker mtime tests keep provider-confirmed timestamps visible in the inode view.
package metadata

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

type mkdirMTimeBackend struct {
	*fakeBackend
	lastModified string
}

func (b *mkdirMTimeBackend) CreateDirectory(ctx context.Context, bucket, prefix, name string) error {
	if err := b.fakeBackend.CreateDirectory(ctx, bucket, prefix, name); err != nil {
		return err
	}
	key := name
	if trimmed := strings.Trim(prefix, "/"); trimmed != "" {
		key = trimmed + "/" + name
	}
	info := b.objects["/"+key+"/"]
	info.LastModified = b.lastModified
	b.objects["/"+key+"/"] = info
	return nil
}

func (b *mkdirMTimeBackend) HeadObject(_ context.Context, _ string, key string) (storageops.ObjectInfo, error) {
	info, ok := b.objects["/"+strings.Trim(key, "/")+"/"]
	if !ok {
		return storageops.ObjectInfo{}, os.ErrNotExist
	}
	info.Key = key
	return info, nil
}

func TestWorkerMkdirPersistsConfirmedLastModified(t *testing.T) {
	const remoteMTime = "2026-08-19 10:15:30"
	backend := &mkdirMTimeBackend{
		fakeBackend: newFakeBackend(), lastModified: remoteMTime,
	}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	inode, err := service.CreateDirectory(rootInode, "sftp-dir", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatal(err)
	}
	object, err := service.StatInode(context.Background(), inode)
	if err != nil {
		t.Fatal(err)
	}
	if object.LastModified != remoteMTime {
		t.Fatalf("LastModified = %q, want %q", object.LastModified, remoteMTime)
	}
}
