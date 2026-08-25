// Mounted object pages let Flutter browse the same local-first view used by desktop mounts.
package mount

import (
	"context"
	"log"
	"strconv"
	"strings"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

// ListMountedObjectPage returns the active mount session's merged local-first directory page when possible.
func ListMountedObjectPage(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	prefix,
	nextToken string,
	pageSize int32,
) (s3ops.ObjectPage, bool, error) {
	return globalManager.listMountedObjectPage(cfg, bucket, prefix, nextToken, pageSize)
}

// InvalidateListCacheForPrefix drops cached directory listings for the given
// bucket and prefix so the next ListMountedObjectPage call fetches fresh data.
func InvalidateListCacheForPrefix(cfg storageconfig.RemoteStorageConfig, bucket, prefix string) {
	globalManager.invalidateListCacheForPrefix(cfg, bucket, prefix)
}

func (m *manager) invalidateListCacheForPrefix(cfg storageconfig.RemoteStorageConfig, bucket, prefix string) {
	m.mu.Lock()
	defer m.mu.Unlock()

	trimmedBucket := normalizeBucketName(bucket)
	session, ok := m.sessions[trimmedBucket]
	if !ok || session.access == nil {
		return
	}
	if !mountSessionMatches(session, cfg, trimmedBucket, MountOptions{}) {
		return
	}
	log.Printf("[mount/object-page] invalidate-list-cache bucket=%q prefix=%q", trimmedBucket, prefix)
	session.access.InvalidateListCache(prefix)
}

func (m *manager) listMountedObjectPage(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	prefix,
	nextToken string,
	pageSize int32,
) (s3ops.ObjectPage, bool, error) {
	m.mu.Lock()
	trimmedBucket := normalizeBucketName(bucket)
	existing, ok := m.sessions[trimmedBucket]
	if !ok {
		m.mu.Unlock()
		return s3ops.ObjectPage{}, false, nil
	}
	if !m.syncSessionLocked(existing) {
		delete(m.sessions, trimmedBucket)
		delete(m.lastProbes, existing.mountTarget)
		m.mu.Unlock()
		log.Printf("[mount/object-page] sync-inactive bucket=%q prefix=%q", bucket, prefix)
		return s3ops.ObjectPage{}, false, nil
	}
	if !existing.mounted {
		m.mu.Unlock()
		log.Printf("[mount/object-page] sync-unready bucket=%q prefix=%q", bucket, prefix)
		return s3ops.ObjectPage{}, false, nil
	}
	session := existing
	if !mountSessionMatches(session, cfg, trimmedBucket, MountOptions{}) || session.access == nil {
		m.mu.Unlock()
		return s3ops.ObjectPage{}, false, nil
	}
	access := session.access
	m.mu.Unlock()
	if page, ok := access.pageViews.page(prefix, nextToken, pageSize); ok {
		return page, true, nil
	}

	items, err := access.listDirectory(context.Background(), prefix)
	if err != nil {
		log.Printf("[mount/object-page] mounted-list-error bucket=%q prefix=%q err=%v", bucket, prefix, err)
		return s3ops.ObjectPage{}, true, err
	}
	sortObjectInfos(items)
	return access.pageViews.start(prefix, items, nextToken, pageSize), true, nil
}

func paginateObjectInfos(
	items []s3ops.ObjectInfo,
	nextToken string,
	pageSize int32,
) s3ops.ObjectPage {
	if pageSize <= 0 {
		pageSize = 200
	}
	offset := 0
	if trimmed := strings.TrimSpace(nextToken); trimmed != "" {
		if parsed, err := strconv.Atoi(trimmed); err == nil && parsed >= 0 {
			offset = parsed
		}
	}
	if offset >= len(items) {
		return s3ops.ObjectPage{Items: []s3ops.ObjectInfo{}, NextToken: ""}
	}

	end := offset + int(pageSize)
	if end > len(items) {
		end = len(items)
	}
	page := s3ops.ObjectPage{
		Items: cloneObjects(items[offset:end]),
	}
	if end < len(items) {
		page.NextToken = strconv.Itoa(end)
	}
	return page
}
