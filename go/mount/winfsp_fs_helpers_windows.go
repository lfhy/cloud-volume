//go:build windows && cgo

// WinFsp FS helpers keep Stat/error mapping out of the main FS method file so
// both stay under the project line limit.
package mount

import (
	"os"
	"time"

	"github.com/winfsp/cgofuse/fuse"

	s3ops "remote-storage/go/s3"
)

func winFspFlagsWritable(flags int) bool {
	switch flags & fuse.O_ACCMODE {
	case fuse.O_WRONLY, fuse.O_RDWR:
		return true
	default:
		return flags&fuse.O_TRUNC != 0
	}
}

func fillWinFspDirStat(stat *fuse.Stat_t, mode uint32) {
	now := time.Now()
	stat.Mode = fuse.S_IFDIR | mode
	stat.Nlink = 2
	stat.Size = 0
	stat.Blksize = int64(winFspBlockBytes)
	stat.Birthtim = fuse.Timespec{Sec: now.Unix()}
	stat.Atim = stat.Birthtim
	stat.Mtim = stat.Birthtim
	stat.Ctim = stat.Birthtim
}

func fillWinFspDirStatWithInode(stat *fuse.Stat_t, mode uint32, inode uint64) {
	fillWinFspDirStat(stat, mode)
	stat.Ino = inode
}

func fillWinFspFileStat(stat *fuse.Stat_t, info os.FileInfo, mode uint32) {
	now := time.Now()
	stat.Mode = fuse.S_IFREG | mode
	stat.Nlink = 1
	stat.Size = info.Size()
	stat.Blksize = int64(winFspBlockBytes)
	if stat.Blksize > 0 {
		stat.Blocks = (info.Size() + int64(stat.Blksize) - 1) / int64(stat.Blksize)
	}
	mtime := info.ModTime()
	stat.Birthtim = fuse.Timespec{Sec: now.Unix()}
	stat.Atim = fuse.Timespec{Sec: mtime.Unix()}
	stat.Mtim = stat.Atim
	stat.Ctim = stat.Atim
}

func fillWinFspFileStatWithInode(
	stat *fuse.Stat_t,
	info os.FileInfo,
	mode uint32,
	inode uint64,
) {
	fillWinFspFileStat(stat, info, mode)
	stat.Ino = inode
}

func fillWinFspFileStatFromObject(stat *fuse.Stat_t, info s3ops.ObjectInfo) {
	mode := uint32(0o644)
	fillWinFspFileStatRaw(stat, info.Size, mode, info.LastModified)
}

func fillWinFspFileStatFromObjectWithInode(
	stat *fuse.Stat_t,
	info s3ops.ObjectInfo,
	inode uint64,
) {
	fillWinFspFileStatFromObject(stat, info)
	stat.Ino = inode
}

func fillWinFspFileStatRaw(stat *fuse.Stat_t, size int64, mode uint32, lastModified string) {
	mtime := time.Now()
	if parsed, err := parseObjectLastModified(lastModified); err == nil {
		mtime = parsed
	}
	stat.Mode = fuse.S_IFREG | mode
	stat.Nlink = 1
	stat.Size = size
	stat.Blksize = int64(winFspBlockBytes)
	if stat.Blksize > 0 {
		stat.Blocks = (size + int64(stat.Blksize) - 1) / int64(stat.Blksize)
	}
	stat.Birthtim = fuse.Timespec{Sec: mtime.Unix()}
	stat.Atim = stat.Birthtim
	stat.Mtim = stat.Birthtim
	stat.Ctim = stat.Birthtim
}

func winFspErrno(err error) int {
	if err == nil {
		return 0
	}
	if os.IsNotExist(err) {
		return -fuse.ENOENT
	}
	return -fuse.EIO
}
