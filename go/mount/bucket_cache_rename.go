// Bucket cache rename helpers move staged bytes before updating their path indexes.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type cacheLocalMove struct {
	oldKey  string
	newKey  string
	oldPath string
	newPath string
	item    localFile
}

func (c *bucketCache) renameLocalFile(
	oldVirtualPath,
	newVirtualPath string,
	isDir bool,
	cacheRoot string,
) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	oldClean := cleanVirtualPath(oldVirtualPath)
	newClean := cleanVirtualPath(newVirtualPath)
	if oldClean == newClean {
		return nil
	}
	if !isDir {
		if err := c.renameLocalFileLocked(oldClean, newClean, cacheRoot); err != nil {
			return err
		}
		c.renameLocalEntryLocked(oldClean, newClean, false)
		c.renameDeletedLocked(oldClean, newClean, false)
		c.invalidateParentsLocked(oldClean)
		c.invalidateParentsLocked(newClean)
		return nil
	}

	oldPrefix := ensureDirSuffix(oldClean)
	newPrefix := ensureDirSuffix(newClean)
	moves := make([]cacheLocalMove, 0)
	for key, item := range c.localFiles {
		if !strings.HasPrefix(key, oldPrefix) {
			continue
		}
		suffix := strings.TrimPrefix(key, oldPrefix)
		nextKey := newPrefix + suffix
		moves = append(moves, cacheLocalMove{
			oldKey:  key,
			newKey:  nextKey,
			oldPath: item.localPath,
			newPath: pathForVirtualKey(cacheRoot, nextKey),
			item:    item,
		})
	}
	if err := moveCacheLocalFiles(moves); err != nil {
		return err
	}
	c.renameLocalEntryLocked(oldClean, newClean, true)
	c.renameDeletedLocked(oldClean, newClean, true)
	for _, move := range moves {
		item := move.item
		item.localPath = move.newPath
		item.info.Key = move.newKey
		c.localFiles[move.newKey] = item
		delete(c.localFiles, move.oldKey)
	}
	c.invalidateParentsLocked(oldClean)
	c.invalidateParentsLocked(newClean)
	return nil
}

func (c *bucketCache) renameLocalFileLocked(oldClean, newClean, cacheRoot string) error {
	item, ok := c.localFiles[oldClean]
	if !ok {
		return nil
	}
	newCachePath := pathForVirtualKey(cacheRoot, newClean)
	move := cacheLocalMove{
		oldKey:  oldClean,
		newKey:  newClean,
		oldPath: item.localPath,
		newPath: newCachePath,
		item:    item,
	}
	if err := moveCacheLocalFiles([]cacheLocalMove{move}); err != nil {
		return err
	}
	item.localPath = newCachePath
	item.info.Key = newClean
	c.localFiles[newClean] = item
	delete(c.localFiles, oldClean)
	return nil
}

// moveCacheLocalFiles updates bytes before their map entries. A failed move
// leaves the cache index unchanged, so writeback keeps pointing at source data.
func moveCacheLocalFiles(moves []cacheLocalMove) error {
	for _, move := range moves {
		if move.oldPath == move.newPath {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(move.newPath), 0o755); err != nil {
			return fmt.Errorf("create cache rename directory %q: %w", filepath.Dir(move.newPath), err)
		}
		if _, err := os.Lstat(move.newPath); err == nil {
			return fmt.Errorf("cache rename destination %q exists", move.newPath)
		} else if !os.IsNotExist(err) {
			return fmt.Errorf("stat cache rename destination %q: %w", move.newPath, err)
		}
	}

	moved := make([]cacheLocalMove, 0, len(moves))
	for _, move := range moves {
		if move.oldPath == move.newPath {
			continue
		}
		if err := os.Rename(move.oldPath, move.newPath); err != nil {
			rollbackCacheLocalMoves(moved)
			return fmt.Errorf("move cached writeback file %q to %q: %w", move.oldPath, move.newPath, err)
		}
		moved = append(moved, move)
	}
	return nil
}

func rollbackCacheLocalMoves(moves []cacheLocalMove) {
	for index := len(moves) - 1; index >= 0; index-- {
		move := moves[index]
		if err := os.MkdirAll(filepath.Dir(move.oldPath), 0o755); err != nil {
			continue
		}
		_ = os.Rename(move.newPath, move.oldPath)
	}
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
