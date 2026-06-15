// Bucket access checks give CLI and bootstrap flows a fast way to validate config.
package s3

import (
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// CheckAccess validates endpoint and credentials without requiring a bucket.
func CheckAccess(cfg storageconfig.RemoteStorageConfig) error {
	client := NewClient(cfg)
	_, err := client.ListBuckets(Ctx(), &awss3.ListBucketsInput{})
	return err
}

// CheckBucketAccess validates that the configured credentials can reach the target bucket.
func CheckBucketAccess(cfg storageconfig.RemoteStorageConfig, bucket string) error {
	trimmed := strings.TrimSpace(bucket)
	if trimmed == "" {
		return CheckAccess(cfg)
	}

	client := NewClient(cfg)
	_, err := client.HeadBucket(Ctx(), &awss3.HeadBucketInput{
		Bucket: aws.String(trimmed),
	})
	return err
}
