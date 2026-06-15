// Bucket cache keeps remote metadata plus local overlay state for delayed writeback.
package mount

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	s3ops "remote-storage/go/s3"
)

type bucketCache struct {
	mu            sync.RWMutex
	ttl           time.Duration
	prefetchTTL   time.Duration
	objectCache   map[string]cachedObject
	listCache     map[string]cachedList
	localFiles    map[string]localFile
	localEntries  map[string]localEntry
	deletedPaths  map[string]deletedEntry
	prefetchStamp map[string]time.Time
}

type cachedObject struct {
	info      s3ops.ObjectInfo
	expiresAt time.Time
}

type cachedList struct {
	items     []s3ops.ObjectInfo
	expiresAt time.Time
}

type localFile struct {
	info      s3ops.ObjectInfo
	localPath string
}

type localEntry struct {
	info s3ops.ObjectInfo
}

type deletedEntry struct {
	isDir bool
}

func newBucketCache(ttl, prefetchTTL time.Duration) *bucketCache {
	return &bucketCache{
		ttl:           ttl,
		prefetchTTL:   prefetchTTL,
		objectCache:   map[string]cachedObject{},
		listCache:     map[string]cachedList{},
		localFiles:    map[string]localFile{},
		localEntries:  map[string]localEntry{},
		deletedPaths:  map[string]deletedEntry{},
		prefetchStamp: map[string]time.Time{},
	}
}

func (c *bucketCache) cachedList(virtualPrefix string) ([]s3ops.ObjectInfo, bool) {
	if c.ttl <= 0 {
		return nil, false
	}
	c.mu.RLock()
	defer c.mu.RUnlock()

	item, ok := c.listCache[cleanVirtualPath(virtualPrefix)]
	if !ok || time.Now().After(item.expiresAt) {
		return nil, false
	}
	return cloneObjects(item.items), true
}

func (c *bucketCache) cachedObject(virtualPath string) (s3ops.ObjectInfo, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	clean := cleanVirtualPath(virtualPath)
	if tombstone, ok := c.deletedPaths[clean]; ok {
		return s3ops.ObjectInfo{Key: deletedKey(clean, tombstone.isDir), IsDir: tombstone.isDir}, false
	}
	if item, ok := c.localEntries[clean]; ok {
		return item.info, true
	}
	if c.ttl <= 0 {
		return s3ops.ObjectInfo{}, false
	}
	item, ok := c.objectCache[clean]
	if !ok || time.Now().After(item.expiresAt) {
		return s3ops.ObjectInfo{}, false
	}
	return item.info, true
}

func (c *bucketCache) localFile(virtualPath string) (localFile, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	item, ok := c.localFiles[cleanVirtualPath(virtualPath)]
	return item, ok
}

