// Baidu Pan backend adapts xpan into the app's single-bucket storage contract.
package storage

import (
	"context"
	"fmt"
	"log"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	xpanclient "github.com/lfhy/xpan/client"
	xpanfile "github.com/lfhy/xpan/file"
	xpantypes "github.com/lfhy/xpan/types"

	storageconfig "remote-storage/go/config"
)

type baiduPanBackend struct {
	cfg storageconfig.RemoteStorageConfig
}

func newBaiduPanBackend(cfg storageconfig.RemoteStorageConfig) Backend {
	return baiduPanBackend{cfg: cfg.Normalized()}
}

// SupportsMountPrefetch disables directory preview prefetch to avoid Baidu Pan rate limits.
func (b baiduPanBackend) SupportsMountPrefetch() bool {
	return false
}

// DirectoryUploadConcurrency keeps Baidu Pan directory uploads modest but not serial.
func (b baiduPanBackend) DirectoryUploadConcurrency() int {
	return 2
}

// DirectoryUploadRetryDelay retries per-file failures that often come from transient RPM limits.
func (b baiduPanBackend) DirectoryUploadRetryDelay(err error, attempt int) (time.Duration, bool) {
	if err == nil || attempt >= len(baiduPanThrottleRetryDelays) {
		return 0, false
	}
	return baiduPanThrottleRetryDelays[attempt], true
}

func (b baiduPanBackend) bucketConfig(bucket string) storageconfig.RemoteStorageConfig {
	return b.cfg.WithBucketSettingsApplied(bucket)
}

func (b baiduPanBackend) ListBuckets(context.Context) ([]BucketInfo, error) {
	return []BucketInfo{{Name: baiduPanBucketLabel(b.cfg)}}, nil
}

func (b baiduPanBackend) ListObjectsPage(
	_ context.Context,
	bucket string,
	prefix string,
	nextToken string,
	pageSize int32,
) (ObjectPage, error) {
	startedAt := time.Now()
	start := 0
	if strings.TrimSpace(nextToken) != "" {
		parsed, err := strconv.Atoi(strings.TrimSpace(nextToken))
		if err != nil {
			return ObjectPage{}, fmt.Errorf("invalid next token: %w", err)
		}
		start = parsed
	}
	if pageSize <= 0 {
		pageSize = 200
	}
	remoteDir := baiduPanDirectoryPath(prefix)
	return withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (ObjectPage, error) {
		res, err := listBaiduPanObjectsWithRetry(client, remoteDir, &xpanfile.ListAllReq{
			Start: start,
			Limit: int(pageSize),
			Order: xpantypes.ListOrderName,
		}, startedAt)
		if err != nil {
			log.Printf(
				"[storage/baidu-pan] list error bucket=%q prefix=%q remote_dir=%q start=%d next_token=%q duration=%s err=%v",
				bucket,
				strings.TrimSpace(prefix),
				remoteDir,
				start,
				strings.TrimSpace(nextToken),
				time.Since(startedAt).Round(time.Millisecond),
				err,
			)
			return ObjectPage{}, err
		}
		items := make([]ObjectInfo, 0, len(res.List))
		cfg := b.bucketConfig(bucket)
		for _, item := range res.List {
			if baiduPanListItemIsSelf(remoteDir, item) {
				continue
			}
			info := baiduPanObjectInfo(remoteDir, item)
			rememberBaiduPanFsid(cfg, bucket, info.Key, item.FsId)
			items = append(items, info)
		}
		page := ObjectPage{Items: items}
		if res.HasMore == xpantypes.BoolIntTrue {
			page.NextToken = strconv.Itoa(res.Cursor)
		}
		return page, nil
	})
}

func (b baiduPanBackend) ListObjectsRecursive(
	ctx context.Context,
	bucket, prefix string,
) ([]ObjectInfo, error) {
	out := make([]ObjectInfo, 0, 64)
	queue := []string{strings.Trim(strings.TrimSpace(prefix), "/")}
	if len(queue) == 0 || queue[0] == "" {
		queue = []string{""}
	}
	seen := map[string]struct{}{}
	for len(queue) > 0 {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		dir := queue[0]
		queue = queue[1:]
		if _, ok := seen[dir]; ok {
			continue
		}
		seen[dir] = struct{}{}
		token := ""
		for {
			page, err := b.ListObjectsPage(ctx, bucket, dir, token, 200)
			if err != nil {
				return nil, err
			}
			for _, item := range page.Items {
				if item.IsDir {
					child := strings.Trim(strings.TrimSuffix(item.Key, "/"), "/")
					queue = append(queue, child)
					continue
				}
				out = append(out, item)
			}
			if page.NextToken == "" {
				break
			}
			token = page.NextToken
		}
	}
	return out, nil
}

func listBaiduPanObjectsWithRetry(
	client *xpanclient.Client,
	remoteDir string,
	req *xpanfile.ListAllReq,
	startedAt time.Time,
) (*xpanfile.ListRes, error) {
	var lastErr error
	for attempt := 0; attempt <= baiduPanThrottleRetryCount; attempt++ {
		res, err := client.ListObjects(remoteDir, req)
		if err == nil || !isBaiduPanThrottleError(err) {
			return res, err
		}
		lastErr = err
		if attempt == baiduPanThrottleRetryCount {
			return nil, err
		}
		delay := baiduPanThrottleRetryDelay(nil, attempt)
		log.Printf(
			"[storage/baidu-pan] list throttled remote_dir=%q attempt=%d sleep=%s elapsed=%s err=%v",
			remoteDir,
			attempt+1,
			delay,
			time.Since(startedAt).Round(time.Millisecond),
			err,
		)
		time.Sleep(delay)
	}
	return nil, lastErr
}

