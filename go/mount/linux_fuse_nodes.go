//go:build linux

// Linux FUSE nodes project the existing cached bucket-access model into the kernel VFS.
package mount

import (
	"context"
	"hash/fnv"
	"os"
	"path"
	"syscall"
	"time"

	gofusefs "github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"
)

type linuxFuseNode struct {
	gofusefs.Inode
	access *bucketAccess
	dir    bool
	oid    uint64
}

var _ gofusefs.NodeLookuper = (*linuxFuseNode)(nil)
var _ gofusefs.NodeReaddirer = (*linuxFuseNode)(nil)
var _ gofusefs.NodeGetattrer = (*linuxFuseNode)(nil)
var _ gofusefs.NodeStatfser = (*linuxFuseNode)(nil)
var _ gofusefs.NodeSetattrer = (*linuxFuseNode)(nil)
var _ gofusefs.NodeOpener = (*linuxFuseNode)(nil)
var _ gofusefs.NodeCreater = (*linuxFuseNode)(nil)
var _ gofusefs.NodeMkdirer = (*linuxFuseNode)(nil)
var _ gofusefs.NodeUnlinker = (*linuxFuseNode)(nil)
var _ gofusefs.NodeRmdirer = (*linuxFuseNode)(nil)
var _ gofusefs.NodeRenamer = (*linuxFuseNode)(nil)

func newLinuxFuseNode(access *bucketAccess, dir bool) *linuxFuseNode {
	return &linuxFuseNode{access: access, dir: dir}
}

func newLinuxFuseNodeWithOID(access *bucketAccess, dir bool, oid uint64) *linuxFuseNode {
	return &linuxFuseNode{access: access, dir: dir, oid: oid}
}

func (n *linuxFuseNode) Lookup(
	ctx context.Context,
	name string,
	out *fuse.EntryOut,
) (*gofusefs.Inode, syscall.Errno) {
	virtualPath := n.childVirtualPath(name)
	info, err := n.access.statPath(ctx, virtualPath)
	if err != nil {
		return nil, gofusefs.ToErrno(err)
	}
	oid, _ := n.access.metadataOIDForVisiblePath(ctx, virtualPath)
	node := newLinuxFuseNodeWithOID(n.access, info.IsDir, oid)
	fillLinuxFuseEntry(out, fileInfoFromObject(info))
	return n.NewInode(ctx, node, linuxFuseStableAttrWithOID(virtualPath, info.IsDir, oid)), 0
}

func (n *linuxFuseNode) Readdir(ctx context.Context) (gofusefs.DirStream, syscall.Errno) {
	items, err := n.access.listDirectory(ctx, n.virtualPath())
	if err != nil {
		return nil, gofusefs.ToErrno(err)
	}
	sortObjectInfos(items)
	oids := n.access.metadataOIDMap(ctx, n.virtualPath())

	entries := make([]fuse.DirEntry, 0, len(items))
	for _, item := range items {
		oid := oids[cleanVirtualPath(item.Key)]
		stable := linuxFuseStableAttrWithOID(item.Key, item.IsDir, oid)
		entries = append(entries, fuse.DirEntry{
			Name: baseName(item.Key),
			Ino:  stable.Ino,
			Mode: stable.Mode,
		})
	}
	return gofusefs.NewListDirStream(entries), 0
}

func (n *linuxFuseNode) Getattr(
	ctx context.Context,
	f gofusefs.FileHandle,
	out *fuse.AttrOut,
) syscall.Errno {
	if file, ok := f.(*linuxFuseFileHandle); ok {
		return file.Getattr(ctx, out)
	}
	if n.IsRoot() {
		fillLinuxFuseRootAttr(out)
		out.Attr.Ino = rootLinuxFuseInode(n.access)
		return 0
	}

	virtualPath := n.virtualPath()
	if item, ok := n.access.cache.localFile(virtualPath); ok {
		if info, err := os.Stat(item.localPath); err == nil {
			fillLinuxFuseLocalAttr(&out.Attr, info, false)
			out.Attr.Ino = n.stableInode(virtualPath, false)
			return 0
		}
	}

	info, err := n.access.statPath(ctx, virtualPath)
	if err != nil {
		return gofusefs.ToErrno(err)
	}
	fillLinuxFuseLocalAttr(&out.Attr, fileInfoFromObject(info), info.IsDir)
	out.Attr.Ino = n.stableInode(virtualPath, info.IsDir)
	return 0
}

