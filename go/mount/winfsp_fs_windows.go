//go:build windows && cgo

// winfsp_fs implements cgofuse's FileSystemInterface on top of bucketAccess.
// Reads/writes reuse the same cache + writeback pipeline that powers the
// Linux FUSE mount and the WebDAV server, so a WinFsp volume is just another
// projection of the local-first bucket view.
package mount

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/winfsp/cgofuse/fuse"

	s3ops "remote-storage/go/s3"
)

// winFspBucketFS projects bucketAccess onto a WinFsp virtual volume.
type winFspBucketFS struct {
	fuse.FileSystemBase

	access      *bucketAccess
	volumeLabel string
	capacity    uint64
	used        uint64
	readOnly    bool
	openFiles   map[uint64]*winFspOpenFile
	openDirs    map[uint64]*winFspOpenDir
	nextHandle  uint64
	mu          sync.Mutex
	ctx         context.Context
	cancelCtx   context.CancelFunc
	wg          sync.WaitGroup
}

// winFspOpenFile tracks a cached local file backing an open WinFsp handle.
type winFspOpenFile struct {
	localPath   string
	virtualPath string
	oid         uint64
	file        *os.File
	writable    bool
	dirty       bool
	mu          sync.Mutex
}

// winFspOpenDir caches a directory listing between Opendir/Readdir/Releasedir.
type winFspOpenDir struct {
	virtualPath string
	entries     []winFspDirectoryEntry
	pos         int
	mu          sync.Mutex
}

func newWinFspBucketFS(
	access *bucketAccess,
	volumeLabel string,
	capacity uint64,
	used uint64,
	readOnly bool,
) *winFspBucketFS {
	ctx, cancel := context.WithCancel(context.Background())
	return &winFspBucketFS{
		access:      access,
		volumeLabel: volumeLabel,
		capacity:    capacity,
		used:        used,
		readOnly:    readOnly,
		openFiles:   make(map[uint64]*winFspOpenFile),
		openDirs:    make(map[uint64]*winFspOpenDir),
		ctx:         ctx,
		cancelCtx:   cancel,
	}
}

func (fs *winFspBucketFS) Init() {
}

func (fs *winFspBucketFS) Destroy() {
	fs.cancelCtx()
	fs.wg.Wait()
	fs.mu.Lock()
	for _, open := range fs.openFiles {
		if open.file != nil {
			_ = open.file.Close()
		}
	}
	fs.openFiles = make(map[uint64]*winFspOpenFile)
	fs.openDirs = make(map[uint64]*winFspOpenDir)
	fs.mu.Unlock()
}

// Statfs projects the resolved remote quota into Explorer's volume statistics.
func (fs *winFspBucketFS) Statfs(_ string, stat *fuse.Statfs_t) int {
	blocks := mountCapacityBlocks(fs.capacity, winFspBlockBytes)
	freeBytes := uint64(0)
	if fs.used < fs.capacity {
		freeBytes = fs.capacity - fs.used
	}
	freeBlocks := mountCapacityBlocks(freeBytes, winFspBlockBytes)
	stat.Bsize = winFspBlockBytes
	stat.Frsize = winFspBlockBytes
	stat.Blocks = blocks
	stat.Bfree = freeBlocks
	stat.Bavail = freeBlocks
	stat.Files = 1 << 32
	stat.Ffree = 1 << 32
	stat.Favail = 1 << 32
	stat.Namemax = 255
	return 0
}

func (fs *winFspBucketFS) Getattr(p string, stat *fuse.Stat_t, fh uint64) int {
	if p == "/" {
		fillWinFspDirStatWithInode(stat, 0o755, winFspVisibleOID(fs.ctx, fs.access, ""))
		return 0
	}
	if fh != 0 {
		fs.mu.Lock()
		open, ok := fs.openFiles[fh]
		fs.mu.Unlock()
		if ok && open.file != nil {
			if info, err := open.file.Stat(); err == nil {
				fillWinFspFileStatWithInode(stat, info, 0o644, open.oid)
				return 0
			}
		}
	}
	info, err := fs.access.statPath(fs.ctx, p)
	if err != nil {
		return -fuse.ENOENT
	}
	if info.IsDir {
		fillWinFspDirStatWithInode(stat, 0o755, winFspVisibleOID(fs.ctx, fs.access, p))
		return 0
	}
	fillWinFspFileStatFromObjectWithInode(stat, info, winFspVisibleOID(fs.ctx, fs.access, p))
	return 0
}

