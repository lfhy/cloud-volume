// Baidu Pan backend I/O helpers keep upload/download logic and progress wiring out of the core router.
package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	xpanclient "github.com/lfhy/xpan/client"
	xpanfile "github.com/lfhy/xpan/file"
	xpantypes "github.com/lfhy/xpan/types"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

func (b baiduPanBackend) UploadFile(
	ctx context.Context,
	bucket string,
	key string,
	localPath string,
	taskID string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	file, err := os.Open(localPath)
	if err != nil {
		return fmt.Errorf("open local file: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return fmt.Errorf("stat local file: %w", err)
	}
	return b.uploadReaderInternal(ctx, bucket, key, file, info.Size(), taskID, path.Base(localPath), localPath)
}

func (b baiduPanBackend) UploadReader(
	ctx context.Context,
	bucket string,
	key string,
	body io.Reader,
	size int64,
	taskID string,
	fileName string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return b.uploadReaderInternal(ctx, bucket, key, body, size, taskID, fileName, "")
}

func (b baiduPanBackend) DownloadFile(
	ctx context.Context,
	bucket string,
	key string,
	localPath string,
	taskID string,
) error {
	if ctx == nil {
		ctx = context.Background()
	}
	info, err := b.HeadObject(ctx, bucket, key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return err
	}
	out, err := os.Create(localPath)
	if err != nil {
		return err
	}
	defer out.Close()
	var finishErr error
	if taskID != "" {
		var cancel context.CancelFunc
		ctx, cancel = context.WithCancel(ctx)
		s3ops.StartQueuedTransfer(taskID, "download", bucket, key, localPath, info.Size, cancel)
		defer func() { s3ops.FinishQueuedTransfer(taskID, finishErr) }()
	}
	cfg := b.bucketConfig(bucket)
	_, finishErr = withBaiduPanClient(cfg, func(client *xpanclient.Client) (int64, error) {
		reader, err := baiduPanOpenObjectReader(client, cfg, bucket, key)
		if err != nil {
			return 0, err
		}
		defer reader.Close()
		return io.Copy(out, &baiduPanDownloadReader{
			ctx:    ctx,
			reader: reader,
			taskID: taskID,
		})
	})
	return finishErr
}

func (b baiduPanBackend) StreamObjectToHTTP(
	ctx context.Context,
	bucket string,
	key string,
	_ bool,
	w http.ResponseWriter,
) error {
	if ctx == nil {
		ctx = context.Background()
	}
	cfg := b.bucketConfig(bucket)
	_, err := withBaiduPanClient(cfg, func(client *xpanclient.Client) (int64, error) {
		reader, err := baiduPanOpenObjectReader(client, cfg, bucket, key)
		if err != nil {
			return 0, err
		}
		defer reader.Close()
		return io.Copy(w, reader)
	})
	return err
}

func baiduPanOpenObjectReader(
	client *xpanclient.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	key string,
) (io.ReadCloser, error) {
	clean := baiduPanCleanKey(key)
	meta, err := baiduPanStatObject(client, cfg, bucket, clean)
	if err != nil {
		return nil, err
	}
	return xpanfile.Download(meta.Dlink)
}

func baiduPanStatObjectByPath(
	client *xpanclient.Client,
	remotePath string,
) (*xpanfile.FilemetasItem, error) {
	found, err := baiduPanListItemByPath(client, remotePath)
	if err != nil {
		return nil, err
	}
	if found == nil {
		return nil, errors.New("file not found")
	}
	return client.StatObjectUseFsId(found.FsId)
}

func baiduPanListItemByPath(
	client *xpanclient.Client,
	remotePath string,
) (*xpanfile.ListItem, error) {
	cleanPath := baiduPanObjectPath(remotePath)
	parentDir := path.Dir(cleanPath)
	startedAt := time.Now()
	start := 0
	for {
		res, err := listBaiduPanObjectsWithRetry(client, parentDir, &xpanfile.ListAllReq{
			Start: start,
			Limit: 1000,
			Order: xpantypes.ListOrderName,
		}, startedAt)
		if err != nil {
			return nil, err
		}
		for _, item := range res.List {
			if baiduPanObjectPath(item.Path) == cleanPath {
				return item, nil
			}
		}
		if res.HasMore != xpantypes.BoolIntTrue {
			return nil, nil
		}
		start = res.Cursor
	}
}

func (b baiduPanBackend) uploadReaderInternal(
	ctx context.Context,
	bucket string,
	key string,
	body io.Reader,
	size int64,
	taskID string,
	fileName string,
	localPath string,
) error {
	cleanKey := baiduPanCleanKey(key)
	if cleanKey == "" {
		return fmt.Errorf("upload key is required")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if taskID != "" {
		var cancel context.CancelFunc
		ctx, cancel = context.WithCancel(ctx)
		s3ops.StartQueuedTransfer(taskID, "upload", bucket, cleanKey, localPath, size, cancel)
	}
	tracked := body
	if taskID != "" {
		tracked = &baiduPanProgressReader{
			ctx:    ctx,
			reader: body,
			taskID: taskID,
		}
	}
	destDir, newName := baiduPanMoveTarget(cleanKey)
	tempName := baiduPanTempUploadPath(fileName, cleanKey)
	var opErr error
	_, opErr = withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
		if err := ensureBaiduPanDir(client, baiduPanUploadRoot); err != nil {
			return struct{}{}, err
		}
		if err := ensureBaiduPanDir(client, destDir); err != nil {
			return struct{}{}, err
		}
		if _, err := client.PutObject(tempName, tracked); err != nil {
			return struct{}{}, err
		}
		_, err := client.MoveObject(tempName, destDir, newName)
		return struct{}{}, err
	})
	if taskID != "" {
		s3ops.FinishQueuedTransfer(taskID, opErr)
	}
	return opErr
}

