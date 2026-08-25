// HTTP streaming helpers expose browser-friendly upload and download primitives.
package s3

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"path"
	"strconv"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// UploadReader uploads a browser-provided file stream directly into the target bucket.
func UploadReader(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	body io.Reader,
	size int64,
	taskID string,
	fileName string,
) (err error) {
	client := NewClient(cfg)
	if ctx == nil {
		ctx = Ctx()
	}
	if taskID != "" {
		var cancel context.CancelFunc
		ctx, cancel = context.WithCancel(ctx)
		startTransfer(taskID, "upload", bucket, key, fileName, size, cancel)
		SetTransferProfile(taskID, cfg.ProfileID)
		defer func() { finishTransfer(taskID, err) }()
	}
	reader := io.Reader(body)
	if taskID != "" {
		reader = &contextReader{
			ctx:    ctx,
			reader: body,
			onRead: func(n int) { advanceTransfer(taskID, int64(n)) },
		}
	}
	_, err = client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:        &bucket,
		Key:           &key,
		Body:          reader,
		ContentLength: aws.Int64(size),
	})
	return err
}

// StreamObjectToHTTP copies one object directly into an HTTP response writer.
func StreamObjectToHTTP(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	inline bool,
	writer http.ResponseWriter,
) error {
	client := NewClient(cfg)
	if ctx == nil {
		ctx = Ctx()
	}
	result, err := client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: &bucket,
		Key:    &key,
	})
	if err != nil {
		return normalizeNotExistError(err)
	}
	defer result.Body.Close()

	if result.ContentType != nil && strings.TrimSpace(*result.ContentType) != "" {
		writer.Header().Set("Content-Type", *result.ContentType)
	} else {
		writer.Header().Set("Content-Type", "application/octet-stream")
	}
	if result.ContentLength != nil && *result.ContentLength >= 0 {
		writer.Header().Set("Content-Length", strconv.FormatInt(*result.ContentLength, 10))
	}
	dispositionType := "attachment"
	if inline {
		dispositionType = "inline"
	}
	writer.Header().Set(
		"Content-Disposition",
		fmt.Sprintf(`%s; filename="%s"`, dispositionType, sanitizeDispositionName(key)),
	)
	_, err = io.Copy(writer, result.Body)
	return err
}

func sanitizeDispositionName(key string) string {
	name := path.Base(strings.Trim(strings.TrimSpace(key), "/"))
	if name == "" || name == "." || name == "/" {
		return "download"
	}
	return strings.NewReplacer(`"`, `'`, "\n", "_", "\r", "_").Replace(name)
}
