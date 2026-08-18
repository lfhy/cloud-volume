// Mount pending-content tests pin local chunk reads before provider confirmation.
package mount

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"remote-storage/go/mount/metadata"
)

type pendingRangeTrapBackend struct {
	mountTestBackend
	rangeCalls    int
	downloadCalls int
}

func (b *pendingRangeTrapBackend) ReadObjectRange(
	context.Context, string, string, int64, int64,
) ([]byte, error) {
	b.rangeCalls++
	return []byte("remote-bytes"), nil
}

func (b *pendingRangeTrapBackend) DownloadFile(
	context.Context, string, string, string, string,
) error {
	b.downloadCalls++
	return os.ErrNotExist
}

func TestMountReadsPendingPageChunksBeforeProvider(t *testing.T) {
	access := newTestBucketAccess(t)
	attachMetadataReadService(t, access, &metadataReadTestBackend{})
	service := access.metadataService()
	service.SetQuietPeriod(time.Hour)
	if _, _, err := service.WritePath(
		context.Background(), "pending.txt", strings.NewReader("local-bytes"), 11,
		metadata.WriteOptions{Origin: "page"},
	); err != nil {
		t.Fatal(err)
	}
	trap := &pendingRangeTrapBackend{}
	access.backend = trap
	data, err := access.readRemoteRange(context.Background(), "pending.txt", 0, 11)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "local-bytes" {
		t.Fatalf("pending range = %q, want local bytes", data)
	}
	if trap.rangeCalls != 0 {
		t.Fatalf("pending range called provider %d times", trap.rangeCalls)
	}
	localPath, _, err := access.ensureLocalFile(context.Background(), "pending.txt")
	if err != nil {
		t.Fatal(err)
	}
	local, err := os.ReadFile(localPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(local) != "local-bytes" || trap.downloadCalls != 0 {
		t.Fatalf("materialized pending file=%q download_calls=%d", local, trap.downloadCalls)
	}
}

func TestPendingGenerationInvalidatesEqualRemoteStampCache(t *testing.T) {
	access := newTestBucketAccess(t)
	attachMetadataReadService(t, access, &metadataReadTestBackend{})
	service := access.metadataService()
	service.SetQuietPeriod(time.Hour)
	options := metadata.WriteOptions{Origin: "page", MTime: "2026-08-18 00:00:00"}
	if _, _, err := service.WritePath(
		context.Background(), "same.txt", strings.NewReader("old-data"), 8, options,
	); err != nil {
		t.Fatal(err)
	}
	firstPath, _, err := access.ensureLocalFile(context.Background(), "same.txt")
	if err != nil {
		t.Fatal(err)
	}
	first, err := os.ReadFile(firstPath)
	if err != nil || string(first) != "old-data" {
		t.Fatalf("first pending materialization = %q err=%v", first, err)
	}
	if _, _, err := service.WritePath(
		context.Background(), "same.txt", strings.NewReader("new-data"), 8, options,
	); err != nil {
		t.Fatal(err)
	}
	secondPath, _, err := access.ensureLocalFile(context.Background(), "same.txt")
	if err != nil {
		t.Fatal(err)
	}
	second, err := os.ReadFile(secondPath)
	if err != nil || string(second) != "new-data" {
		t.Fatalf("second pending materialization = %q err=%v", second, err)
	}
}

func TestWebDAVReadRejectsStaleCacheForNewPendingGeneration(t *testing.T) {
	access := newTestBucketAccess(t)
	attachMetadataReadService(t, access, &metadataReadTestBackend{})
	service := access.metadataService()
	service.SetQuietPeriod(time.Hour)
	options := metadata.WriteOptions{Origin: "page", MTime: "2026-08-18 00:00:00"}
	if _, _, err := service.WritePath(
		context.Background(), "webdav.txt", strings.NewReader("old-data"), 8, options,
	); err != nil {
		t.Fatal(err)
	}
	if _, _, err := access.ensureLocalFile(context.Background(), "webdav.txt"); err != nil {
		t.Fatal(err)
	}
	if _, _, err := service.WritePath(
		context.Background(), "webdav.txt", strings.NewReader("new-data"), 8, options,
	); err != nil {
		t.Fatal(err)
	}
	trap := &pendingRangeTrapBackend{}
	access.backend = trap
	file, err := newReadableWebDAVFile(context.Background(), access, "webdav.txt")
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	if file.file != nil {
		t.Fatal("stale cache file bypassed pending generation validation")
	}
	buffer := make([]byte, 8)
	count, err := file.Read(buffer)
	if err != nil {
		t.Fatal(err)
	}
	if got := string(buffer[:count]); got != "new-data" {
		t.Fatalf("WebDAV bytes = %q, want new pending content", got)
	}
	if trap.rangeCalls != 0 {
		t.Fatalf("WebDAV pending read called provider %d times", trap.rangeCalls)
	}
}