// Statfs projects the bucket's display quota into Linux filesystem statistics.
func (n *linuxFuseNode) Statfs(
	_ context.Context,
	out *fuse.StatfsOut,
) syscall.Errno {
	capacityBytes := resolvedMountCapacityBytes(
		n.access.config,
		n.access.bucket,
		0,
	)
	if capacityBytes == 0 {
		return 0
	}
	const blockBytes uint64 = 4096
	blocks := mountCapacityBlocks(capacityBytes, blockBytes)
	out.Bsize = uint32(blockBytes)
	out.Frsize = uint32(blockBytes)
	out.Blocks = blocks
	out.Bfree = blocks
	out.Bavail = blocks
	out.Files = 1 << 32
	out.Ffree = 1 << 32
	out.NameLen = 255
	return 0
}

func (n *linuxFuseNode) Setattr(
	ctx context.Context,
	f gofusefs.FileHandle,
	in *fuse.SetAttrIn,
	out *fuse.AttrOut,
) syscall.Errno {
	if file, ok := f.(*linuxFuseFileHandle); ok {
		return file.Setattr(ctx, in, out)
	}
	if n.dir || n.IsRoot() {
		return n.Getattr(ctx, nil, out)
	}
	if n.access.readOnly {
		return syscall.EROFS
	}
	virtualPath := n.virtualPath()
	localPath, overlayOnly, errno := linuxEnsureWritableLocalPath(ctx, n.access, virtualPath, 0, false)
	if errno != 0 {
		return errno
	}
	if errno := linuxApplySetattr(localPath, in); errno != 0 {
		return errno
	}
	if !overlayOnly {
		if err := n.access.stageLocalWrite(virtualPath, localPath, fileSize(localPath)); err != nil {
			return gofusefs.ToErrno(err)
		}
	}
	info, err := os.Stat(localPath)
	if err != nil {
		return gofusefs.ToErrno(err)
	}
	fillLinuxFuseLocalAttr(&out.Attr, info, false)
	return 0
}

func (n *linuxFuseNode) Open(
	ctx context.Context,
	flags uint32,
) (gofusefs.FileHandle, uint32, syscall.Errno) {
	if n.dir {
		return nil, 0, syscall.EISDIR
	}
	handle, errno := newLinuxFuseFileHandle(ctx, n.access, n.virtualPath(), flags, false, 0o644)
	return handle, fuse.FOPEN_KEEP_CACHE, errno
}

func (n *linuxFuseNode) Create(
	ctx context.Context,
	name string,
	flags uint32,
	mode uint32,
	out *fuse.EntryOut,
) (*gofusefs.Inode, gofusefs.FileHandle, uint32, syscall.Errno) {
	virtualPath := n.childVirtualPath(name)
	handle, errno := newLinuxFuseFileHandle(ctx, n.access, virtualPath, flags|syscall.O_CREAT, true, os.FileMode(mode))
	if errno != 0 {
		return nil, nil, 0, errno
	}
	info, statErr := handle.file.Stat()
	if statErr != nil {
		_ = handle.Release(ctx)
		return nil, nil, 0, gofusefs.ToErrno(statErr)
	}
	fillLinuxFuseLocalAttr(&out.Attr, info, false)
	child := n.NewInode(ctx, newLinuxFuseNode(n.access, false), linuxFuseStableAttr(virtualPath, false))
	return child, handle, fuse.FOPEN_KEEP_CACHE, 0
}

func (n *linuxFuseNode) Mkdir(
	ctx context.Context,
	name string,
	mode uint32,
	out *fuse.EntryOut,
) (*gofusefs.Inode, syscall.Errno) {
	virtualPath := n.childVirtualPath(name)
	if err := n.access.createDirectory(ctx, virtualPath); err != nil {
		return nil, gofusefs.ToErrno(err)
	}
	child := n.NewInode(ctx, newLinuxFuseNode(n.access, true), linuxFuseStableAttr(virtualPath, true))
	fillLinuxFuseEntry(out, fileInfoFromObject(objectInfoFromLocalStat(virtualPath, dirInfo(mode))))
	return child, 0
}

func (n *linuxFuseNode) Unlink(ctx context.Context, name string) syscall.Errno {
	return gofusefs.ToErrno(n.access.deletePath(ctx, n.childVirtualPath(name), false))
}

func (n *linuxFuseNode) Rmdir(ctx context.Context, name string) syscall.Errno {
	return gofusefs.ToErrno(n.access.deletePath(ctx, n.childVirtualPath(name), true))
}

