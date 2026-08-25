//go:build windows && cgo

// Windows Cloud Files helpers convert between sync-root paths and bucket object paths.
package mount

import (
	"path/filepath"
	"strconv"
	"strings"
	"time"

	s3ops "remote-storage/go/s3"
)

const (
	windowsCFProviderID               = "{5C3F6D4D-FAE6-4A0D-9E49-5A3E5EDC7E71}"
	windowsCFEventIgnoreTTL           = 3 * time.Second
	windowsCFDirectoryHarvestInterval = time.Second
	windowsCFDirectoryHarvestWindow   = 20 * time.Second
	windowsCFPlaceholderChunk         = 4 * 1024 * 1024
	windowsCFTransferAlignment        = 4 * 1024
)

type cloudPlaceholderInfo struct {
	RelativePath string
	FileSize     int64
	ModTime      time.Time
	FileID       string
	Fingerprint  string
	IsDirectory  bool
}

type cloudFilesFetchRequest struct {
	LocalPath string
	FileSize  int64
	Offset    int64
	Length    int64
	opInfo    uintptr
}

type cloudFilesTransferRange struct {
	Offset int64
	Length int64
}

type cloudFilesCallbacks struct {
	OnFetchData         func(req cloudFilesFetchRequest) error
	OnCancelFetch       func(req cloudFilesFetchRequest)
	OnFetchPlaceholders func(localPath string) error
	OnDeleteCompletion  func(localPath string)
	OnRenameCompletion  func(oldPath, newPath string)
}

func cloudFilesLocalPathToVirtual(syncRoot, localPath string) string {
	virtualPath, _ := cloudFilesLocalPathToVirtualChecked(syncRoot, localPath)
	return virtualPath
}

func cloudFilesLocalPathToVirtualChecked(syncRoot, localPath string) (string, bool) {
	root := filepath.Clean(strings.TrimSpace(syncRoot))
	current := filepath.Clean(strings.TrimSpace(localPath))
	if root == "" || current == "" {
		return "", false
	}
	if current == root {
		return "", true
	}
	relative, err := filepath.Rel(root, current)
	if err != nil {
		return "", false
	}
	if relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", false
	}
	return cleanVirtualPath(filepath.ToSlash(relative)), true
}

func cloudFilesVirtualPathToLocal(syncRoot, virtualPath string) string {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return filepath.Clean(syncRoot)
	}
	parts := strings.Split(clean, "/")
	return filepath.Join(append([]string{filepath.Clean(syncRoot)}, parts...)...)
}

func cloudFilesObjectModTime(info s3ops.ObjectInfo) time.Time {
	if info.LastModified == "" {
		return time.Now()
	}
	modTime, err := parseObjectLastModified(info.LastModified)
	if err != nil {
		return time.Now()
	}
	return modTime
}

func cloudFilesPlaceholderInfo(info s3ops.ObjectInfo) cloudPlaceholderInfo {
	return cloudPlaceholderInfo{
		RelativePath: strings.TrimSuffix(filepath.Base(filepath.Clean(info.Key)), "/"),
		FileSize:     info.Size,
		ModTime:      cloudFilesObjectModTime(info),
		FileID:       cloudFilesObjectIdentity(info),
		Fingerprint:  cloudFilesObjectFingerprint(info),
		IsDirectory:  info.IsDir,
	}
}

func cloudFilesMetadataPlaceholderInfo(
	item metadataMountObject,
	namespace string,
) cloudPlaceholderInfo {
	placeholder := cloudFilesPlaceholderInfo(item.info)
	if item.inode != 0 && namespace != "" {
		placeholder.FileID = "cloud-volume:v1:" + namespace + ":" + strconv.FormatUint(item.inode, 10)
	}
	return placeholder
}

// cloudFilesObjectIdentity remains the legacy fallback when no metadata OID is
// available; metadata-backed placeholders use a namespace-qualified OID while
// cloudFilesObjectFingerprint independently drives dehydration.
func cloudFilesObjectIdentity(info s3ops.ObjectInfo) string {
	identity := info.Key
	if etag := strings.TrimSpace(info.ETag); etag != "" {
		identity += "\x1f" + etag
	}
	return identity
}

func cloudFilesObjectFingerprint(info s3ops.ObjectInfo) string {
	return strings.Join([]string{
		cleanVirtualPath(info.Key), strings.TrimSpace(info.ETag), info.LastModified,
		strconv.FormatInt(info.Size, 10), strconv.FormatBool(info.IsDir),
	}, "\x1f")
}

func isWindowsLocalOnlyPath(virtualPath string) bool {
	clean := strings.ToLower(cleanVirtualPath(virtualPath))
	switch {
	case clean == "":
		return false
	case clean == ".cloud-volume":
		return true
	case strings.HasPrefix(clean, ".cloud-volume/"):
		return true
	case clean == "desktop.ini":
		return true
	case clean == "thumbs.db":
		return true
	case isEphemeralMountFilePath(clean):
		return true
	case strings.HasPrefix(clean, "$recycle.bin/"):
		return true
	case strings.HasPrefix(clean, "system volume information/"):
		return true
	default:
		return false
	}
}

func cloudFilesAlignedTransferRange(
	offset,
	length,
	fileSize int64,
) cloudFilesTransferRange {
	if length <= 0 {
		return cloudFilesTransferRange{Offset: offset, Length: 0}
	}
	if fileSize <= 0 {
		return cloudFilesTransferRange{Offset: offset, Length: length}
	}
	if offset < 0 {
		offset = 0
	}
	if offset > fileSize {
		offset = fileSize
	}

	end := offset + length
	if end > fileSize {
		end = fileSize
	}
	alignedOffset := offset - (offset % windowsCFTransferAlignment)
	alignedEnd := end
	if end < fileSize {
		remainder := end % windowsCFTransferAlignment
		if remainder != 0 {
			alignedEnd += windowsCFTransferAlignment - remainder
			if alignedEnd > fileSize {
				alignedEnd = fileSize
			}
		}
	}
	if alignedEnd < alignedOffset {
		alignedEnd = alignedOffset
	}
	return cloudFilesTransferRange{
		Offset: alignedOffset,
		Length: alignedEnd - alignedOffset,
	}
}
