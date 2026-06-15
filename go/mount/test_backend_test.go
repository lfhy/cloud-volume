// Mount test backend keeps local-first queue tests off the network unless a test opts into a real backend.
package mount

import (
	"context"
	"io"
	"net/http"
	"os"

	storageops "remote-storage/go/storage"
)

type mountTestBackend struct{}

func (mountTestBackend) ListBuckets(context.Context) ([]storageops.BucketInfo, error) {
	return []storageops.BucketInfo{{Name: "test-bucket"}}, nil
}

func (mountTestBackend) ListObjectsPage(context.Context, string, string, string, int32) (storageops.ObjectPage, error) {
	return storageops.ObjectPage{Items: []storageops.ObjectInfo{}}, nil
}

func (mountTestBackend) HeadObject(context.Context, string, string) (storageops.ObjectInfo, error) {
	return storageops.ObjectInfo{}, os.ErrNotExist
}

func (mountTestBackend) ReadObjectRange(context.Context, string, string, int64, int64) ([]byte, error) {
	return []byte{}, nil
}

func (mountTestBackend) DirectoryAccess(context.Context, string, string) (storageops.DirectoryAccess, error) {
	return storageops.DirectoryAccess{Writable: true, Known: true}, nil
}

func (mountTestBackend) CreateDirectory(context.Context, string, string, string) error {
	return nil
}

func (mountTestBackend) DeleteObject(context.Context, string, string, bool, string) error {
	return nil
}

func (mountTestBackend) DeleteObjectHard(context.Context, string, string, bool, string) error {
	return nil
}

func (mountTestBackend) ListTrashPage(context.Context, string, string, int32) (storageops.TrashPage, error) {
	return storageops.TrashPage{Items: []storageops.TrashItem{}}, nil
}

func (mountTestBackend) RestoreTrashItem(context.Context, string, string) error {
	return nil
}

func (mountTestBackend) DeleteTrashItem(context.Context, string, string) error {
	return nil
}

func (mountTestBackend) ClearTrash(context.Context, string) error {
	return nil
}

func (mountTestBackend) RenameObject(context.Context, string, string, bool, string) error {
	return nil
}

func (mountTestBackend) CopyObject(context.Context, string, string, string, bool, string) error {
	return nil
}

func (mountTestBackend) MoveObject(context.Context, string, string, string, bool, string) error {
	return nil
}

func (mountTestBackend) UploadFile(context.Context, string, string, string, string) error {
	return nil
}

func (mountTestBackend) UploadReader(context.Context, string, string, io.Reader, int64, string, string) error {
	return nil
}

func (mountTestBackend) DownloadFile(context.Context, string, string, string, string) error {
	return os.ErrNotExist
}

func (mountTestBackend) StreamObjectToHTTP(context.Context, string, string, bool, http.ResponseWriter) error {
	return os.ErrNotExist
}
