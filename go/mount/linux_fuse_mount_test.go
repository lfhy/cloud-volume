//go:build linux

package mount

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	gofusefs "github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

func TestLinuxFuseServesCachedFiles(t *testing.T) {
	if _, err := os.Stat("/dev/fuse"); err != nil {
		t.Skip("/dev/fuse is not available")
	}

	access, err := newBucketAccess(storageconfig.RemoteStorageConfig{}, "demo")
	if err != nil {
		t.Fatalf("newBucketAccess: %v", err)
	}
	t.Cleanup(func() {
		access.writeback.cancel("hello.txt")
		access.cache.removeLocalFile("hello.txt", false)
		_ = access.close()
	})

	cachePath := access.cachePathFor("hello.txt")
	if err := os.MkdirAll(filepath.Dir(cachePath), 0o755); err != nil {
		t.Fatalf("mkdir cache: %v", err)
	}
	if err := os.WriteFile(cachePath, []byte("hello from fuse"), 0o644); err != nil {
		t.Fatalf("seed cache file: %v", err)
	}
	access.registerLocalWrite("hello.txt", cachePath, int64(len("hello from fuse")))
	access.cache.storeList("", []s3ops.ObjectInfo{{
		Key:          "hello.txt",
		Size:         int64(len("hello from fuse")),
		LastModified: time.Now().Format("2006-01-02 15:04:05"),
		IsDir:        false,
	}})

	mountDir := t.TempDir()
	server, err := gofusefs.Mount(mountDir, newLinuxFuseNode(access, true), &gofusefs.Options{
		EntryTimeout: ptrDuration(time.Second),
		AttrTimeout:  ptrDuration(time.Second),
		MountOptions: fuse.MountOptions{DisableXAttrs: true},
	})
	if err != nil {
		t.Fatalf("mount fuse: %v", err)
	}
	defer func() {
		if unmountErr := server.Unmount(); unmountErr != nil {
			t.Fatalf("unmount fuse: %v", unmountErr)
		}
	}()

	data, err := os.ReadFile(filepath.Join(mountDir, "hello.txt"))
	if err != nil {
		t.Fatalf("read mounted file: %v", err)
	}
	if string(data) != "hello from fuse" {
		t.Fatalf("unexpected mounted file contents %q", string(data))
	}
}

func TestLinuxFuseWriteStagesLocalCache(t *testing.T) {
	if _, err := os.Stat("/dev/fuse"); err != nil {
		t.Skip("/dev/fuse is not available")
	}

	access, err := newBucketAccess(storageconfig.RemoteStorageConfig{}, "demo")
	if err != nil {
		t.Fatalf("newBucketAccess: %v", err)
	}
	t.Cleanup(func() {
		access.writeback.cancel("created.txt")
		access.cache.removeLocalFile("created.txt", false)
		_ = access.close()
	})
	access.cache.storeList("", []s3ops.ObjectInfo{})
	access.cache.markDeleted("created.txt", false)

	mountDir := t.TempDir()
	server, err := gofusefs.Mount(mountDir, newLinuxFuseNode(access, true), &gofusefs.Options{
		EntryTimeout: ptrDuration(time.Second),
		AttrTimeout:  ptrDuration(time.Second),
		MountOptions: fuse.MountOptions{DisableXAttrs: true},
	})
	if err != nil {
		t.Fatalf("mount fuse: %v", err)
	}
	defer func() {
		access.writeback.cancel("created.txt")
		if unmountErr := server.Unmount(); unmountErr != nil {
			t.Fatalf("unmount fuse: %v", unmountErr)
		}
	}()

	targetPath := filepath.Join(mountDir, "created.txt")
	if err := os.WriteFile(targetPath, []byte("queued"), 0o644); err != nil {
		t.Fatalf("write mounted file: %v", err)
	}

	item, ok := access.cache.localFile("created.txt")
	if !ok {
		t.Fatal("expected local cache marker for mounted write")
	}
	data, err := os.ReadFile(item.localPath)
	if err != nil {
		t.Fatalf("read staged local cache file: %v", err)
	}
	if string(data) != "queued" {
		t.Fatalf("unexpected staged file contents %q", string(data))
	}
}

