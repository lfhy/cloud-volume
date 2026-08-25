// WebDAV upload helpers own local files and shared transfer-task reporting.
package storage

import (
	"context"
	"io"
	"os"
	"path"
)

func (b webDAVBackend) UploadFile(ctx context.Context, bucket, key, localPath, taskID string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	if err := b.ensureWritableDirectory(ctx, bucket, path.Dir(cleanRemotePath(key))); err != nil {
		return err
	}
	file, err := os.Open(localPath)
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	return runTrackedUpload(
		ctx,
		bucket,
		key,
		localPath,
		file,
		info.Size(),
		taskID,
		func(uploadCtx context.Context, body io.Reader) error {
			return b.put(uploadCtx, key, body)
		},
		b.cfg.ProfileID,
	)
}

func (b webDAVBackend) UploadReader(
	ctx context.Context,
	bucket, key string,
	body io.Reader,
	size int64,
	taskID, _ string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	if err := b.ensureWritableDirectory(ctx, bucket, path.Dir(cleanRemotePath(key))); err != nil {
		return err
	}
	return runTrackedUpload(
		ctx,
		bucket,
		key,
		"",
		body,
		size,
		taskID,
		func(uploadCtx context.Context, tracked io.Reader) error {
			return b.put(uploadCtx, key, tracked)
		},
		b.cfg.ProfileID,
	)
}
