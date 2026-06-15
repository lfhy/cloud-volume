// S3 backend adapts the existing S3-compatible implementation to storage.Backend.
package storage

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type s3Backend struct {
	cfg storageconfig.RemoteStorageConfig
}

// bucketConfig applies bucket-level overrides before delegating to shared S3 helpers.
func (b s3Backend) bucketConfig(bucket string) storageconfig.RemoteStorageConfig {
	return b.cfg.WithBucketSettingsApplied(bucket)
}

func (b s3Backend) ListBuckets(context.Context) ([]BucketInfo, error) {
	return s3ops.ListBuckets(b.cfg)
}

func (b s3Backend) ListObjectsPage(
	ctx context.Context,
	bucket, prefix, nextToken string,
	pageSize int32,
) (ObjectPage, error) {
	return s3ops.ListObjectsPageContext(ctx, b.bucketConfig(bucket), bucket, prefix, nextToken, pageSize)
}

func (b s3Backend) HeadObject(ctx context.Context, bucket, key string) (ObjectInfo, error) {
	return s3ops.HeadObjectContext(ctx, b.bucketConfig(bucket), bucket, key)
}

func (b s3Backend) ReadObjectRange(
	ctx context.Context,
	bucket, key string,
	offset, length int64,
) ([]byte, error) {
	return s3ops.ReadObjectRangeContext(ctx, b.bucketConfig(bucket), bucket, key, offset, length)
}

func (b s3Backend) DirectoryAccess(context.Context, string, string) (DirectoryAccess, error) {
	return DirectoryAccess{Writable: true, Known: true}, nil
}

func (b s3Backend) CreateDirectory(ctx context.Context, bucket, prefix, name string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.CreateDirectoryContext(ctx, b.bucketConfig(bucket), bucket, prefix, name)
}

func (b s3Backend) DeleteObject(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	taskID string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	cfg := b.bucketConfig(bucket)
	if !cfg.BucketSettingsFor(bucket).IsTrashEnabled() {
		return s3ops.DeleteObjectHardContextWithTask(ctx, cfg, bucket, key, isDirectory, taskID)
	}
	return s3ops.DeleteObjectContextWithTask(ctx, cfg, bucket, key, isDirectory, taskID)
}

func (b s3Backend) DeleteObjectHard(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	taskID string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.DeleteObjectHardContextWithTask(ctx, b.bucketConfig(bucket), bucket, key, isDirectory, taskID)
}

func (b s3Backend) RenameObject(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	newName string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.RenameObjectContext(ctx, b.bucketConfig(bucket), bucket, key, isDirectory, newName)
}

func (b s3Backend) CopyObject(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
	isDirectory bool,
	taskID string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.CopyObjectContext(ctx, b.bucketConfig(bucket), bucket, sourceKey, targetKey, isDirectory, taskID)
}

func (b s3Backend) MoveObject(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
	isDirectory bool,
	taskID string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.MoveObjectContextWithTask(ctx, b.bucketConfig(bucket), bucket, sourceKey, targetKey, isDirectory, taskID)
}

func (b s3Backend) UploadFile(
	ctx context.Context,
	bucket, key, localPath, taskID string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.UploadFileContextResumable(ctx, b.bucketConfig(bucket), bucket, key, localPath, taskID, 0)
}

func (b s3Backend) UploadReader(
	ctx context.Context,
	bucket, key string,
	body io.Reader,
	size int64,
	taskID, fileName string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.UploadReader(ctx, b.bucketConfig(bucket), bucket, key, body, size, taskID, fileName)
}

func (b s3Backend) ListTrashPage(ctx context.Context, bucket, nextToken string, pageSize int32) (TrashPage, error) {
	cfg := b.bucketConfig(bucket)
	if !cfg.BucketSettingsFor(bucket).IsTrashEnabled() {
		return TrashPage{Items: []TrashItem{}}, nil
	}
	return s3ops.ListTrashPageContext(ctx, cfg, bucket, nextToken, pageSize)
}

func (b s3Backend) RestoreTrashItem(ctx context.Context, bucket, trashID string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.RestoreTrashItemContext(ctx, b.bucketConfig(bucket), bucket, trashID)
}

func (b s3Backend) DeleteTrashItem(ctx context.Context, bucket, trashID string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.DeleteTrashItemContext(ctx, b.bucketConfig(bucket), bucket, trashID)
}

func (b s3Backend) ClearTrash(ctx context.Context, bucket string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.ClearTrashContext(ctx, b.bucketConfig(bucket), bucket)
}

func (b s3Backend) ensureBucketWritable(bucket string) error {
	if b.cfg.BucketSettingsFor(bucket).ReadOnly {
		return fmt.Errorf("当前存储桶已配置为只读，无法写入")
	}
	return nil
}

func (b s3Backend) DownloadFile(
	ctx context.Context,
	bucket, key, localPath, taskID string,
) error {
	return s3ops.DownloadFileContext(ctx, b.bucketConfig(bucket), bucket, key, localPath, taskID)
}

func (b s3Backend) StreamObjectToHTTP(
	ctx context.Context,
	bucket, key string,
	inline bool,
	w http.ResponseWriter,
) error {
	return s3ops.StreamObjectToHTTP(ctx, b.bucketConfig(bucket), bucket, key, inline, w)
}

func (b s3Backend) UploadFilePrefix(
	ctx context.Context,
	bucket, key, localPath string,
	info os.FileInfo,
	readySize int64,
	uploadWorkers int,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return s3ops.UploadFilePrefixContextResumable(
		ctx,
		b.bucketConfig(bucket),
		bucket,
		key,
		localPath,
		info,
		readySize,
		uploadWorkers,
	)
}
