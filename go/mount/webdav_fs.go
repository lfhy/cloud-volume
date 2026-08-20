// WebDAV filesystem maps Finder/WebDAV operations onto one S3 bucket view.
package mount

import (
	"context"
	"io/fs"
	"os"
	"path"
	"strings"
	"time"

	"golang.org/x/net/webdav"
)

type webDAVFS struct {
	access *bucketAccess
}

func (f *webDAVFS) Mkdir(ctx context.Context, name string, _ os.FileMode) error {
	return f.access.createDirectory(ctx, normalizeWebDAVName(name))
}

func (f *webDAVFS) OpenFile(
	ctx context.Context,
	name string,
	flag int,
	perm os.FileMode,
) (webdav.File, error) {
	clean := normalizeWebDAVName(name)
	if webDAVRequestMethod(ctx) == "LOCK" && flag == os.O_RDWR|os.O_CREATE|os.O_TRUNC {
		return newWebDAVLockNullFile(clean), nil
	}
	if f.access.overlay.handles(clean) {
		file, err := f.access.overlay.openFile(ctx, clean, flag, perm)
		if err != nil {
			return nil, err
		}
		return newLocalWebDAVFile(file), nil
	}
	// x/net/webdav uses an exact O_RDWR open only to inspect optional dead
	// property support during PROPPATCH. Keep that metadata probe away from the
	// staged content-write path so Finder metadata cannot download/re-upload a file.
	if flag == os.O_RDWR {
		return newMetadataWebDAVFile(ctx, f.access, clean)
	}
	switch {
	case flag&os.O_CREATE != 0 || flag&os.O_WRONLY != 0 || flag&os.O_RDWR != 0 || flag&os.O_TRUNC != 0:
		return newWritableWebDAVFile(ctx, f.access, clean, perm, flag)
	default:
		return newReadableWebDAVFile(ctx, f.access, clean)
	}
}

func (f *webDAVFS) RemoveAll(ctx context.Context, name string) error {
	clean := normalizeWebDAVName(name)
	if f.access.overlay.handles(clean) {
		return f.access.overlay.removeAll(clean)
	}
	info, err := f.Stat(ctx, clean)
	if err != nil {
		return err
	}
	return f.access.deletePath(ctx, clean, info.IsDir())
}

func (f *webDAVFS) Rename(ctx context.Context, oldName, newName string) error {
	oldClean := normalizeWebDAVName(oldName)
	newClean := normalizeWebDAVName(newName)
	info, err := f.Stat(ctx, oldClean)
	if err != nil {
		return err
	}
	return f.access.renamePath(ctx, oldClean, newClean, info.IsDir())
}

func (f *webDAVFS) Stat(ctx context.Context, name string) (os.FileInfo, error) {
	clean := normalizeWebDAVName(name)
	if clean == "" {
		return virtualFileInfo{name: "/", size: 0, mode: fs.ModeDir | 0o755, modTime: time.Time{}, isDir: true}, nil
	}
	if f.access.overlay.handles(clean) {
		info, err := f.access.overlay.statPath(clean)
		if err != nil {
			return nil, err
		}
		return info, nil
	}
	info, err := f.access.statPath(ctx, clean)
	if err != nil {
		return nil, err
	}
	return fileInfoFromObject(info), nil
}

func normalizeWebDAVName(name string) string {
	clean := path.Clean("/" + strings.TrimSpace(name))
	return strings.Trim(clean, "/")
}