func (b baiduPanBackend) readObjectRange(
	ctx context.Context,
	bucket string,
	key string,
	offset, length int64,
) ([]byte, error) {
	if length <= 0 {
		return []byte{}, nil
	}
	if offset < 0 {
		offset = 0
	}
	if ctx == nil {
		ctx = context.Background()
	}
	_, err := b.HeadObject(ctx, bucket, key)
	if err != nil {
		return nil, err
	}
	cfg := b.bucketConfig(bucket)
	return withBaiduPanClient(cfg, func(client *xpanclient.Client) ([]byte, error) {
		reader, err := baiduPanOpenObjectReader(client, cfg, bucket, key)
		if err != nil {
			return nil, err
		}
		defer reader.Close()
		if offset > 0 {
			if _, err := io.CopyN(io.Discard, reader, offset); err != nil {
				if err == io.EOF {
					return []byte{}, nil
				}
				return nil, err
			}
		}
		return io.ReadAll(io.LimitReader(reader, length))
	})
}

type baiduPanProgressReader struct {
	ctx    context.Context
	reader io.Reader
	taskID string
}

func (r *baiduPanProgressReader) Read(p []byte) (int, error) {
	if r.ctx != nil {
		if err := r.ctx.Err(); err != nil {
			return 0, err
		}
	}
	n, err := r.reader.Read(p)
	if n > 0 && strings.TrimSpace(r.taskID) != "" {
		s3ops.AdvanceTransfer(r.taskID, int64(n))
	}
	return n, err
}

type baiduPanDownloadReader struct {
	ctx    context.Context
	reader io.Reader
	taskID string
}

func (r *baiduPanDownloadReader) Read(p []byte) (int, error) {
	if r.ctx != nil {
		if err := r.ctx.Err(); err != nil {
			return 0, err
		}
	}
	n, err := r.reader.Read(p)
	if n > 0 && strings.TrimSpace(r.taskID) != "" {
		s3ops.AdvanceTransfer(r.taskID, int64(n))
	}
	return n, err
}
