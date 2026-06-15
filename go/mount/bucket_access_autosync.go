// Bucket access autosync helpers bridge Linux sequential write detection to resumable multipart uploads.
package mount

import (
	"context"
	"os"

	storageops "remote-storage/go/storage"
)

func (a *bucketAccess) uploadPartialPrefix(
	ctx context.Context,
	virtualPath,
	localPath string,
	info os.FileInfo,
	readySize int64,
) error {
	if a == nil || readySize <= 0 {
		return nil
	}
	uploader, ok := a.backend.(storageops.PartialFileUploader)
	if !ok {
		return nil
	}
	return uploader.UploadFilePrefix(
		ctx,
		a.bucket,
		a.remoteKey(virtualPath),
		localPath,
		info,
		readySize,
		a.uploadWorkers,
	)
}
