// Directory upload tests verify backend-side folder walking without network I/O.
package storage

import (
	"context"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestUploadDirectoryCreatesTreeAndUploadsFiles(t *testing.T) {
	root := t.TempDir()
	mustMkdir(t, filepath.Join(root, "album", "nested"))
	mustMkdir(t, filepath.Join(root, "album", "empty"))
	mustWriteFile(t, filepath.Join(root, "album", "cover.txt"), "cover")
	mustWriteFile(t, filepath.Join(root, "album", "nested", "track.txt"), "track")
	backend := &directoryUploadTestBackend{}

	err := UploadDirectory(context.Background(), backend, "bucket", "remote/", filepath.Join(root, "album"), "")
	if err != nil {
		t.Fatalf("UploadDirectory returned error: %v", err)
	}

	wantDirs := []string{"remote/album", "remote/album/empty", "remote/album/nested"}
	if !reflect.DeepEqual(backend.directories, wantDirs) {
		t.Fatalf("directories = %#v, want %#v", backend.directories, wantDirs)
	}
	wantFiles := []string{"remote/album/cover.txt", "remote/album/nested/track.txt"}
	sort.Strings(backend.files)
	if !reflect.DeepEqual(backend.files, wantFiles) {
		t.Fatalf("files = %#v, want %#v", backend.files, wantFiles)
	}
}

func TestUploadDirectoryContinuesAfterFileFailure(t *testing.T) {
	root := t.TempDir()
	mustMkdir(t, filepath.Join(root, "album"))
	mustWriteFile(t, filepath.Join(root, "album", "bad.txt"), "bad")
	mustWriteFile(t, filepath.Join(root, "album", "good-a.txt"), "good")
	mustWriteFile(t, filepath.Join(root, "album", "good-b.txt"), "good")
	backend := &directoryUploadTestBackend{
		failKeys: map[string]error{
			"remote/album/bad.txt": errors.New("backend rejected object"),
		},
	}

	err := UploadDirectory(context.Background(), backend, "bucket", "remote/", filepath.Join(root, "album"), "")
	if err == nil {
		t.Fatal("UploadDirectory returned nil error")
	}
	if !strings.Contains(err.Error(), "remote/album/bad.txt") {
		t.Fatalf("error %q did not include failed remote key", err)
	}
	sort.Strings(backend.files)
	wantFiles := []string{"remote/album/good-a.txt", "remote/album/good-b.txt"}
	if !reflect.DeepEqual(backend.files, wantFiles) {
		t.Fatalf("files = %#v, want %#v", backend.files, wantFiles)
	}
}

func TestUploadDirectoryRetriesFileFailure(t *testing.T) {
	root := t.TempDir()
	mustMkdir(t, filepath.Join(root, "album"))
	mustWriteFile(t, filepath.Join(root, "album", "eventual.txt"), "eventual")
	backend := &retryDirectoryUploadTestBackend{
		directoryUploadTestBackend: &directoryUploadTestBackend{
			failAttempts: map[string]int{
				"remote/album/eventual.txt": 2,
			},
		},
	}

	err := UploadDirectory(context.Background(), backend, "bucket", "remote/", filepath.Join(root, "album"), "")
	if err != nil {
		t.Fatalf("UploadDirectory returned error: %v", err)
	}
	if got := backend.attempts["remote/album/eventual.txt"]; got != 3 {
		t.Fatalf("attempts = %d, want 3", got)
	}
	if !reflect.DeepEqual(backend.files, []string{"remote/album/eventual.txt"}) {
		t.Fatalf("files = %#v", backend.files)
	}
}

func mustMkdir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", path, err)
	}
}

func mustWriteFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

type directoryUploadTestBackend struct {
	mu           sync.Mutex
	directories  []string
	files        []string
	failKeys     map[string]error
	failAttempts map[string]int
	attempts     map[string]int
}

func (b *directoryUploadTestBackend) ListBuckets(context.Context) ([]BucketInfo, error) {
	return nil, nil
}

func (b *directoryUploadTestBackend) ListObjectsPage(context.Context, string, string, string, int32) (ObjectPage, error) {
	return ObjectPage{}, nil
}

func (b *directoryUploadTestBackend) HeadObject(context.Context, string, string) (ObjectInfo, error) {
	return ObjectInfo{}, os.ErrNotExist
}

func (b *directoryUploadTestBackend) ReadObjectRange(context.Context, string, string, int64, int64) ([]byte, error) {
	return nil, nil
}

func (b *directoryUploadTestBackend) DirectoryAccess(context.Context, string, string) (DirectoryAccess, error) {
	return DirectoryAccess{Writable: true, Known: true}, nil
}

func (b *directoryUploadTestBackend) CreateDirectory(_ context.Context, _, prefix, name string) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.directories = append(b.directories, cleanRemoteJoin(prefix, name))
	return nil
}

func (b *directoryUploadTestBackend) DeleteObject(context.Context, string, string, bool, string) error {
	return nil
}

func (b *directoryUploadTestBackend) DeleteObjectHard(context.Context, string, string, bool, string) error {
	return nil
}

func (b *directoryUploadTestBackend) ListTrashPage(context.Context, string, string, int32) (TrashPage, error) {
	return TrashPage{}, nil
}

func (b *directoryUploadTestBackend) RestoreTrashItem(context.Context, string, string) error {
	return nil
}

func (b *directoryUploadTestBackend) DeleteTrashItem(context.Context, string, string) error {
	return nil
}

func (b *directoryUploadTestBackend) ClearTrash(context.Context, string) error {
	return nil
}

func (b *directoryUploadTestBackend) RenameObject(context.Context, string, string, bool, string) error {
	return nil
}

func (b *directoryUploadTestBackend) CopyObject(context.Context, string, string, string, bool, string) error {
	return nil
}

func (b *directoryUploadTestBackend) MoveObject(context.Context, string, string, string, bool, string) error {
	return nil
}

func (b *directoryUploadTestBackend) UploadFile(context.Context, string, string, string, string) error {
	return nil
}

func (b *directoryUploadTestBackend) UploadReader(_ context.Context, _, key string, body io.Reader, _ int64, _, _ string) error {
	b.mu.Lock()
	if b.attempts == nil {
		b.attempts = map[string]int{}
	}
	b.attempts[key]++
	attempt := b.attempts[key]
	failAttempts := b.failAttempts[key]
	b.mu.Unlock()
	if failAttempts > 0 && attempt <= failAttempts {
		return errors.New("transient backend error")
	}
	if err := b.failKeys[key]; err != nil {
		return err
	}
	if _, err := io.Copy(io.Discard, body); err != nil {
		return err
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	b.files = append(b.files, key)
	return nil
}

type retryDirectoryUploadTestBackend struct {
	*directoryUploadTestBackend
}

func (b *retryDirectoryUploadTestBackend) DirectoryUploadRetryDelay(error, int) (time.Duration, bool) {
	return 0, true
}

func (b *directoryUploadTestBackend) DownloadFile(context.Context, string, string, string, string) error {
	return nil
}

func (b *directoryUploadTestBackend) StreamObjectToHTTP(context.Context, string, string, bool, http.ResponseWriter) error {
	return nil
}
