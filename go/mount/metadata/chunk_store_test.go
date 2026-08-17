// Chunk-store tests pin block-level deduplication, replay safety, and splice fidelity.
package metadata

import (
	"bytes"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStageWriteDeduplicatesChunksAndBalancesNlink(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	first, err := service.StageWrite(2, 1, strings.NewReader("same payload"), 12)
	if err != nil {
		t.Fatal(err)
	}
	second, err := service.StageWrite(3, 1, strings.NewReader("same payload"), 12)
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Chunks) != 1 || !slicesEqual(first.Chunks, second.Chunks) {
		t.Fatalf("expected one shared chunk, first=%+v second=%+v", first, second)
	}
	hash := first.Chunks[0]
	if strings.HasPrefix(service.chunkPath(hash), service.store.namespace.Root) {
		t.Fatalf("chunk path %q must be outside metadata root %q", service.chunkPath(hash), service.store.namespace.Root)
	}
	if files, err := service.chunkFiles(); err != nil || len(files) != 1 {
		t.Fatalf("chunk files = %v, %v; want one", files, err)
	}
	if record := chunkRecordForTest(t, service, hash); record.Nlink != 2 {
		t.Fatalf("nlink = %d, want 2", record.Nlink)
	}
	if err := service.retireContent(first.Inode, first.Generation); err != nil {
		t.Fatal(err)
	}
	if record := chunkRecordForTest(t, service, hash); record.Nlink != 1 {
		t.Fatalf("nlink after first retire = %d, want 1", record.Nlink)
	}
	if err := service.retireContent(second.Inode, second.Generation); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(service.chunkPath(hash)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("shared chunk remains after final retire: %v", err)
	}
}

func TestChunksPreservePartialOverlapAndSpliceExactBytes(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	blockA := bytes.Repeat([]byte("a"), chunkSize)
	blockB := bytes.Repeat([]byte("b"), chunkSize)
	firstData := bytes.Join([][]byte{blockA, blockB, []byte("old tail")}, nil)
	secondData := bytes.Join([][]byte{blockA, blockB, []byte("new tail")}, nil)
	first, err := service.StageWrite(2, 1, bytes.NewReader(firstData), int64(len(firstData)))
	if err != nil {
		t.Fatal(err)
	}
	second, err := service.StageWrite(3, 1, bytes.NewReader(secondData), int64(len(secondData)))
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Chunks) != 3 || len(second.Chunks) != 3 {
		t.Fatalf("unexpected chunk counts: first=%d second=%d", len(first.Chunks), len(second.Chunks))
	}
	if first.Chunks[0] != second.Chunks[0] || first.Chunks[1] != second.Chunks[1] || first.Chunks[2] == second.Chunks[2] {
		t.Fatalf("partial overlap was not retained: first=%v second=%v", first.Chunks, second.Chunks)
	}
	if files, err := service.chunkFiles(); err != nil || len(files) != 4 {
		t.Fatalf("chunk file count = %d, err=%v; want 4", len(files), err)
	}
	splice, err := service.spliceChunks(second.Chunks, "partial-overlap")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(splice)
	got, err := os.ReadFile(splice)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, secondData) {
		t.Fatal("spliced content differs from staged bytes")
	}
}

func TestStartupSweepDropsUncommittedChunkFiles(t *testing.T) {
	root := filepath.Join(t.TempDir(), "runtime")
	cacheRoot := filepath.Join(t.TempDir(), "cache")
	namespace := Namespace{ID: "test", Root: root, CacheRoot: cacheRoot, Bucket: "bucket"}
	store, err := OpenStore(namespace)
	if err != nil {
		t.Fatal(err)
	}
	service := NewService(store, newFakeBackend())
	payload := []byte("partial source")
	_, err = service.StageWrite(2, 1, &failingChunkReader{payload: payload}, -1)
	if err == nil {
		t.Fatal("expected staging error")
	}
	sum := sha256.Sum256(payload)
	hash := fmt.Sprintf("%x", sum)
	if _, err := os.Stat(service.chunkPath(hash)); err != nil {
		t.Fatalf("expected orphan chunk before restart: %v", err)
	}
	if err := store.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := OpenStore(namespace)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	resumed := NewService(reopened, newFakeBackend())
	if _, err := os.Stat(resumed.chunkPath(hash)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("orphan chunk survived startup sweep: %v", err)
	}
}