func (n *linuxFuseNode) Rename(
	ctx context.Context,
	name string,
	newParent gofusefs.InodeEmbedder,
	newName string,
	flags uint32,
) syscall.Errno {
	if flags != 0 {
		return syscall.ENOTSUP
	}
	targetParent, ok := newParent.(*linuxFuseNode)
	if !ok {
		return syscall.EXDEV
	}
	oldPath := n.childVirtualPath(name)
	info, err := n.access.statPath(ctx, oldPath)
	if err != nil {
		return gofusefs.ToErrno(err)
	}
	newPath := targetParent.childVirtualPath(newName)
	return gofusefs.ToErrno(n.access.renamePath(ctx, oldPath, newPath, info.IsDir))
}

func (n *linuxFuseNode) virtualPath() string {
	return cleanVirtualPath(n.Path(n.Root()))
}

func (n *linuxFuseNode) childVirtualPath(name string) string {
	return cleanVirtualPath(path.Join("/", n.virtualPath(), name))
}

func linuxFuseStableAttr(virtualPath string, isDir bool) gofusefs.StableAttr {
	return linuxFuseStableAttrWithOID(virtualPath, isDir, 0)
}

func linuxFuseStableAttrWithOID(virtualPath string, isDir bool, oid uint64) gofusefs.StableAttr {
	mode := uint32(syscall.S_IFREG)
	if isDir {
		mode = syscall.S_IFDIR
	}
	if oid == 0 {
		oid = linuxFuseInodeNumber(virtualPath, isDir)
	}
	return gofusefs.StableAttr{
		Mode: mode,
		Ino:  oid,
	}
}

func (n *linuxFuseNode) stableInode(virtualPath string, isDir bool) uint64 {
	if n != nil && n.oid != 0 {
		return n.oid
	}
	if oid, ok := n.access.metadataOIDForVisiblePath(context.Background(), virtualPath); ok {
		return oid
	}
	return linuxFuseInodeNumber(virtualPath, isDir)
}

func rootLinuxFuseInode(access *bucketAccess) uint64 {
	if oid, ok := access.metadataOIDForVisiblePath(context.Background(), ""); ok {
		return oid
	}
	return linuxFuseInodeNumber("", true)
}

func linuxFuseInodeNumber(virtualPath string, isDir bool) uint64 {
	value := cleanVirtualPath(virtualPath)
	if isDir {
		value += "/"
	}
	return stringHash64(value)
}

func stringHash64(value string) uint64 {
	hasher := fnv.New64a()
	_, _ = hasher.Write([]byte(value))
	return hasher.Sum64()
}

func fillLinuxFuseEntry(out *fuse.EntryOut, info os.FileInfo) {
	fillLinuxFuseLocalAttr(&out.Attr, info, info.IsDir())
}

func fillLinuxFuseRootAttr(out *fuse.AttrOut) {
	now := time.Now()
	fillLinuxFuseTimes(&out.Attr, now)
	fillLinuxFuseOwner(&out.Attr)
	out.Mode = 0o755
	out.Nlink = 2
	out.Size = 4096
	out.Blksize = 4096
	out.Blocks = 8
}

func fillLinuxFuseLocalAttr(out *fuse.Attr, info os.FileInfo, isDir bool) {
	modTime := info.ModTime()
	fillLinuxFuseTimes(out, modTime)
	fillLinuxFuseOwner(out)
	out.Mode = 0o644
	out.Nlink = 1
	out.Size = uint64(info.Size())
	if isDir {
		out.Mode = 0o755
		out.Nlink = 2
		if out.Size == 0 {
			out.Size = 4096
		}
	}
	out.Blksize = 4096
	out.Blocks = (out.Size + 511) / 512
}

// fillLinuxFuseOwner makes default_permissions evaluate mounted entries as the
// desktop user rather than as root, regardless of which client wrote them.
func fillLinuxFuseOwner(out *fuse.Attr) {
	out.Uid = uint32(os.Getuid())
	out.Gid = uint32(os.Getgid())
}

func fillLinuxFuseTimes(out *fuse.Attr, value time.Time) {
	out.Atime = uint64(value.Unix())
	out.Mtime = uint64(value.Unix())
	out.Ctime = uint64(value.Unix())
	out.Atimensec = uint32(value.Nanosecond())
	out.Mtimensec = uint32(value.Nanosecond())
	out.Ctimensec = uint32(value.Nanosecond())
}

type dirInfo uint32

func (m dirInfo) Name() string       { return "" }
func (m dirInfo) Size() int64        { return 0 }
func (m dirInfo) Mode() os.FileMode  { return os.FileMode(m) | os.ModeDir }
func (m dirInfo) ModTime() time.Time { return time.Now() }
func (m dirInfo) IsDir() bool        { return true }
func (m dirInfo) Sys() any           { return nil }
