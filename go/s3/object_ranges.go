// Range reads back Cloud Files hydration without downloading the whole object first.
package s3

import (
	"context"
	"fmt"
	"io"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// ReadObjectRangeContext reads up to length bytes starting at offset.
func ReadObjectRangeContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	offset,
	length int64,
) ([]byte, error) {
	if offset < 0 {
		offset = 0
	}
	if length <= 0 {
		return []byte{}, nil
	}
	client := NewClient(cfg)
	input := &s3.GetObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
		Range:  aws.String(fmt.Sprintf("bytes=%d-%d", offset, offset+length-1)),
	}
	out, err := client.GetObject(ctx, input)
	if err != nil {
		return nil, normalizeNotExistError(err)
	}
	defer out.Body.Close()

	data, err := io.ReadAll(io.LimitReader(out.Body, length))
	if err != nil {
		return nil, err
	}
	return data, nil
}