func TestRemoveNamespaceDeletesSeparatedChunkData(t *testing.T) {
	cacheRoot := t.TempDir()
	manager := NewManager(filepath.Join(t.TempDir(), "runtime"))
	config := fakeConfig("chunk-profile")
	config.CacheDirectory = cacheRoot
	handle, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
	if err != nil {
		t.Fatal(err)
	}
	ref, err := handle.Service.StageWrite(2, 1, strings.NewReader("remove me"), 9)
	if err != nil {
		t.Fatal(err)
	}
	path := handle.Service.chunkPath(ref.Chunks[0])
	manager.Release(handle)
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("chunk missing before namespace removal: %v", err)
	}
	if err := manager.RemoveNamespace(config, "bucket"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("chunk survived namespace removal: %v", err)
	}
}

func TestChunkRootSurvivesCacheDirectorySettingChange(t *testing.T) {
	oldCacheRoot := t.TempDir()
	newCacheRoot := t.TempDir()
	manager := NewManager(filepath.Join(t.TempDir(), "runtime"))
	config := fakeConfig("chunk-profile")
	config.CacheDirectory = oldCacheRoot
	handle, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
	if err != nil {
		t.Fatal(err)
	}
	ref, err := handle.Service.StageWrite(2, 1, strings.NewReader("durable"), 7)
	if err != nil {
		t.Fatal(err)
	}
	oldPath := handle.Service.chunkPath(ref.Chunks[0])
	manager.Release(handle)

	config.CacheDirectory = newCacheRoot
	reopened, err := manager.AcquireWithBackend(config, "bucket", newFakeBackend())
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Release(reopened)
	if !strings.HasPrefix(reopened.Service.chunkStoreRoot(), oldCacheRoot) {
		t.Fatalf("chunk root changed after config update: %q", reopened.Service.chunkStoreRoot())
	}
	splice, err := reopened.Service.spliceChunks(ref.Chunks, "reopen")
	if err != nil {
		t.Fatal(err)
	}
	_ = os.Remove(splice)
	if _, err := os.Stat(oldPath); err != nil {
		t.Fatalf("original chunk vanished after cache setting change: %v", err)
	}
}

func TestResetGuardProtectsStagedChunkWithoutJournalOp(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	ref, err := service.StageWrite(2, 1, strings.NewReader("guarded"), 7)
	if err != nil {
		t.Fatal(err)
	}
	result, err := service.Reset(false)
	if err != nil {
		t.Fatal(err)
	}
	if result.Reset || !result.Required || result.Pending != 1 {
		t.Fatalf("staged content did not block reset: %+v", result)
	}
	if _, err := service.Reset(true); err != nil {
		t.Fatal(err)
	}
	for _, hash := range ref.Chunks {
		if _, err := os.Stat(service.chunkPath(hash)); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("forced reset did not sweep chunk %s: %v", hash, err)
		}
	}
}

type failingChunkReader struct {
	payload []byte
	read    bool
}

func (r *failingChunkReader) Read(target []byte) (int, error) {
	if r.read {
		return 0, io.EOF
	}
	copy(target, r.payload)
	r.read = true
	return len(r.payload), errors.New("source failed")
}

func chunkRecordForTest(t *testing.T, service *Service, hash string) chunkRecord {
	t.Helper()
	var record chunkRecord
	err := service.store.view(func(tx boltTxT) error {
		raw := tx.Bucket([]byte(bucketChunks)).Get([]byte(hash))
		if raw == nil {
			return ErrNotFound
		}
		return decodeJSON(raw, &record)
	})
	if err != nil {
		t.Fatalf("chunk %s: %v", hash, err)
	}
	return record
}

func slicesEqual(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}
