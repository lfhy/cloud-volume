// Bucket listing operations.

package s3

import (
	"context"
	"log"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

const bucketListTimeout = 15 * time.Second

// BucketInfo holds bucket metadata returned to the Flutter layer.
type BucketInfo struct {
	Name string `json:"name"`
}

// ListBuckets returns all buckets accessible by the configured credentials.
func ListBuckets(cfg storageconfig.RemoteStorageConfig) ([]BucketInfo, error) {
	client := NewClient(cfg)
	ctx, cancel := context.WithTimeout(Ctx(), bucketListTimeout)
	defer cancel()
	startedAt := time.Now()
	log.Printf("[s3/buckets] start")
	out, err := client.ListBuckets(ctx, &s3.ListBucketsInput{})
	if err != nil {
		log.Printf("[s3/buckets] error duration=%s err=%v", time.Since(startedAt).Round(time.Millisecond), err)
		return nil, err
	}

	var result []BucketInfo
	for _, b := range out.Buckets {
		result = append(result, BucketInfo{Name: *b.Name})
	}
	if result == nil {
		result = []BucketInfo{}
	}
	log.Printf("[s3/buckets] done duration=%s count=%d", time.Since(startedAt).Round(time.Millisecond), len(result))
	return result, nil
}