func (b baiduPanBackend) HeadObject(
	_ context.Context,
	bucket string,
	key string,
) (ObjectInfo, error) {
	clean := baiduPanCleanKey(key)
	if clean == "" {
		return ObjectInfo{Key: "", IsDir: true}, nil
	}
	cfg := b.bucketConfig(bucket)
	return withBaiduPanClient(cfg, func(client *xpanclient.Client) (ObjectInfo, error) {
		meta, err := baiduPanStatObject(client, cfg, bucket, clean)
		if err != nil {
			return ObjectInfo{}, err
		}
		return baiduPanObjectInfoFromMeta(clean, meta), nil
	})
}

func (b baiduPanBackend) ReadObjectRange(
	ctx context.Context,
	bucket string,
	key string,
	offset, length int64,
) ([]byte, error) {
	return b.readObjectRange(ctx, bucket, key, offset, length)
}

func (b baiduPanBackend) DirectoryAccess(
	_ context.Context,
	bucket string,
	_ string,
) (DirectoryAccess, error) {
	return DirectoryAccess{
		Writable: !b.bucketConfig(bucket).BucketSettingsFor(bucket).ReadOnly,
		Known:    true,
	}, nil
}

func (b baiduPanBackend) CreateDirectory(
	_ context.Context,
	bucket string,
	prefix string,
	name string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	remotePath := baiduPanObjectPath(path.Join(baiduPanCleanKey(prefix), strings.Trim(strings.TrimSpace(name), "/")))
	_, err := withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
		return struct{}{}, ensureBaiduPanDir(client, remotePath)
	})
	return err
}

func (b baiduPanBackend) ListTrashPage(
	_ context.Context,
	_ string,
	_ string,
	_ int32,
) (TrashPage, error) {
	return TrashPage{Items: []TrashItem{}}, nil
}

func (b baiduPanBackend) RestoreTrashItem(_ context.Context, _, _ string) error {
	return fmt.Errorf("百度网盘账号暂不支持应用级回收站恢复")
}

func (b baiduPanBackend) DeleteTrashItem(_ context.Context, _, _ string) error {
	return fmt.Errorf("百度网盘账号暂不支持应用级回收站删除")
}

func (b baiduPanBackend) ClearTrash(_ context.Context, _ string) error {
	return fmt.Errorf("百度网盘账号暂不支持应用级回收站清空")
}

func (b baiduPanBackend) ensureBucketWritable(bucket string) error {
	if b.bucketConfig(bucket).BucketSettingsFor(bucket).ReadOnly {
		return fmt.Errorf("当前存储桶已配置为只读，无法写入")
	}
	return nil
}

func baiduPanObjectInfo(parentDir string, item *xpanfile.ListItem) ObjectInfo {
	isDir := item.IsDir == xpantypes.BoolIntTrue
	key := baiduPanListItemKey(parentDir, item)
	if isDir && key != "" && !strings.HasSuffix(key, "/") {
		key += "/"
	}
	return ObjectInfo{
		Key:          key,
		Size:         int64(item.Size),
		LastModified: item.ServerMtime.String(),
		IsDir:        isDir,
	}
}

func baiduPanListItemIsSelf(parentDir string, item *xpanfile.ListItem) bool {
	return baiduPanCleanKey(item.Path) == baiduPanCleanKey(parentDir)
}

func baiduPanListItemKey(parentDir string, item *xpanfile.ListItem) string {
	if key := baiduPanCleanKey(item.Path); key != "" {
		return key
	}
	name := strings.Trim(strings.TrimSpace(item.Name), "/")
	if name == "" {
		return ""
	}
	return baiduPanCleanKey(path.Join(baiduPanDirectoryPath(parentDir), name))
}

func baiduPanObjectInfoFromMeta(
	key string,
	meta *xpanfile.FilemetasItem,
) ObjectInfo {
	isDir := meta.IsDir == xpantypes.BoolIntTrue
	clean := baiduPanCleanKey(key)
	if isDir && clean != "" && !strings.HasSuffix(clean, "/") {
		clean += "/"
	}
	return ObjectInfo{
		Key:          clean,
		Size:         int64(meta.Size),
		LastModified: meta.ServerMtime.String(),
		IsDir:        isDir,
	}
}

func baiduPanDirectoryPath(prefix string) string {
	clean := baiduPanCleanKey(prefix)
	if clean == "" {
		return "/"
	}
	return "/" + strings.TrimSuffix(clean, "/")
}

func baiduPanObjectPath(key string) string {
	clean := baiduPanCleanKey(key)
	if clean == "" {
		return "/"
	}
	return "/" + clean
}

func baiduPanCleanKey(key string) string {
	trimmed := strings.TrimSpace(key)
	if trimmed == "" || trimmed == "/" {
		return ""
	}
	clean := path.Clean("/" + strings.Trim(trimmed, "/"))
	if clean == "/" || clean == "." {
		return ""
	}
	return strings.TrimPrefix(clean, "/")
}

func baiduPanMoveTarget(targetKey string) (destDir string, newName string) {
	remotePath := baiduPanObjectPath(targetKey)
	clean := strings.TrimSuffix(remotePath, "/")
	return path.Dir(clean), path.Base(clean)
}

func baiduPanTempUploadPath(fileName string, key string) string {
	base := strings.TrimSpace(fileName)
	if base == "" {
		base = path.Base(baiduPanObjectPath(key))
	}
	base = strings.TrimSpace(base)
	if base == "" || base == "." || base == "/" {
		base = "upload.bin"
	}
	return baiduPanUploadRoot + "/" + uuid.NewString() + "-" + base
}