func (fs *winFspBucketFS) Mkdir(p string, mode uint32) int {
	if fs.readOnly {
		return -fuse.EROFS
	}
	if err := fs.access.createDirectory(fs.ctx, p); err != nil {
		return winFspErrno(err)
	}
	return 0
}

func (fs *winFspBucketFS) Unlink(p string) int {
	if fs.readOnly {
		return -fuse.EROFS
	}
	if err := fs.access.deletePath(fs.ctx, p, false); err != nil {
		return winFspErrno(err)
	}
	return 0
}

func (fs *winFspBucketFS) Rmdir(p string) int {
	if fs.readOnly {
		return -fuse.EROFS
	}
	if err := fs.access.deletePath(fs.ctx, p, true); err != nil {
		return winFspErrno(err)
	}
	return 0
}

func (fs *winFspBucketFS) Rename(oldp, newp string) int {
	if fs.readOnly {
		return -fuse.EROFS
	}
	info, err := fs.access.statPath(fs.ctx, oldp)
	if err != nil {
		return -fuse.ENOENT
	}
	if err := fs.access.renamePath(fs.ctx, oldp, newp, info.IsDir); err != nil {
		return winFspErrno(err)
	}
	return 0
}

func (fs *winFspBucketFS) Opendir(p string) (int, uint64) {
	handle := fs.allocHandle()
	items, err := fs.access.listDirectory(fs.ctx, p)
	if err != nil {
		fs.releaseHandle(handle)
		return winFspErrno(err), ^uint64(0)
	}
	sortObjectInfos(items)
	fs.mu.Lock()
	fs.openDirs[handle] = &winFspOpenDir{
		virtualPath: p,
		entries:     winFspDirectoryEntries(fs.ctx, fs.access, p, items),
	}
	fs.mu.Unlock()
	return 0, handle
}

func (fs *winFspBucketFS) Readdir(
	p string,
	fill func(name string, stat *fuse.Stat_t, ofst int64) bool,
	ofst int64,
	fh uint64,
) int {
	fs.mu.Lock()
	open, ok := fs.openDirs[fh]
	fs.mu.Unlock()
	if !ok {
		return -fuse.EBADF
	}
	open.mu.Lock()
	defer open.mu.Unlock()

	if ofst != 0 {
		// cgofuse issues a single Readdir with an increasing offset cursor in
		// some callers; serve the slice starting at ofst.
		open.pos = int(ofst)
	}
	if open.pos == 0 {
		if !fill(".", nil, 0) {
			return 0
		}
		if !fill("..", nil, 0) {
			return 0
		}
	}
	for open.pos < len(open.entries) {
		entry := open.entries[open.pos]
		name := baseName(entry.info.Key)
		if entry.info.IsDir {
			name = baseName(strings.TrimSuffix(entry.info.Key, "/"))
		}
		var stat fuse.Stat_t
		if entry.info.IsDir {
			fillWinFspDirStatWithInode(&stat, 0o755, entry.oid)
		} else {
			fillWinFspFileStatFromObjectWithInode(&stat, entry.info, entry.oid)
		}
		if !fill(name, &stat, int64(open.pos+1)) {
			open.pos++
			return 0
		}
		open.pos++
	}
	return 0
}

func (fs *winFspBucketFS) Releasedir(_ string, fh uint64) int {
	fs.releaseHandle(fh)
	return 0
}

func (fs *winFspBucketFS) Open(p string, flags int) (int, uint64) {
	writable := winFspFlagsWritable(flags)
	if fs.readOnly && writable {
		return -fuse.EROFS, ^uint64(0)
	}
	localPath, info, err := fs.access.ensureLocalFile(fs.ctx, p)
	if err != nil {
		if writable && flags&fuse.O_CREAT != 0 {
			cachePath := fs.access.cachePathFor(cleanVirtualPath(p))
			if err := os.MkdirAll(filepath.Dir(cachePath), 0o755); err != nil {
				return winFspErrno(err), ^uint64(0)
			}
			file, openErr := os.OpenFile(cachePath, os.O_CREATE|os.O_RDWR, 0o644)
			if openErr != nil {
				return winFspErrno(openErr), ^uint64(0)
			}
			return fs.registerOpen(p, cachePath, file, true, 0)
		}
		return winFspErrno(err), ^uint64(0)
	}
	openFlags := os.O_RDONLY
	if writable {
		openFlags = os.O_RDWR
	}
	file, err := os.OpenFile(localPath, openFlags, 0o644)
	if err != nil {
		return winFspErrno(err), ^uint64(0)
	}
	_ = info
	return fs.registerOpen(p, localPath, file, writable, winFspVisibleOID(fs.ctx, fs.access, p))
}

