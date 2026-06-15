// Bucket remote helpers handle timeout-bound backend fetches and key translation.
package mount

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"

	s3ops "remote-storage/go/s3"
)

const prefetchDirectoryPageSize int32 = 20
const maxPrefetchChildrenPerDirectory = 8

func (a *bucketAccess) fetchDirectory(
	ctx context.Context,
	virtualPrefix string,
) ([]s3ops.ObjectInfo, error) {
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	items, err := a.listAllRemoteObjects(timeoutCtx, a.remotePrefix(virtualPrefix))
	if err != nil {
		return nil, err
	}

	rewritten := make([]s3ops.ObjectInfo, 0, len(items))
	for _, item := range items {
		item, ok := a.rewriteRemoteObject(item)
		if !ok {
			continue
		}
		rewritten = append(rewritten, item)
		a.cache.storeObject(strings.TrimSuffix(item.Key, "/"), item)
	}
	return a.filterTrashItems(rewritten), nil
}

func (a *bucketAccess) fetchStat(
	ctx context.Context,
	virtualPath string,
) (s3ops.ObjectInfo, error) {
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	fileInfo, err := a.backend.HeadObject(timeoutCtx, a.bucket, a.remoteKey(virtualPath))
	if err == nil {
		fileInfo.Key = cleanVirtualPath(virtualPath)
		return fileInfo, nil
	}

	items, listErr := a.listDirectory(ctx, parentVirtualPrefix(virtualPath))
	if listErr == nil {
		clean := cleanVirtualPath(virtualPath)
		for _, item := range items {
			if item.Key == clean || item.Key == ensureDirSuffix(clean) {
				return item, nil
			}
		}
	}

	return s3ops.ObjectInfo{}, err
}

func (a *bucketAccess) downloadToCache(
	ctx context.Context,
	virtualPath string,
	info s3ops.ObjectInfo,
	localPath string,
) (string, error) {
	timeoutCtx, cancel := a.withTransferTimeout(ctx)
	defer cancel()
	reconcileDownloadArtifacts(localPath, info)
	if isCompleteDownloadUsable(localPath, info) {
		a.cache.storeObject(virtualPath, info)
		return localPath, nil
	}

	tempPath := partialDownloadPath(localPath)
	if err := writeDownloadStamp(tempPath, info); err != nil {
		return "", err
	}
	taskID := "mount-download-" + uuid.NewString()
	if err := a.backend.DownloadFile(timeoutCtx, a.bucket, a.remoteKey(virtualPath), tempPath, taskID); err != nil {
		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return "", err
	}
	_ = os.Remove(localPath)
	if err := os.Rename(tempPath, localPath); err != nil {
		return "", err
	}
	if err := renameDownloadStamp(stampPath(tempPath), stampPath(localPath)); err != nil {
		if !os.IsNotExist(err) {
			return "", err
		}
		if err := writeDownloadStamp(localPath, info); err != nil {
			return "", err
		}
	} else {
		_ = os.Remove(partialStampPath(localPath))
	}
	a.cache.storeObject(virtualPath, info)
	return localPath, nil
}

func (a *bucketAccess) prefetchChildren(items []s3ops.ObjectInfo) {
	if !a.allowPrefetch {
		return
	}
	prefetched := 0
	for _, item := range items {
		if !item.IsDir {
			continue
		}
		if prefetched >= maxPrefetchChildrenPerDirectory {
			return
		}
		childPrefix := strings.TrimSuffix(item.Key, "/")
		if !a.cache.shouldPrefetch(childPrefix) {
			continue
		}
		prefetched++
		go func(prefix string) {
			ctx, cancel := context.WithTimeout(context.Background(), a.requestTimeout)
			defer cancel()
			if err := a.prefetchDirectoryPreview(ctx, prefix); err != nil {
				log.Printf("[mount/prefetch] preview-error prefix=%q err=%v", prefix, err)
			}
		}(childPrefix)
	}
}

