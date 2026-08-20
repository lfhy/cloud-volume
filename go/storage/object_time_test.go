// Object timestamp adapter tests pin the shared client-local wall-clock contract.
package storage

import (
	"net/http"
	"os"
	"testing"
	"time"

	ftpclient "github.com/jlaffaye/ftp"
)

type objectTimeFileInfo struct {
	name    string
	modTime time.Time
}

func (i objectTimeFileInfo) Name() string       { return i.name }
func (i objectTimeFileInfo) Size() int64        { return 0 }
func (i objectTimeFileInfo) Mode() os.FileMode  { return 0o644 }
func (i objectTimeFileInfo) ModTime() time.Time { return i.modTime }
func (i objectTimeFileInfo) IsDir() bool        { return false }
func (i objectTimeFileInfo) Sys() any           { return nil }

func TestProviderObjectTimesUseLocalWallClock(t *testing.T) {
	originalLocal := time.Local
	localZone := time.FixedZone("UTC+8", 8*60*60)
	time.Local = localZone
	t.Cleanup(func() {
		time.Local = originalLocal
	})

	source := time.Date(2026, time.June, 8, 12, 34, 56, 0, time.UTC)
	const want = "2026-06-08 20:34:56"
	file := objectTimeFileInfo{name: "entry.txt", modTime: source}

	if got := sftpEntryFromInfo("", file).LastModified; got != want {
		t.Fatalf("sftp list mtime = %q, want %q", got, want)
	}
	if got := sftpEntryFromStat("entry.txt", file).LastModified; got != want {
		t.Fatalf("sftp stat mtime = %q, want %q", got, want)
	}
	if got := ftpEntryFromInfo("", &ftpclient.Entry{Name: "entry.txt", Time: source}).LastModified; got != want {
		t.Fatalf("ftp mtime = %q, want %q", got, want)
	}
	if got := parseHTTPTime(source.Format(http.TimeFormat)); got != want {
		t.Fatalf("webdav mtime = %q, want %q", got, want)
	}
}