func (fs *winFspBucketFS) Create(p string, flags int, mode uint32) (int, uint64) {
	if fs.readOnly {
		return -fuse.EROFS, ^uint64(0)
	}
	clean := cleanVirtualPath(p)
	if err := fs.access.hiddenTrashError(clean); err != nil {
		return winFspErrno(err), ^uint64(0)
	}
	cachePath := fs.access.cachePathFor(clean)
	if err := os.MkdirAll(filepath.Dir(cachePath), 0o755); err != nil {
		return winFspErrno(err), ^uint64(0)
	}
	file, err := os.OpenFile(cachePath, os.O_CREATE|os.O_RDWR|os.O_TRUNC, os.FileMode(mode&0o777))
	if err != nil {
		return winFspErrno(err), ^uint64(0)
	}
	return fs.registerOpen(p, cachePath, file, true, 0)
}

func (fs *winFspBucketFS) Read(p string, buff []byte, ofst int64, fh uint64) int {
	fs.mu.Lock()
	open, ok := fs.openFiles[fh]
	fs.mu.Unlock()
	if !ok || open.file == nil {
		return -fuse.EBADF
	}
	open.mu.Lock()
	defer open.mu.Unlock()
	n, err := open.file.ReadAt(buff, ofst)
	if err != nil && !errors.Is(err, io.EOF) {
		return winFspErrno(err)
	}
	return n
}

func (fs *winFspBucketFS) Write(p string, buff []byte, ofst int64, fh uint64) int {
	if fs.readOnly {
		return -fuse.EROFS
	}
	fs.mu.Lock()
	open, ok := fs.openFiles[fh]
	fs.mu.Unlock()
	if !ok || open.file == nil {
		return -fuse.EBADF
	}
	open.mu.Lock()
	defer open.mu.Unlock()
	n, err := open.file.WriteAt(buff, ofst)
	if err != nil {
		return winFspErrno(err)
	}
	open.dirty = true
	return n
}

func (fs *winFspBucketFS) Truncate(p string, size int64, fh uint64) int {
	if fs.readOnly {
		return -fuse.EROFS
	}
	if fh == 0 {
		return -fuse.EBADF
	}
	fs.mu.Lock()
	open, ok := fs.openFiles[fh]
	fs.mu.Unlock()
	if !ok || open.file == nil {
		return -fuse.EBADF
	}
	open.mu.Lock()
	defer open.mu.Unlock()
	if err := open.file.Truncate(size); err != nil {
		return winFspErrno(err)
	}
	open.dirty = true
	return 0
}

func (fs *winFspBucketFS) Flush(_ string, fh uint64) int {
	if fh == 0 {
		return 0
	}
	fs.mu.Lock()
	open, ok := fs.openFiles[fh]
	fs.mu.Unlock()
	if !ok || open.file == nil {
		return 0
	}
	open.mu.Lock()
	defer open.mu.Unlock()
	if open.writable && open.dirty {
		_ = open.file.Sync()
	}
	return 0
}

func (fs *winFspBucketFS) Release(p string, fh uint64) int {
	fs.mu.Lock()
	open, ok := fs.openFiles[fh]
	if ok {
		delete(fs.openFiles, fh)
	}
	fs.mu.Unlock()
	if !ok {
		return 0
	}
	open.mu.Lock()
	defer open.mu.Unlock()
	stageErr := error(nil)
	if open.writable && open.dirty {
		if stat, err := open.file.Stat(); err == nil {
			stageErr = fs.access.stageLocalWrite(open.virtualPath, open.localPath, stat.Size())
		}
		open.dirty = false
	}
	if open.file != nil {
		_ = open.file.Close()
	}
	if stageErr != nil {
		return winFspErrno(stageErr)
	}
	return 0
}

// registerOpen opens a tracking slot for a freshly opened local file.
func (fs *winFspBucketFS) registerOpen(
	virtualPath, localPath string,
	file *os.File,
	writable bool,
	oid uint64,
) (int, uint64) {
	handle := fs.allocHandle()
	fs.mu.Lock()
	fs.openFiles[handle] = &winFspOpenFile{
		localPath:   localPath,
		virtualPath: cleanVirtualPath(virtualPath),
		oid:         oid,
		file:        file,
		writable:    writable,
	}
	fs.mu.Unlock()
	return 0, handle
}

func (fs *winFspBucketFS) allocHandle() uint64 {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	fs.nextHandle++
	return fs.nextHandle
}

func (fs *winFspBucketFS) releaseHandle(handle uint64) {
	fs.mu.Lock()
	delete(fs.openFiles, handle)
	delete(fs.openDirs, handle)
	fs.mu.Unlock()
}
