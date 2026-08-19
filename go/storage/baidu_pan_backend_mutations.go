// Baidu Pan mutation methods keep provider calls and task projection together.
package storage

import (
	"context"
	"strings"

	xpanclient "github.com/lfhy/xpan/client"
)

func (b baiduPanBackend) DeleteObject(
	ctx context.Context,
	bucket, key string,
	_ bool,
	taskID string,
) error {
	return runTrackedMutation(
		ctx, "delete", bucket, key, "", taskID, b.cfg.ProfileID,
		func(context.Context) error {
			if err := b.ensureBucketWritable(bucket); err != nil {
				return err
			}
			_, err := withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
				_, err := client.DeleteObject(baiduPanObjectPath(key))
				if err == nil {
					forgetBaiduPanFsid(b.bucketConfig(bucket), bucket, key)
					forgetBaiduPanKnownDir(baiduPanObjectPath(key))
				}
				return struct{}{}, err
			})
			return err
		},
	)
}

func (b baiduPanBackend) DeleteObjectHard(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	taskID string,
) error {
	return b.DeleteObject(ctx, bucket, key, isDirectory, taskID)
}

func (b baiduPanBackend) RenameObject(
	_ context.Context,
	bucket, key string,
	_ bool,
	newName string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	_, err := withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
		_, err := client.RenameObject(
			baiduPanObjectPath(key),
			strings.Trim(strings.TrimSpace(newName), "/"),
		)
		return struct{}{}, err
	})
	return err
}

func (b baiduPanBackend) CopyObject(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
	_ bool,
	taskID string,
) error {
	return runTrackedMutation(
		ctx, "copy", bucket, sourceKey, targetKey, taskID, b.cfg.ProfileID,
		func(context.Context) error {
			if err := b.ensureBucketWritable(bucket); err != nil {
				return err
			}
			destDir, newName := baiduPanMoveTarget(targetKey)
			_, err := withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
				if err := ensureBaiduPanDir(client, destDir); err != nil {
					return struct{}{}, err
				}
				_, err := client.CopyObject(baiduPanObjectPath(sourceKey), destDir, newName)
				return struct{}{}, err
			})
			return err
		},
	)
}

func (b baiduPanBackend) MoveObject(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
	_ bool,
	taskID string,
) error {
	return runTrackedMutation(
		ctx, "move", bucket, sourceKey, targetKey, taskID, b.cfg.ProfileID,
		func(context.Context) error {
			if err := b.ensureBucketWritable(bucket); err != nil {
				return err
			}
			destDir, newName := baiduPanMoveTarget(targetKey)
			_, err := withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
				if err := ensureBaiduPanDir(client, destDir); err != nil {
					return struct{}{}, err
				}
				_, err := client.MoveObject(baiduPanObjectPath(sourceKey), destDir, newName)
				return struct{}{}, err
			})
			return err
		},
	)
}
