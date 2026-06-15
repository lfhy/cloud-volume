// WebDAV bucket policy helpers keep readonly and trash overrides aligned with config.
package storage

import (
	"fmt"

	storageconfig "remote-storage/go/config"
)

func (b webDAVBackend) bucketConfig(bucket string) storageconfig.RemoteStorageConfig {
	return b.cfg.WithBucketSettingsApplied(bucket)
}

func (b webDAVBackend) ensureBucketWritable(bucket string) error {
	if b.bucketConfig(bucket).BucketSettingsFor(bucket).ReadOnly {
		return fmt.Errorf("当前存储桶已配置为只读，无法写入")
	}
	return nil
}

