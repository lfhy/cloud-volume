package mount

import (
	"fmt"
	"io"
	"os"
	"time"
)

// webDAVLockNullFile represents the short-lived resource x/net/webdav asks
// the filesystem to create while processing LOCK for a missing path. Finder
// follows it with PUT; no content or metadata should be journaled by LOCK.
type webDAVLockNullFile struct {
	info os.FileInfo
}

func newWebDAVLockNullFile(path string) *webDAVLockNullFile {
	return &webDAVLockNullFile{info: virtualFileInfo{
		name:    baseName(path),
		mode:    0o644,
		modTime: time.Unix(0, 0),
	}}
}

func (f *webDAVLockNullFile) Close() error             { return nil }
func (f *webDAVLockNullFile) Read([]byte) (int, error) { return 0, io.EOF }
func (f *webDAVLockNullFile) Readdir(int) ([]os.FileInfo, error) {
	return nil, fmt.Errorf("lock-null resource is not a directory")
}
func (f *webDAVLockNullFile) Seek(int64, int) (int64, error) {
	return 0, fmt.Errorf("lock-null resource is not seekable")
}
func (f *webDAVLockNullFile) Stat() (os.FileInfo, error) { return f.info, nil }
func (f *webDAVLockNullFile) Write([]byte) (int, error) {
	return 0, fmt.Errorf("lock-null resource is not writable")
}
