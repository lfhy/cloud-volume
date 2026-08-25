// Local overlay keeps macOS volume-private dot paths writable without syncing them to S3.
package mount

import (
	"context"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	s3ops "remote-storage/go/s3"
)

type localOverlayEntry struct {
	name  string
	isDir bool
	mode  os.FileMode
}

type localMountOverlay struct {
	root     string
	entries  map[string]localOverlayEntry
	trashUID string
}

func newLocalMountOverlay(root string) (*localMountOverlay, error) {
	overlay := &localMountOverlay{
		root: root,
		entries: map[string]localOverlayEntry{
			".TemporaryItems":                     {name: ".TemporaryItems", isDir: true, mode: 0o777 | fs.ModeSticky},
			".fseventsd":                          {name: ".fseventsd", isDir: true, mode: 0o755},
			".metadata_never_index":               {name: ".metadata_never_index", isDir: false, mode: 0o644},
			".metadata_never_index_unless_rootfs": {name: ".metadata_never_index_unless_rootfs", isDir: false, mode: 0o644},
			".ql_disablecache":                    {name: ".ql_disablecache", isDir: false, mode: 0o644},
			".ql_disablethumbnails":               {name: ".ql_disablethumbnails", isDir: false, mode: 0o644},
		},
		trashUID: strconv.Itoa(os.Getuid()),
	}
	if err := overlay.ensureSeed(); err != nil {
		return nil, err
	}
	return overlay, nil
}

func (o *localMountOverlay) ensureSeed() error {
	if err := os.MkdirAll(o.root, 0o755); err != nil {
		return err
	}
	for _, entry := range o.entries {
		target := filepath.Join(o.root, entry.name)
		if entry.isDir {
			if err := os.MkdirAll(target, entry.mode); err != nil {
				return err
			}
			if err := os.Chmod(target, entry.mode); err != nil {
				return err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		file, err := os.OpenFile(target, os.O_CREATE, entry.mode)
		if err != nil {
			return err
		}
		if closeErr := file.Close(); closeErr != nil {
			return closeErr
		}
		if err := os.Chmod(target, entry.mode); err != nil {
			return err
		}
	}
	noLogPath := filepath.Join(o.root, ".fseventsd", "no_log")
	file, err := os.OpenFile(noLogPath, os.O_CREATE, 0o644)
	if err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return nil
}

func (o *localMountOverlay) handles(virtualPath string) bool {
	segments := splitVirtualPath(virtualPath)
	if len(segments) == 0 {
		return false
	}
	for index, segment := range segments {
		if index == 0 {
			if _, ok := o.entries[segment]; ok {
				return true
			}
		}
		if isOverlayTransientSegment(segment) {
			return true
		}
	}
	if isFinderCopyTempPath(virtualPath) {
		return true
	}
	return isLocalMetadataPath(virtualPath)
}

func (o *localMountOverlay) isTrashPath(virtualPath string) bool {
	head := topLevelSegment(virtualPath)
	return head == ".Trash" || head == ".Trash-"+o.trashUID || head == ".Trashes"
}

func (o *localMountOverlay) listRootEntries() ([]s3ops.ObjectInfo, error) {
	return o.listVisibleEntries("")
}

func (o *localMountOverlay) listDirectory(virtualPrefix string) ([]s3ops.ObjectInfo, error) {
	return o.listVisibleEntries(virtualPrefix)
}

func (o *localMountOverlay) listVisibleEntries(virtualPrefix string) ([]s3ops.ObjectInfo, error) {
	if err := o.ensureSeed(); err != nil {
		return nil, err
	}
	cleanPrefix := cleanVirtualPath(virtualPrefix)
	localPath := o.localPath(virtualPrefix)
	entries, err := os.ReadDir(localPath)
	if err != nil {
		return nil, err
	}
	items := make([]s3ops.ObjectInfo, 0, len(entries))
	for _, entry := range entries {
		info, infoErr := entry.Info()
		if infoErr != nil {
			return nil, infoErr
		}
		key := entry.Name()
		if cleanPrefix != "" {
			key = cleanPrefix + "/" + key
		}
		if !o.handles(key) {
			continue
		}
		items = append(items, objectInfoFromLocalStat(key, info))
	}
	sort.Slice(items, func(i, j int) bool { return items[i].Key < items[j].Key })
	return items, nil
}

func (o *localMountOverlay) statObject(virtualPath string) (s3ops.ObjectInfo, error) {
	info, err := o.statPath(virtualPath)
	if err != nil {
		return s3ops.ObjectInfo{}, err
	}
	return objectInfoFromLocalStat(virtualPath, info), nil
}

func (o *localMountOverlay) statPath(virtualPath string) (os.FileInfo, error) {
	return os.Stat(o.localPath(virtualPath))
}

func (o *localMountOverlay) openFile(
	_ context.Context,
	virtualPath string,
	flag int,
	perm os.FileMode,
) (*os.File, error) {
	localPath := o.localPath(virtualPath)
	if flag&os.O_CREATE != 0 {
		if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
			return nil, err
		}
	}
	if perm.Perm() == 0 {
		perm = 0o644
	}
	return os.OpenFile(localPath, flag, perm)
}

func (o *localMountOverlay) mkdir(virtualPath string, mode os.FileMode) error {
	if mode.Perm() == 0 {
		mode = 0o755
	}
	return os.MkdirAll(o.localPath(virtualPath), mode.Perm())
}

func (o *localMountOverlay) removeAll(virtualPath string) error {
	return os.RemoveAll(o.localPath(virtualPath))
}

func (o *localMountOverlay) rename(oldVirtualPath, newVirtualPath string) error {
	targetPath := o.localPath(newVirtualPath)
	if err := os.MkdirAll(filepath.Dir(targetPath), 0o755); err != nil {
		return err
	}
	return os.Rename(o.localPath(oldVirtualPath), targetPath)
}

func (o *localMountOverlay) localPath(virtualPath string) string {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return o.root
	}
	return filepath.Join(append([]string{o.root}, splitVirtualPath(clean)...)...)
}

