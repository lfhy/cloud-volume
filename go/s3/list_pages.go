// Paged listing helpers expose continuation-token based object and trash pages.
package s3

import (
	"context"
	"log"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

const defaultListPageSize int32 = 200
const trashMetadataPageConcurrency = 8
const objectListTimeout = 15 * time.Second

type ObjectPage struct {
	Items     []ObjectInfo `json:"items"`
	NextToken string       `json:"nextToken"`
}

type TrashPage struct {
	Items     []TrashItem `json:"items"`
	NextToken string      `json:"nextToken"`
}

func ListObjectsPage(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	prefix,
	nextToken string,
	pageSize int32,
) (ObjectPage, error) {
	return ListObjectsPageContext(Ctx(), cfg, bucket, prefix, nextToken, pageSize)
}

func ListObjectsPageContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	prefix,
	nextToken string,
	pageSize int32,
) (ObjectPage, error) {
	client := NewClient(cfg)
	if ctx == nil {
		ctx = Ctx()
	}
	ctx, cancel := context.WithTimeout(ctx, objectListTimeout)
	defer cancel()
	startedAt := time.Now()
	log.Printf("[s3/list] start bucket=%q prefix=%q next_token=%q page_size=%d", bucket, prefix, nextToken, pageSize)
	if prefix != "" && !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}
	if pageSize <= 0 {
		pageSize = defaultListPageSize
	}
	input := &s3.ListObjectsV2Input{
		Bucket:    &bucket,
		Prefix:    &prefix,
		Delimiter: aws.String("/"),
		MaxKeys:   aws.Int32(pageSize),
	}
	if strings.TrimSpace(nextToken) != "" {
		input.ContinuationToken = aws.String(strings.TrimSpace(nextToken))
	}
	out, err := client.ListObjectsV2(ctx, input)
	if err != nil {
		log.Printf("[s3/list] error bucket=%q prefix=%q duration=%s err=%v", bucket, prefix, time.Since(startedAt).Round(time.Millisecond), err)
		return ObjectPage{}, err
	}

	items := make([]ObjectInfo, 0, len(out.CommonPrefixes)+len(out.Contents))
	for _, cp := range out.CommonPrefixes {
		if cp.Prefix != nil && isRootTrashKey(cfg, *cp.Prefix) {
			continue
		}
		items = append(items, ObjectInfo{Key: *cp.Prefix, IsDir: true})
	}
	for _, obj := range out.Contents {
		if obj.Key != nil && *obj.Key == prefix {
			continue
		}
		if obj.Key != nil && isRootTrashKey(cfg, *obj.Key) {
			continue
		}
		info := ObjectInfo{Key: *obj.Key, Size: *obj.Size}
		info.LastModified = formatObjectLastModified(obj.LastModified)
		items = append(items, info)
	}
	if items == nil {
		items = []ObjectInfo{}
	}
	log.Printf("[s3/list] done bucket=%q prefix=%q duration=%s items=%d next_token=%q", bucket, prefix, time.Since(startedAt).Round(time.Millisecond), len(items), aws.ToString(out.NextContinuationToken))
	return ObjectPage{
		Items:     items,
		NextToken: aws.ToString(out.NextContinuationToken),
	}, nil
}

func ListTrashPage(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	nextToken string,
	pageSize int32,
) (TrashPage, error) {
	return ListTrashPageContext(Ctx(), cfg, bucket, nextToken, pageSize)
}

func ListTrashPageContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	nextToken string,
	pageSize int32,
) (TrashPage, error) {
	client := NewClient(cfg)
	if ctx == nil {
		ctx = Ctx()
	}
	scheduleExpiredTrashPurge(cfg, bucket)
	if pageSize <= 0 {
		pageSize = defaultListPageSize
	}

	mode, token := parseTrashPageCursor(nextToken)
	if mode == legacyTrashPageMode {
		items, next, err := listLegacyTrashPage(ctx, client, cfg, bucket, token, pageSize)
		if err != nil {
			return TrashPage{}, err
		}
		return TrashPage{Items: items, NextToken: formatTrashPageCursor(legacyTrashPageMode, next)}, nil
	}

	indexedItems, indexedNextToken, err := listIndexedTrashPage(ctx, client, cfg, bucket, token, pageSize)
	if err != nil {
		return TrashPage{}, err
	}
	if indexedNextToken != "" {
		return TrashPage{
			Items:     indexedItems,
			NextToken: formatTrashPageCursor(indexedTrashPageMode, indexedNextToken),
		}, nil
	}
	if int32(len(indexedItems)) >= pageSize {
		return TrashPage{Items: indexedItems}, nil
	}

	legacyItems, legacyNextToken, err := listLegacyTrashPage(
		ctx,
		client,
		cfg,
		bucket,
		"",
		pageSize-int32(len(indexedItems)),
	)
	if err != nil {
		return TrashPage{}, err
	}
	items := mergeTrashItems(indexedItems, legacyItems)
	sort.Slice(items, func(i, j int) bool {
		return items[i].DeletedAt > items[j].DeletedAt
	})
	return TrashPage{
		Items:     items,
		NextToken: formatTrashPageCursor(legacyTrashPageMode, legacyNextToken),
	}, nil
}