func TestLinuxFuseLargeWriteKeepsCacheFileOnClose(t *testing.T) {
	if _, err := os.Stat("/dev/fuse"); err != nil {
		t.Skip("/dev/fuse is not available")
	}

	access, err := newBucketAccess(storageconfig.RemoteStorageConfig{}, "demo")
	if err != nil {
		t.Fatalf("newBucketAccess: %v", err)
	}
	t.Cleanup(func() {
		access.writeback.cancel("large.bin")
		access.cache.removeLocalFile("large.bin", false)
		_ = access.close()
	})
	access.cache.storeList("", []s3ops.ObjectInfo{})
	access.cache.markDeleted("large.bin", false)

	mountDir := t.TempDir()
	server, err := gofusefs.Mount(mountDir, newLinuxFuseNode(access, true), &gofusefs.Options{
		EntryTimeout: ptrDuration(time.Second),
		AttrTimeout:  ptrDuration(time.Second),
		MountOptions: fuse.MountOptions{DisableXAttrs: true},
	})
	if err != nil {
		t.Fatalf("mount fuse: %v", err)
	}
	defer func() {
		access.writeback.cancel("large.bin")
		if unmountErr := server.Unmount(); unmountErr != nil {
			t.Fatalf("unmount fuse: %v", unmountErr)
		}
	}()

	targetPath := filepath.Join(mountDir, "large.bin")
	payload := make([]byte, 8<<20)
	for index := range payload {
		payload[index] = byte(index)
	}
	if err := os.WriteFile(targetPath, payload, 0o644); err != nil {
		t.Fatalf("write mounted file: %v", err)
	}

	item, ok := access.cache.localFile("large.bin")
	if !ok {
		t.Fatal("expected local cache marker for large mounted write")
	}
	info, err := os.Stat(item.localPath)
	if err != nil {
		t.Fatalf("stat staged local cache file: %v", err)
	}
	if info.Size() != int64(len(payload)) {
		t.Fatalf("unexpected staged file size %d", info.Size())
	}
}

func TestLinuxFuseAutoSyncSequentialRangeTracksFullParts(t *testing.T) {
	t.Parallel()

	access, err := newBucketAccess(storageconfig.RemoteStorageConfig{}, "demo")
	if err != nil {
		t.Fatalf("newBucketAccess: %v", err)
	}
	t.Cleanup(func() {
		_ = access.close()
	})
	access.autoSync = true

	localPath := access.cachePathFor("seq.bin")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir cache path: %v", err)
	}
	file, err := os.OpenFile(localPath, os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0o644)
	if err != nil {
		t.Fatalf("open local file: %v", err)
	}
	t.Cleanup(func() {
		_ = file.Close()
	})

	handle := &linuxFuseFileHandle{
		access:      access,
		virtualPath: "seq.bin",
		localPath:   localPath,
		file:        file,
		writable:    true,
	}
	partSize := s3ops.ChooseMultipartUploadPartSize(128 << 20)
	handle.noteWriteRange(0, int(partSize/2))
	if ready := handle.autoSyncReadySizeLocked(); ready != 0 {
		t.Fatalf("expected no full ready part, got %d", ready)
	}
	handle.noteWriteRange(partSize/2, int(partSize))
	if ready := handle.autoSyncReadySizeLocked(); ready != partSize {
		t.Fatalf("expected ready size %d, got %d", partSize, ready)
	}
}

func TestLinuxFuseAutoSyncDisablesOnRandomWrite(t *testing.T) {
	t.Parallel()

	handle := &linuxFuseFileHandle{}
	handle.noteWriteRange(0, 1024)
	handle.noteWriteRange(2048, 1024)
	if !handle.autoSyncDisabled {
		t.Fatal("expected random write to disable autosync")
	}
}

func TestLinuxFuseAutoSyncReturnsWithoutUploadWhenReleased(t *testing.T) {
	t.Parallel()

	access, err := newBucketAccess(storageconfig.RemoteStorageConfig{}, "demo")
	if err != nil {
		t.Fatalf("newBucketAccess: %v", err)
	}
	t.Cleanup(func() {
		_ = access.close()
	})
	localPath := access.cachePathFor("released.bin")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir cache path: %v", err)
	}
	partSize := s3ops.ChooseMultipartUploadPartSize(128 << 20)
	if err := os.WriteFile(localPath, make([]byte, partSize), 0o644); err != nil {
		t.Fatalf("seed cache file: %v", err)
	}
	file, err := os.OpenFile(localPath, os.O_RDWR, 0o644)
	if err != nil {
		t.Fatalf("open local file: %v", err)
	}
	t.Cleanup(func() {
		_ = file.Close()
	})

	handle := &linuxFuseFileHandle{
		access:          access,
		virtualPath:     "released.bin",
		localPath:       localPath,
		file:            file,
		writable:        true,
		sequentialDirty: true,
		sequentialEnd:   partSize,
		autoSyncedSize:  0,
		released:        true,
	}
	if err := handle.autoSyncReadyRange(context.Background(), partSize); err != nil {
		t.Fatalf("expected released autosync to no-op, got %v", err)
	}
}

func TestLinuxFuseFsyncIsLocalOnly(t *testing.T) {
	access, err := newBucketAccess(storageconfig.RemoteStorageConfig{}, "demo")
	if err != nil {
		t.Fatal(err)
	}
	defer access.close()
	localPath := access.cachePathFor("sync.txt")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatal(err)
	}
	file, err := os.OpenFile(localPath, os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	handle := &linuxFuseFileHandle{access: access, virtualPath: "sync.txt", localPath: localPath, file: file}
	if errno := handle.Fsync(context.Background(), 0); errno != 0 {
		t.Fatalf("Fsync errno = %v", errno)
	}
	if errno := handle.Flush(context.Background()); errno != 0 {
		t.Fatalf("Flush errno = %v", errno)
	}
	if access.writeback.hasPendingAtOrBelow("sync.txt", false) {
		t.Fatal("local fsync unexpectedly queued remote write")
	}
	_ = file.Close()
}