func objectInfoFromLocalStat(virtualPath string, info os.FileInfo) s3ops.ObjectInfo {
	key := cleanVirtualPath(virtualPath)
	if info.IsDir() {
		key = ensureDirSuffix(key)
	}
	return s3ops.ObjectInfo{
		Key:          key,
		Size:         info.Size(),
		LastModified: info.ModTime().Format("2006-01-02 15:04:05"),
		IsDir:        info.IsDir(),
	}
}

func topLevelSegment(virtualPath string) string {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return ""
	}
	index := strings.Index(clean, "/")
	if index < 0 {
		return clean
	}
	return clean[:index]
}

func isOverlayTransientSegment(segment string) bool {
	switch {
	case strings.HasPrefix(segment, ".AU."):
		return true
	case segment == ".ArchiveServiceTemp":
		return true
	case strings.HasPrefix(segment, ".ArchiveServiceTemp."):
		return true
	default:
		return false
	}
}

type localWebDAVFile struct {
	file *os.File
}

func newLocalWebDAVFile(file *os.File) *localWebDAVFile {
	return &localWebDAVFile{file: file}
}

func (f *localWebDAVFile) Close() error {
	return f.file.Close()
}

func (f *localWebDAVFile) Read(p []byte) (int, error) {
	return f.file.Read(p)
}

func (f *localWebDAVFile) Seek(offset int64, whence int) (int64, error) {
	return f.file.Seek(offset, whence)
}

func (f *localWebDAVFile) Readdir(count int) ([]os.FileInfo, error) {
	return f.file.Readdir(count)
}

func (f *localWebDAVFile) Stat() (os.FileInfo, error) {
	return f.file.Stat()
}

func (f *localWebDAVFile) Write(p []byte) (int, error) {
	return f.file.Write(p)
}

type overlayRootFile struct {
	infos []os.FileInfo
	pos   int
}

func newOverlayRootFile(overlayItems []s3ops.ObjectInfo) *overlayRootFile {
	infos := make([]os.FileInfo, 0, len(overlayItems))
	for _, item := range overlayItems {
		infos = append(infos, fileInfoFromObject(item))
	}
	sort.Slice(infos, func(i, j int) bool { return infos[i].Name() < infos[j].Name() })
	return &overlayRootFile{infos: infos}
}

func (f *overlayRootFile) Close() error { return nil }

func (f *overlayRootFile) Read([]byte) (int, error) { return 0, os.ErrInvalid }

func (f *overlayRootFile) Seek(int64, int) (int64, error) { return 0, os.ErrInvalid }

func (f *overlayRootFile) Readdir(count int) ([]os.FileInfo, error) {
	if f.pos >= len(f.infos) && count > 0 {
		return nil, io.EOF
	}
	if count <= 0 {
		return f.infos, nil
	}
	end := f.pos + count
	if end > len(f.infos) {
		end = len(f.infos)
	}
	out := f.infos[f.pos:end]
	f.pos = end
	if len(out) == 0 {
		return nil, io.EOF
	}
	return out, nil
}

func (f *overlayRootFile) Stat() (os.FileInfo, error) {
	return virtualFileInfo{
		name:    "/",
		size:    0,
		mode:    fs.ModeDir | 0o755,
		modTime: time.Now(),
		isDir:   true,
	}, nil
}

func (f *overlayRootFile) Write([]byte) (int, error) { return 0, os.ErrInvalid }
