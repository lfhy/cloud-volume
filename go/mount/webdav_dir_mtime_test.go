// Directory mtime tests pin stable PROPFIND timestamps so Finder does not
// treat every refresh as a modification.
package mount

import (
	"os"
	"testing"
	"time"

	s3ops "remote-storage/go/s3"
)

func TestDirectoryHandleMTimeComesFromObject(t *testing.T) {
	originalLocal := time.Local
	localZone := time.FixedZone("UTC+8", 8*60*60)
	time.Local = localZone
	t.Cleanup(func() {
		time.Local = originalLocal
	})

	handle := newDirectoryHandle(nil, "docs", s3ops.ObjectInfo{
		Key: "docs", IsDir: true, LastModified: "2026-08-18 10:00:00",
	})
	info, err := handle.Stat()
	if err != nil {
		t.Fatalf("Stat() error = %v", err)
	}
	want := time.Date(2026, 8, 18, 10, 0, 0, 0, localZone)
	if !info.ModTime().Equal(want) {
		t.Fatalf("directory mtime = %v, want %v", info.ModTime(), want)
	}
}

func TestDirectoryInfoFallbackMTimeIsStable(t *testing.T) {
	t.Parallel()

	first := fileInfoFromObject(s3ops.ObjectInfo{Key: "docs", IsDir: true})
	second := fileInfoFromObject(s3ops.ObjectInfo{Key: "docs", IsDir: true})
	if !first.ModTime().Equal(second.ModTime()) {
		t.Fatalf("directory fallback mtime moved: %v vs %v", first.ModTime(), second.ModTime())
	}
	if first.ModTime().Before(time.Unix(0, 0)) {
		t.Fatalf("directory fallback mtime %v predates epoch", first.ModTime())
	}

	fileInfo := fileInfoFromObject(s3ops.ObjectInfo{Key: "a.txt", LastModified: "2026-01-02 03:04:05"})
	wantFile := time.Date(2026, 1, 2, 3, 4, 5, 0, time.Local)
	if !fileInfo.ModTime().Equal(wantFile) {
		t.Fatalf("file mtime = %v, want %v", fileInfo.ModTime(), wantFile)
	}

	var _ os.FileInfo = first // virtualFileInfo satisfies os.FileInfo
}
