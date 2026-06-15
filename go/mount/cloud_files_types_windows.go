//go:build windows && cgo

// Windows Cloud Files helpers convert between sync-root paths and bucket object paths.
package mount

import (
	"path/filepath"
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
	root := filepath.Clean(strings.TrimSpace(syncRoot))
	current := filepath.Clean(strings.TrimSpace(localPath))
	if root == "" || current == "" {
		return ""
	}
	if current == root {
		return ""
	}
	relative, err := filepath.Rel(root, current)
	if err != nil {
		return ""
	}
	return cleanVirtualPath(filepath.ToSlash(relative))
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
	modTime, err := time.ParseInLocation("2006-01-02 15:04:05", info.LastModified, time.Local)
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
		FileID:       info.Key,
		IsDirectory:  info.IsDir,
	}
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