func (c *bucketCache) storeList(virtualPrefix string, items []s3ops.ObjectInfo) {
	if c.ttl <= 0 {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()

	c.listCache[cleanVirtualPath(virtualPrefix)] = cachedList{
		items:     cloneObjects(items),
		expiresAt: time.Now().Add(c.ttl),
	}
}

func (c *bucketCache) storeObject(virtualPath string, info s3ops.ObjectInfo) {
	if c.ttl <= 0 {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()

	key := cleanVirtualPath(virtualPath)
	info = normalizeObjectInfo(key, info)
	c.objectCache[key] = cachedObject{
		info:      info,
		expiresAt: time.Now().Add(c.ttl),
	}
}

func (c *bucketCache) storeLocalFile(
	virtualPath,
	localPath string,
	info s3ops.ObjectInfo,
) {
	c.mu.Lock()
	defer c.mu.Unlock()

	key := cleanVirtualPath(virtualPath)
	info = normalizeObjectInfo(key, info)
	c.localFiles[key] = localFile{
		info:      info,
		localPath: localPath,
	}
	c.localEntries[key] = localEntry{info: info}
	c.objectCache[key] = cachedObject{
		info:      info,
		expiresAt: time.Now().Add(c.ttl),
	}
	delete(c.deletedPaths, key)
	c.invalidateParentsLocked(key)
}

func (c *bucketCache) storeLocalDirectory(virtualPath string, info s3ops.ObjectInfo) {
	c.mu.Lock()
	defer c.mu.Unlock()

	key := cleanVirtualPath(virtualPath)
	info.IsDir = true
	info = normalizeObjectInfo(key, info)
	c.localEntries[key] = localEntry{info: info}
	c.objectCache[key] = cachedObject{
		info:      info,
		expiresAt: time.Now().Add(c.ttl),
	}
	delete(c.deletedPaths, key)
	c.invalidateParentsLocked(key)
}

func (c *bucketCache) removeLocalFile(virtualPath string, isDir bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.removeLocalPathLocked(virtualPath, isDir)
}

func (c *bucketCache) removeLocalPath(virtualPath string, isDir bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.removeLocalPathLocked(virtualPath, isDir)
}

func (c *bucketCache) removeLocalPathLocked(virtualPath string, isDir bool) {
	clean := cleanVirtualPath(virtualPath)
	if !isDir {
		if item, ok := c.localFiles[clean]; ok {
			_ = os.Remove(item.localPath)
		}
		delete(c.localFiles, clean)
		delete(c.localEntries, clean)
		delete(c.deletedPaths, clean)
		c.invalidateParentsLocked(clean)
		return
	}

	prefix := ensureDirSuffix(clean)
	for key, item := range c.localFiles {
		if strings.HasPrefix(key, prefix) {
			_ = os.Remove(item.localPath)
			delete(c.localFiles, key)
		}
	}
	for key := range c.localEntries {
		if key == clean || strings.HasPrefix(key, prefix) {
			delete(c.localEntries, key)
		}
	}
	for key := range c.deletedPaths {
		if key == clean || strings.HasPrefix(key, prefix) {
			delete(c.deletedPaths, key)
		}
	}
	c.invalidateParentsLocked(clean)
}

func (c *bucketCache) clearLocalFileMarker(virtualPath string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	delete(c.localFiles, cleanVirtualPath(virtualPath))
}

func (c *bucketCache) markDeleted(virtualPath string, isDir bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	c.removeLocalPathLocked(clean, isDir)
	c.deletedPaths[clean] = deletedEntry{isDir: isDir}
	c.invalidateParentsLocked(clean)
}

func (c *bucketCache) isMarkedDeleted(virtualPath string) bool {
	c.mu.RLock()
	defer c.mu.RUnlock()

	clean := cleanVirtualPath(virtualPath)
	if _, ok := c.deletedPaths[clean]; ok {
		return true
	}
	for key, tombstone := range c.deletedPaths {
		if tombstone.isDir && strings.HasPrefix(clean, ensureDirSuffix(key)) {
			return true
		}
	}
	return false
}

func (c *bucketCache) renameLocalFile(
	oldVirtualPath,
	newVirtualPath string,
	isDir bool,
	cacheRoot string,
) {
	c.mu.Lock()
	defer c.mu.Unlock()

	oldClean := cleanVirtualPath(oldVirtualPath)
	newClean := cleanVirtualPath(newVirtualPath)
	if !isDir {
		c.renameLocalFileLocked(oldClean, newClean, cacheRoot)
		c.renameLocalEntryLocked(oldClean, newClean, false)
		c.renameDeletedLocked(oldClean, newClean, false)
		c.invalidateParentsLocked(oldClean)
		c.invalidateParentsLocked(newClean)
		return
	}

	oldPrefix := ensureDirSuffix(oldClean)
	newPrefix := ensureDirSuffix(newClean)
	c.renameLocalEntryLocked(oldClean, newClean, true)
	c.renameDeletedLocked(oldClean, newClean, true)
	for key, item := range c.localFiles {
		if !strings.HasPrefix(key, oldPrefix) {
			continue
		}
		suffix := strings.TrimPrefix(key, oldPrefix)
		nextKey := newPrefix + suffix
		nextPath := pathForVirtualKey(cacheRoot, nextKey)
		_ = os.MkdirAll(filepath.Dir(nextPath), 0o755)
		_ = os.Remove(nextPath)
		_ = os.Rename(item.localPath, nextPath)
		item.localPath = nextPath
		item.info.Key = nextKey
		c.localFiles[nextKey] = item
		delete(c.localFiles, key)
	}
	c.invalidateParentsLocked(oldClean)
	c.invalidateParentsLocked(newClean)
}

func (c *bucketCache) renameLocalFileLocked(oldClean, newClean, cacheRoot string) {
	item, ok := c.localFiles[oldClean]
	if !ok {
		return
	}
	newCachePath := pathForVirtualKey(cacheRoot, newClean)
	_ = os.MkdirAll(filepath.Dir(newCachePath), 0o755)
	_ = os.Remove(newCachePath)
	_ = os.Rename(item.localPath, newCachePath)
	item.localPath = newCachePath
	item.info.Key = newClean
	c.localFiles[newClean] = item
	delete(c.localFiles, oldClean)
}

func (c *bucketCache) renameLocalEntryLocked(oldClean, newClean string, isDir bool) {
	if !isDir {
		item, ok := c.localEntries[oldClean]
		if !ok {
			return
		}
		item.info = normalizeObjectInfo(newClean, item.info)
		c.localEntries[newClean] = item
		delete(c.localEntries, oldClean)
		return
	}

	if item, ok := c.localEntries[oldClean]; ok {
		item.info = normalizeObjectInfo(newClean, item.info)
		c.localEntries[newClean] = item
		delete(c.localEntries, oldClean)
	}
	oldPrefix := ensureDirSuffix(oldClean)
	newPrefix := ensureDirSuffix(newClean)
	for key, item := range c.localEntries {
		if !strings.HasPrefix(key, oldPrefix) {
			continue
		}
		nextKey := newPrefix + strings.TrimPrefix(key, oldPrefix)
		item.info = normalizeObjectInfo(nextKey, item.info)
		c.localEntries[nextKey] = item
		delete(c.localEntries, key)
	}
}

func (c *bucketCache) renameDeletedLocked(oldClean, newClean string, isDir bool) {
	if !isDir {
		if item, ok := c.deletedPaths[oldClean]; ok {
			c.deletedPaths[newClean] = item
			delete(c.deletedPaths, oldClean)
		}
		return
	}
	if item, ok := c.deletedPaths[oldClean]; ok {
		c.deletedPaths[newClean] = item
		delete(c.deletedPaths, oldClean)
	}
	oldPrefix := ensureDirSuffix(oldClean)
	newPrefix := ensureDirSuffix(newClean)
	for key, item := range c.deletedPaths {
		if !strings.HasPrefix(key, oldPrefix) {
			continue
		}
		nextKey := newPrefix + strings.TrimPrefix(key, oldPrefix)
		c.deletedPaths[nextKey] = item
		delete(c.deletedPaths, key)
	}
}

func (c *bucketCache) mergeLocalFiles(
	virtualPrefix string,
	items []s3ops.ObjectInfo,
) []s3ops.ObjectInfo {
	c.mu.RLock()
	defer c.mu.RUnlock()

	byKey := map[string]s3ops.ObjectInfo{}
	cleanPrefix := cleanVirtualPath(virtualPrefix)
	for _, item := range items {
		key := cleanVirtualPath(strings.TrimSuffix(item.Key, "/"))
		if c.hiddenByDeleteLocked(key) {
			continue
		}
		byKey[item.Key] = item
	}

	for key, item := range c.localEntries {
		if parentVirtualPrefix(key) != cleanPrefix {
			continue
		}
		if c.hiddenByDeleteLocked(key) {
			continue
		}
		byKey[item.info.Key] = item.info
	}

	out := make([]s3ops.ObjectInfo, 0, len(byKey))
	for _, item := range byKey {
		out = append(out, item)
	}
	return out
}

func (c *bucketCache) shouldPrefetch(virtualPrefix string) bool {
	if c.prefetchTTL <= 0 {
		return false
	}
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	clean := cleanVirtualPath(virtualPrefix)
	if stamp, ok := c.prefetchStamp[clean]; ok && now.Sub(stamp) < c.prefetchTTL {
		return false
	}
	c.prefetchStamp[clean] = now
	return true
}

func (c *bucketCache) invalidatePath(virtualPath string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.invalidatePathLocked(virtualPath)
}

func (c *bucketCache) invalidatePathLocked(virtualPath string) {
	clean := cleanVirtualPath(virtualPath)
	delete(c.objectCache, clean)
	delete(c.listCache, clean)
	delete(c.listCache, parentVirtualPrefix(clean))
	for prefix := range c.listCache {
		if clean != "" && strings.HasPrefix(prefix, ensureDirSuffix(clean)) {
			delete(c.listCache, prefix)
		}
	}
}

func (c *bucketCache) invalidateParentsLocked(virtualPath string) {
	clean := cleanVirtualPath(virtualPath)
	delete(c.listCache, clean)
	delete(c.listCache, parentVirtualPrefix(clean))
}

func (c *bucketCache) hiddenByDeleteLocked(virtualPath string) bool {
	clean := cleanVirtualPath(virtualPath)
	if _, ok := c.deletedPaths[clean]; ok {
		return true
	}
	for key, tombstone := range c.deletedPaths {
		if tombstone.isDir && strings.HasPrefix(clean, ensureDirSuffix(key)) {
			return true
		}
	}
	return false
}

func normalizeObjectInfo(virtualPath string, info s3ops.ObjectInfo) s3ops.ObjectInfo {
	key := cleanVirtualPath(virtualPath)
	if info.IsDir {
		info.Key = ensureDirSuffix(key)
	} else {
		info.Key = key
	}
	return info
}

func deletedKey(virtualPath string, isDir bool) string {
	if isDir {
		return ensureDirSuffix(cleanVirtualPath(virtualPath))
	}
	return cleanVirtualPath(virtualPath)
}
