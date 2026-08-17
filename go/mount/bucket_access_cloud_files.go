//go:build windows

// Cloud Files reads use the remote-only bucket view so placeholders never mirror local drafts.
package mount

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"

	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) listRemoteDirectory(
	ctx context.Context,
	virtualPrefix string,
) ([]s3ops.ObjectInfo, error) {
	if a.metadataService() != nil {
		items, err := a.metadataDirectory(ctx, virtualPrefix, false)
		if err != nil {
			return nil, err
		}
		return metadataObjectInfos(items), nil
	}
	return a.fetchDirectory(ctx, virtualPrefix)
}

func (a *bucketAccess) statRemotePath(
	ctx context.Context,
	virtualPath string,
) (s3ops.ObjectInfo, error) {
	if a.metadataService() != nil {
		item, err := a.metadataStat(ctx, virtualPath)
		if err != nil {
			return s3ops.ObjectInfo{}, err
		}
		return item.info, nil
	}
	return a.fetchStat(ctx, virtualPath)
}

func (a *bucketAccess) readCachedRange(
	ctx context.Context,
	virtualPath string,
	offset,
	length int64,
) ([]byte, error) {
	if length <= 0 {
		return nil, nil
	}
	clean := cleanVirtualPath(virtualPath)
	if item, ok := a.cache.localFile(clean); ok && a.isSyncRootLocalPath(item.localPath) {
		// Cloud Files hydration must not read back from the sync-root placeholder
		// itself, or the reader will recurse into the same CFAPI callback chain.
		a.cache.clearLocalFileMarker(clean)
	}
	// If cached metadata already describes the object and the downloaded cache
	// file is present, hydrate from that copy instead of forcing a remote stat
	// round-trip for bytes that are already local.
	if info, ok := a.cache.cachedObject(clean); ok && !info.IsDir {
		cachePath := a.cachePathFor(clean)
		if isUsableLocalFile(cachePath, info.Size) {
			return readLocalRange(cachePath, info, offset, length)
		}
	}

	localPath, info, err := a.ensureLocalFile(ctx, virtualPath)
	if err != nil {
		return nil, err
	}
	return readLocalRange(localPath, info, offset, length)
}

func readLocalRange(localPath string, info s3ops.ObjectInfo, offset, length int64) ([]byte, error) {
	file, err := os.Open(localPath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	if offset >= info.Size {
		return nil, nil
	}
	remaining := info.Size - offset
	if remaining < length {
		length = remaining
	}

	buffer := make([]byte, length)
	n, err := file.ReadAt(buffer, offset)
	switch {
	case err == nil:
		return buffer[:n], nil
	case err == io.EOF:
		return buffer[:n], nil
	default:
		return nil, err
	}
}

func (a *bucketAccess) isSyncRootLocalPath(localPath string) bool {
	if a == nil || strings.TrimSpace(localPath) == "" {
		return false
	}
	rootPath, err := windowsCloudFilesRootPath()
	if err != nil {
		return false
	}
	cleanLocal := filepath.Clean(localPath)
	cleanRoot := filepath.Clean(rootPath)
	return cleanLocal == cleanRoot ||
		strings.HasPrefix(cleanLocal, cleanRoot+string(os.PathSeparator))
}
