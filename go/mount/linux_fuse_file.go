//go:build linux

// Linux FUSE file handles bind kernel reads and writes onto cache files plus delayed writeback.
package mount

import (
	"context"
	"io"
	"log"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	gofusefs "github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"
)

type linuxFuseFileHandle struct {
	access           *bucketAccess
	virtualPath      string
	localPath        string
	file             *os.File
	overlayOnly      bool
	writable         bool
	dirty            bool
	sequentialDirty  bool
	sequentialEnd    int64
	autoSyncedSize   int64
	autoSyncDisabled bool
	autoSyncQueued   bool

	mu       sync.Mutex
	released bool
}

var _ gofusefs.FileReader = (*linuxFuseFileHandle)(nil)
var _ gofusefs.FileWriter = (*linuxFuseFileHandle)(nil)
var _ gofusefs.FileFlusher = (*linuxFuseFileHandle)(nil)
var _ gofusefs.FileFsyncer = (*linuxFuseFileHandle)(nil)
var _ gofusefs.FileReleaser = (*linuxFuseFileHandle)(nil)
var _ gofusefs.FileGetattrer = (*linuxFuseFileHandle)(nil)
var _ gofusefs.FileSetattrer = (*linuxFuseFileHandle)(nil)

func newLinuxFuseFileHandle(
	ctx context.Context,
	access *bucketAccess,
	virtualPath string,
	flags uint32,
	create bool,
	perm os.FileMode,
) (*linuxFuseFileHandle, syscall.Errno) {
	writable := linuxFuseFlagsWritable(flags) || create
	if access.readOnly && writable {
		return nil, syscall.EROFS
	}
	if perm.Perm() == 0 {
		perm = 0o644
	}

	if !writable {
		file, localPath, overlayOnly, errno := linuxOpenReadableLocalFile(ctx, access, virtualPath)
		if errno != 0 {
			return nil, errno
		}
		return &linuxFuseFileHandle{
			access:      access,
			virtualPath: cleanVirtualPath(virtualPath),
			localPath:   localPath,
			file:        file,
			overlayOnly: overlayOnly,
		}, 0
	}

	localPath, overlayOnly, errno := linuxEnsureWritableLocalPath(ctx, access, virtualPath, flags, create)
	if errno != 0 {
		return nil, errno
	}
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return nil, gofusefs.ToErrno(err)
	}
	openFlags := int(flags)
	if create || flags&syscall.O_CREAT != 0 {
		openFlags |= os.O_CREATE
	}
	file, err := os.OpenFile(localPath, openFlags, perm.Perm())
	if err != nil {
		return nil, gofusefs.ToErrno(err)
	}
	if !overlayOnly {
		access.registerLocalWrite(cleanVirtualPath(virtualPath), localPath, fileSize(localPath))
	}
	return &linuxFuseFileHandle{
		access:      access,
		virtualPath: cleanVirtualPath(virtualPath),
		localPath:   localPath,
		file:        file,
		overlayOnly: overlayOnly,
		writable:    true,
		dirty:       create || flags&syscall.O_TRUNC != 0,
	}, 0
}

func (h *linuxFuseFileHandle) Read(
	_ context.Context,
	dest []byte,
	off int64,
) (fuse.ReadResult, syscall.Errno) {
	h.mu.Lock()
	defer h.mu.Unlock()

	count, err := h.file.ReadAt(dest, off)
	switch {
	case err == nil:
		return fuse.ReadResultData(dest[:count]), 0
	case err == io.EOF:
		return fuse.ReadResultData(dest[:count]), 0
	default:
		return nil, gofusefs.ToErrno(err)
	}
}

func (h *linuxFuseFileHandle) Write(
	_ context.Context,
	data []byte,
	off int64,
) (uint32, syscall.Errno) {
	h.mu.Lock()
	defer h.mu.Unlock()

	count, err := h.file.WriteAt(data, off)
	if count > 0 {
		h.dirty = true
		h.noteWriteRange(off, count)
		h.scheduleAutoSyncLocked()
	}
	return uint32(count), gofusefs.ToErrno(err)
}

func (h *linuxFuseFileHandle) Flush(_ context.Context) syscall.Errno {
	h.mu.Lock()
	defer h.mu.Unlock()
	log.Printf("[mount/linux-file] flush path=%q dirty=%t overlay_only=%t", h.virtualPath, h.dirty, h.overlayOnly)
	if h.file == nil {
		return syscall.EBADF
	}
	return gofusefs.ToErrno(h.file.Sync())
}

// Fsync makes the local cache durable without waiting for remote journal work.
// Release remains the single content-admission point, so frequent rsync fsync
// calls do not create one remote operation per write boundary.
func (h *linuxFuseFileHandle) Fsync(_ context.Context, _ uint32) syscall.Errno {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.file == nil {
		return syscall.EBADF
	}
	return gofusefs.ToErrno(h.file.Sync())
}

func (h *linuxFuseFileHandle) Release(_ context.Context) syscall.Errno {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.released {
		return 0
	}
	h.released = true
	log.Printf("[mount/linux-file] release path=%q dirty=%t overlay_only=%t", h.virtualPath, h.dirty, h.overlayOnly)

	if errno := h.publishLocked(); errno != 0 {
		_ = h.file.Close()
		return errno
	}
	return gofusefs.ToErrno(h.file.Close())
}