func (a *bucketAccess) prefetchDirectoryPreview(
	ctx context.Context,
	virtualPrefix string,
) error {
	page, err := a.backend.ListObjectsPage(
		ctx,
		a.bucket,
		a.remotePrefix(virtualPrefix),
		"",
		prefetchDirectoryPageSize,
	)
	if err != nil {
		return err
	}
	log.Printf(
		"[mount/prefetch] preview prefix=%q items=%d next_token=%q",
		cleanVirtualPath(virtualPrefix),
		len(page.Items),
		page.NextToken,
	)
	for _, item := range page.Items {
		item, ok := a.rewriteRemoteObject(item)
		if !ok {
			continue
		}
		a.cache.storeObject(strings.TrimSuffix(item.Key, "/"), item)
	}
	return nil
}

func (a *bucketAccess) listAllRemoteObjects(
	ctx context.Context,
	remotePrefix string,
) ([]s3ops.ObjectInfo, error) {
	items := make([]s3ops.ObjectInfo, 0, 200)
	nextToken := ""
	for {
		page, err := a.backend.ListObjectsPage(ctx, a.bucket, remotePrefix, nextToken, 200)
		if err != nil {
			return nil, err
		}
		items = append(items, page.Items...)
		if strings.TrimSpace(page.NextToken) == "" {
			return items, nil
		}
		if page.NextToken == nextToken {
			return nil, fmt.Errorf("mount remote listing repeated next token %q", nextToken)
		}
		nextToken = page.NextToken
	}
}

func (a *bucketAccess) rewriteRemoteObject(item s3ops.ObjectInfo) (s3ops.ObjectInfo, bool) {
	virtualKey, ok := a.virtualKey(item.Key, item.IsDir)
	if !ok {
		return s3ops.ObjectInfo{}, false
	}
	item.Key = virtualKey
	return item, true
}

func (a *bucketAccess) withTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	if ctx == nil {
		ctx = context.Background()
	}
	return context.WithTimeout(ctx, a.requestTimeout)
}

func (a *bucketAccess) withTransferTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	if ctx == nil {
		ctx = context.Background()
	}
	return context.WithTimeout(ctx, a.transferTimeout)
}

func (a *bucketAccess) remotePrefix(virtualPrefix string) string {
	clean := cleanVirtualPath(virtualPrefix)
	switch {
	case a.rootPrefix == "" && clean == "":
		return ""
	case a.rootPrefix == "":
		return ensureDirSuffix(clean)
	case clean == "":
		return ensureDirSuffix(a.rootPrefix)
	default:
		return ensureDirSuffix(a.rootPrefix + "/" + clean)
	}
}

func (a *bucketAccess) remoteKey(virtualPath string) string {
	clean := cleanVirtualPath(virtualPath)
	if a.rootPrefix == "" {
		return clean
	}
	if clean == "" {
		return a.rootPrefix
	}
	return a.rootPrefix + "/" + clean
}

func (a *bucketAccess) remoteKeyForMutation(virtualPath string, isDir bool) string {
	key := a.remoteKey(virtualPath)
	if isDir {
		return ensureDirSuffix(strings.TrimSuffix(key, "/"))
	}
	return key
}

func (a *bucketAccess) virtualKey(remoteKey string, isDir bool) (string, bool) {
	trimmed := strings.TrimSpace(remoteKey)
	if a.rootPrefix != "" {
		prefix := a.rootPrefix + "/"
		if trimmed == a.rootPrefix {
			trimmed = ""
		} else if strings.HasPrefix(trimmed, prefix) {
			trimmed = strings.TrimPrefix(trimmed, prefix)
		} else {
			return "", false
		}
	}
	trimmed = strings.TrimPrefix(trimmed, "/")
	if isDir {
		return ensureDirSuffix(strings.TrimSuffix(trimmed, "/")), true
	}
	return trimmed, true
}
