//go:build windows && cgo

// Cloud Files readers let one sync-root shell compare direct remote reads with cached reads.
package mount

import (
	"context"
	"fmt"

	storageconfig "remote-storage/go/config"
)

type cloudFilesReader interface {
	Read(ctx context.Context, virtualPath string, offset, length int64) ([]byte, error)
}

type directCloudFilesReader struct {
	access *bucketAccess
}

type cachedCloudFilesReader struct {
	access *bucketAccess
}

func newCloudFilesReader(mode string, access *bucketAccess) (cloudFilesReader, error) {
	switch mode {
	case storageconfig.WindowsMountModeCloudFilesDirect:
		return &directCloudFilesReader{access: access}, nil
	case storageconfig.WindowsMountModeCloudFilesCached:
		return &cachedCloudFilesReader{access: access}, nil
	default:
		return nil, fmt.Errorf("unsupported Cloud Files reader mode %q", mode)
	}
}

func (r *directCloudFilesReader) Read(
	ctx context.Context,
	virtualPath string,
	offset,
	length int64,
) ([]byte, error) {
	return r.access.readRemoteRange(ctx, virtualPath, offset, length)
}

func (r *cachedCloudFilesReader) Read(
	ctx context.Context,
	virtualPath string,
	offset,
	length int64,
) ([]byte, error) {
	return r.access.readCachedRange(ctx, virtualPath, offset, length)
}