func loadTrashItemsPage(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	metadataKeys []string,
) ([]TrashItem, []trashMetadata, error) {
	if len(metadataKeys) == 0 {
		return []TrashItem{}, []trashMetadata{}, nil
	}

	items := make([]TrashItem, len(metadataKeys))
	metadatas := make([]trashMetadata, len(metadataKeys))
	var (
		wg       sync.WaitGroup
		mu       sync.Mutex
		firstErr error
		sem      = make(chan struct{}, trashMetadataPageConcurrency)
	)

	for index, metadataKey := range metadataKeys {
		wg.Add(1)
		sem <- struct{}{}
		go func(index int, metadataKey string) {
			defer wg.Done()
			defer func() {
				<-sem
			}()

			metadata, err := loadTrashMetadataByKey(ctx, client, bucket, metadataKey)
			if err != nil {
				mu.Lock()
				if firstErr == nil {
					firstErr = err
				}
				mu.Unlock()
				return
			}
			items[index] = trashItemFromMetadata(metadata)
			metadatas[index] = metadata
		}(index, metadataKey)
	}

	wg.Wait()
	if firstErr != nil {
		return nil, nil, firstErr
	}

	filteredItems := make([]TrashItem, 0, len(items))
	filteredMetadata := make([]trashMetadata, 0, len(metadatas))
	for index, item := range items {
		if strings.TrimSpace(item.ID) == "" {
			continue
		}
		filteredItems = append(filteredItems, item)
		filteredMetadata = append(filteredMetadata, metadatas[index])
	}
	return filteredItems, filteredMetadata, nil
}

func listIndexedTrashPage(
	ctx context.Context,
	client *s3.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	nextToken string,
	pageSize int32,
) ([]TrashItem, string, error) {
	input := &s3.ListObjectsV2Input{
		Bucket:  &bucket,
		Prefix:  aws.String(trashIndexByTimePrefix(cfg)),
		MaxKeys: aws.Int32(pageSize),
	}
	if strings.TrimSpace(nextToken) != "" {
		input.ContinuationToken = aws.String(strings.TrimSpace(nextToken))
	}
	out, err := client.ListObjectsV2(ctx, input)
	if err != nil {
		return nil, "", err
	}
	items := make([]TrashItem, 0, len(out.Contents))
	for _, obj := range out.Contents {
		if obj.Key == nil || !strings.HasSuffix(*obj.Key, trashIndexSuffix) {
			continue
		}
		item, err := parseTrashItemFromByTimeIndexKey(cfg, *obj.Key)
		if err != nil {
			return nil, "", err
		}
		items = append(items, item)
	}
	return items, aws.ToString(out.NextContinuationToken), nil
}

func listLegacyTrashPage(
	ctx context.Context,
	client *s3.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	nextToken string,
	pageSize int32,
) ([]TrashItem, string, error) {
	if pageSize <= 0 {
		return []TrashItem{}, "", nil
	}
	input := &s3.ListObjectsV2Input{
		Bucket:  &bucket,
		Prefix:  aws.String(trashMetadataPrefix(cfg)),
		MaxKeys: aws.Int32(pageSize),
	}
	if strings.TrimSpace(nextToken) != "" {
		input.ContinuationToken = aws.String(strings.TrimSpace(nextToken))
	}
	out, err := client.ListObjectsV2(ctx, input)
	if err != nil {
		return nil, "", err
	}
	metadataKeys := make([]string, 0, len(out.Contents))
	for _, obj := range out.Contents {
		if obj.Key == nil || !strings.HasSuffix(*obj.Key, trashMetadataSuffix) {
			continue
		}
		metadataKeys = append(metadataKeys, *obj.Key)
	}
	items, metadatas, err := loadTrashItemsPage(ctx, client, bucket, metadataKeys)
	if err != nil {
		return nil, "", err
	}
	sort.Slice(items, func(i, j int) bool {
		return items[i].DeletedAt > items[j].DeletedAt
	})
	migrateLegacyTrashMetadata(cfg, bucket, metadatas)
	return items, aws.ToString(out.NextContinuationToken), nil
}

func mergeTrashItems(primary []TrashItem, secondary []TrashItem) []TrashItem {
	merged := make([]TrashItem, 0, len(primary)+len(secondary))
	seen := make(map[string]struct{}, len(primary)+len(secondary))
	for _, item := range append(primary, secondary...) {
		id := strings.TrimSpace(item.ID)
		if id == "" {
			continue
		}
		if _, exists := seen[id]; exists {
			continue
		}
		seen[id] = struct{}{}
		merged = append(merged, item)
	}
	return merged
}

func parseTrashPageCursor(cursor string) (string, string) {
	cursor = strings.TrimSpace(cursor)
	if cursor == "" {
		return indexedTrashPageMode, ""
	}
	if strings.HasPrefix(cursor, legacyTrashPageMode+":") {
		return legacyTrashPageMode, strings.TrimPrefix(cursor, legacyTrashPageMode+":")
	}
	if strings.HasPrefix(cursor, indexedTrashPageMode+":") {
		return indexedTrashPageMode, strings.TrimPrefix(cursor, indexedTrashPageMode+":")
	}
	return indexedTrashPageMode, cursor
}

func formatTrashPageCursor(mode string, token string) string {
	token = strings.TrimSpace(token)
	if token == "" {
		return ""
	}
	return mode + ":" + token
}

func migrateLegacyTrashMetadata(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	metadatas []trashMetadata,
) {
	if len(metadatas) == 0 {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(Ctx(), 15*time.Minute)
		defer cancel()
		client := NewClient(cfg)
		for _, metadata := range metadatas {
			byTimeKey, byIDKey, err := buildTrashIndexKeys(cfg, metadata)
			if err != nil || len(byTimeKey) > maxTrashIndexKeyLength || len(byIDKey) > maxTrashIndexKeyLength {
				continue
			}
			if err := putTrashIndexObject(ctx, client, bucket, byTimeKey); err != nil {
				continue
			}
			if err := putTrashIndexObject(ctx, client, bucket, byIDKey); err != nil {
				continue
			}
			_ = deleteObjectKeyIfExists(ctx, client, bucket, trashMetadataKey(cfg, metadata.ID))
		}
	}()
}
