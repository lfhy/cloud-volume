// Baidu Pan fsid cache lets downloads reuse ids learned from directory lists.
package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"sync"

	storageconfig "remote-storage/go/config"
)

type baiduPanFsidCacheEntry struct {
	fsid uint64
}

var baiduPanFsidCache sync.Map

func rememberBaiduPanFsid(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	key string,
	fsid uint64,
) {
	if fsid == 0 {
		return
	}
	cacheKey := baiduPanFsidCacheKey(cfg, bucket, key)
	if cacheKey == "" {
		return
	}
	baiduPanFsidCache.Store(cacheKey, baiduPanFsidCacheEntry{fsid: fsid})
}

func cachedBaiduPanFsid(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	key string,
) (uint64, bool) {
	cacheKey := baiduPanFsidCacheKey(cfg, bucket, key)
	if cacheKey == "" {
		return 0, false
	}
	value, ok := baiduPanFsidCache.Load(cacheKey)
	if !ok {
		return 0, false
	}
	entry, ok := value.(baiduPanFsidCacheEntry)
	return entry.fsid, ok && entry.fsid != 0
}

func forgetBaiduPanFsid(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	key string,
) {
	cacheKey := baiduPanFsidCacheKey(cfg, bucket, key)
	if cacheKey != "" {
		baiduPanFsidCache.Delete(cacheKey)
	}
}

func baiduPanFsidCacheKey(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	key string,
) string {
	cleanKey := baiduPanCleanKey(key)
	if cleanKey == "" {
		return ""
	}
	normalized := cfg.Normalized()
	identity := strings.Join([]string{
		normalized.Endpoint,
		normalized.DisplayName,
		normalized.MappedBucketName,
		strings.TrimSpace(bucket),
		normalized.AccessKeyID,
	}, "\x00")
	sum := sha256.Sum256([]byte(identity))
	return hex.EncodeToString(sum[:]) + "\x00" + cleanKey
}