func (h *linuxFuseFileHandle) Getattr(_ context.Context, out *fuse.AttrOut) syscall.Errno {
	h.mu.Lock()
	defer h.mu.Unlock()

	info, err := h.file.Stat()
	if err != nil {
		return gofusefs.ToErrno(err)
	}
	fillLinuxFuseLocalAttr(&out.Attr, info, info.IsDir())
	return 0
}

func (h *linuxFuseFileHandle) Setattr(
	_ context.Context,
	in *fuse.SetAttrIn,
	out *fuse.AttrOut,
) syscall.Errno {
	h.mu.Lock()
	defer h.mu.Unlock()

	if errno := linuxApplySetattr(h.localPath, in); errno != 0 {
		return errno
	}
	h.dirty = true
	h.autoSyncDisabled = true
	h.autoSyncQueued = false
	info, err := h.file.Stat()
	if err != nil {
		return gofusefs.ToErrno(err)
	}
	fillLinuxFuseLocalAttr(&out.Attr, info, info.IsDir())
	return 0
}

func (h *linuxFuseFileHandle) publishLocked() syscall.Errno {
	if !h.writable {
		return 0
	}
	if !h.dirty || h.overlayOnly {
		return 0
	}

	log.Printf(
		"[mount/linux-file] publish path=%q local_path=%q size=%d",
		h.virtualPath,
		h.localPath,
		fileSize(h.localPath),
	)
	h.autoSyncQueued = false
	if err := h.access.stageLocalWrite(h.virtualPath, h.localPath, fileSize(h.localPath)); err != nil {
		return gofusefs.ToErrno(err)
	}
	h.dirty = false
	return 0
}

func linuxOpenReadableLocalFile(
	ctx context.Context,
	access *bucketAccess,
	virtualPath string,
) (*os.File, string, bool, syscall.Errno) {
	clean := cleanVirtualPath(virtualPath)
	if access.overlay.handles(clean) {
		file, err := access.overlay.openFile(ctx, clean, os.O_RDONLY, 0o644)
		if err != nil {
			return nil, "", false, gofusefs.ToErrno(err)
		}
		return file, access.overlay.localPath(clean), true, 0
	}
	localPath, _, err := access.ensureLocalFile(ctx, clean)
	if err != nil {
		return nil, "", false, gofusefs.ToErrno(err)
	}
	file, err := os.Open(localPath)
	if err != nil {
		return nil, "", false, gofusefs.ToErrno(err)
	}
	return file, localPath, false, 0
}

func linuxEnsureWritableLocalPath(
	ctx context.Context,
	access *bucketAccess,
	virtualPath string,
	flags uint32,
	create bool,
) (string, bool, syscall.Errno) {
	clean := cleanVirtualPath(virtualPath)
	if err := access.hiddenTrashError(clean); err != nil {
		return "", false, gofusefs.ToErrno(err)
	}
	if access.overlay.handles(clean) {
		return access.overlay.localPath(clean), true, 0
	}

	cachePath := access.cachePathFor(clean)
	if err := os.MkdirAll(filepath.Dir(cachePath), 0o755); err != nil {
		return "", false, gofusefs.ToErrno(err)
	}
	if flags&syscall.O_TRUNC == 0 {
		if _, _, err := access.ensureLocalFile(ctx, clean); err != nil && !create && flags&syscall.O_CREAT == 0 {
			return "", false, gofusefs.ToErrno(err)
		}
		return cachePath, false, 0
	}
	if _, err := access.statPath(ctx, clean); err != nil && !create && flags&syscall.O_CREAT == 0 {
		return "", false, gofusefs.ToErrno(err)
	}
	file, err := os.OpenFile(cachePath, os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return "", false, gofusefs.ToErrno(err)
	}
	_ = file.Close()
	return cachePath, false, 0
}

func linuxApplySetattr(localPath string, in *fuse.SetAttrIn) syscall.Errno {
	if size, ok := in.GetSize(); ok {
		if err := os.Truncate(localPath, int64(size)); err != nil {
			return gofusefs.ToErrno(err)
		}
	}
	if mode, ok := in.GetMode(); ok {
		if err := os.Chmod(localPath, os.FileMode(mode)); err != nil {
			return gofusefs.ToErrno(err)
		}
	}
	atime, hasAtime := in.GetATime()
	mtime, hasMtime := in.GetMTime()
	if hasAtime || hasMtime {
		current := time.Now()
		if !hasAtime {
			atime = current
		}
		if !hasMtime {
			mtime = current
		}
		if err := os.Chtimes(localPath, atime, mtime); err != nil {
			return gofusefs.ToErrno(err)
		}
	}
	return 0
}

func linuxFuseFlagsWritable(flags uint32) bool {
	switch flags & syscall.O_ACCMODE {
	case syscall.O_WRONLY, syscall.O_RDWR:
		return true
	default:
		return flags&syscall.O_TRUNC != 0
	}
}
