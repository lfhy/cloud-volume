// Preview cache index persists cached-object metadata in the config bbolt DB.
package config

import (
	"bytes"
	"encoding/json"
	"fmt"
	"time"

	bolt "go.etcd.io/bbolt"
)

var previewCacheBucketKey = []byte("preview_cache")

// CacheIndexRecord is the bridge-facing metadata for a cached remote object.
type CacheIndexRecord struct {
	Bucket           string `json:"bucket"`
	ObjectKey        string `json:"objectKey"`
	LocalPath        string `json:"localPath"`
	FileSize         int64  `json:"fileSize"`
	LastModified     string `json:"lastModified"`
	UpdatedAtEpochMs int64  `json:"updatedAtEpochMs"`
}

// FindCacheIndexRecord returns the cached record for bucket/objectKey, if any.
func FindCacheIndexRecord(bucket, objectKey string) (*CacheIndexRecord, error) {
	db, release, err := acquireConfigDB()
	if err != nil {
		return nil, err
	}
	defer release()

	var record *CacheIndexRecord
	err = db.View(func(tx *bolt.Tx) error {
		cacheBucket := tx.Bucket(previewCacheBucketKey)
		if cacheBucket == nil {
			return nil
		}
		data := cacheBucket.Get(cacheIndexKey(bucket, objectKey))
		if data == nil {
			return nil
		}
		var decoded CacheIndexRecord
		if err := json.Unmarshal(data, &decoded); err != nil {
			return fmt.Errorf("decode cache index record: %w", err)
		}
		record = &decoded
		return nil
	})
	if err != nil {
		return nil, err
	}
	return record, nil
}

// UpsertCacheIndexRecord stores or replaces one cached-object index record.
func UpsertCacheIndexRecord(record CacheIndexRecord) error {
	if record.Bucket == "" || record.ObjectKey == "" {
		return fmt.Errorf("cache index bucket and objectKey are required")
	}
	if record.UpdatedAtEpochMs == 0 {
		record.UpdatedAtEpochMs = time.Now().UnixMilli()
	}
	data, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("encode cache index record: %w", err)
	}

	db, release, err := acquireConfigDB()
	if err != nil {
		return err
	}
	defer release()

	return db.Update(func(tx *bolt.Tx) error {
		cacheBucket, err := tx.CreateBucketIfNotExists(previewCacheBucketKey)
		if err != nil {
			return fmt.Errorf("create preview cache bucket: %w", err)
		}
		return cacheBucket.Put(cacheIndexKey(record.Bucket, record.ObjectKey), data)
	})
}

// RemoveCacheIndexRecord deletes a single cached-object index entry.
func RemoveCacheIndexRecord(bucket, objectKey string) error {
	db, release, err := acquireConfigDB()
	if err != nil {
		return err
	}
	defer release()

	return db.Update(func(tx *bolt.Tx) error {
		cacheBucket := tx.Bucket(previewCacheBucketKey)
		if cacheBucket == nil {
			return nil
		}
		return cacheBucket.Delete(cacheIndexKey(bucket, objectKey))
	})
}

// RemoveCacheIndexPrefix deletes matching index entries and returns them so the
// caller can remove their local files after the metadata update commits.
func RemoveCacheIndexPrefix(bucket, objectKeyPrefix string) ([]CacheIndexRecord, error) {
	db, release, err := acquireConfigDB()
	if err != nil {
		return nil, err
	}
	defer release()

	var removed []CacheIndexRecord
	err = db.Update(func(tx *bolt.Tx) error {
		cacheBucket := tx.Bucket(previewCacheBucketKey)
		if cacheBucket == nil {
			return nil
		}
		prefix := cacheIndexKey(bucket, objectKeyPrefix)
		cursor := cacheBucket.Cursor()
		for key, data := cursor.Seek(prefix); key != nil && bytes.HasPrefix(key, prefix); key, data = cursor.Next() {
			var record CacheIndexRecord
			if err := json.Unmarshal(data, &record); err != nil {
				return fmt.Errorf("decode cache index record: %w", err)
			}
			removed = append(removed, record)
			if err := cursor.Delete(); err != nil {
				return fmt.Errorf("delete cache index record: %w", err)
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	if removed == nil {
		removed = []CacheIndexRecord{}
	}
	return removed, nil
}

func cacheIndexKey(bucket, objectKey string) []byte {
	return []byte(bucket + "\x00" + objectKey)
}
