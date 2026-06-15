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

func (m *manager) listMountedObjectPage(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	prefix,
	nextToken string,
	pageSize int32,
) (s3ops.ObjectPage, bool, error) {
	m.mu.Lock()
	if err := m.syncSessionLocked(); err != nil {
		m.mu.Unlock()
		log.Printf("[mount/object-page] sync-error bucket=%q prefix=%q err=%v", bucket, prefix, err)
		return s3ops.ObjectPage{}, false, err
	}
	session := m.session
	if !mountSessionMatches(session, cfg, bucket, MountOptions{}) || session == nil || session.access == nil {
		m.mu.Unlock()
		return s3ops.ObjectPage{}, false, nil
	}
	access := session.access
	m.mu.Unlock()

	items, err := access.listDirectory(context.Background(), prefix)
	if err != nil {
		log.Printf("[mount/object-page] mounted-list-error bucket=%q prefix=%q err=%v", bucket, prefix, err)
		return s3ops.ObjectPage{}, true, err
	}
	sortObjectInfos(items)
	return paginateObjectInfos(items, nextToken, pageSize), true, nil
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
