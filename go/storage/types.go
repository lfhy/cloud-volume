// Package storage routes account operations to concrete S3 or WebDAV backends.
package storage

import (
	"context"
	"io"
	"net/http"
	"os"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type BucketInfo = s3ops.BucketInfo
type ObjectInfo = s3ops.ObjectInfo
type ObjectPage = s3ops.ObjectPage
type TrashItem = s3ops.TrashItem
type TrashPage = s3ops.TrashPage

type DirectoryAccess struct {
	Writable bool   `json:"writable"`
	Known    bool   `json:"known"`
	Reason   string `json:"reason,omitempty"`
}

type Backend interface {
	ListBuckets(context.Context) ([]BucketInfo, error)
	ListObjectsPage(context.Context, string, string, string, int32) (ObjectPage, error)
	HeadObject(context.Context, string, string) (ObjectInfo, error)
	ReadObjectRange(context.Context, string, string, int64, int64) ([]byte, error)
	DirectoryAccess(context.Context, string, string) (DirectoryAccess, error)
	CreateDirectory(context.Context, string, string, string) error
	DeleteObject(context.Context, string, string, bool, string) error
	DeleteObjectHard(context.Context, string, string, bool, string) error
	ListTrashPage(context.Context, string, string, int32) (TrashPage, error)
	RestoreTrashItem(context.Context, string, string) error
	DeleteTrashItem(context.Context, string, string) error
	ClearTrash(context.Context, string) error
	RenameObject(context.Context, string, string, bool, string) error
	CopyObject(context.Context, string, string, string, bool, string) error
	MoveObject(context.Context, string, string, string, bool, string) error
	UploadFile(context.Context, string, string, string, string) error
	UploadReader(context.Context, string, string, io.Reader, int64, string, string) error
	DownloadFile(context.Context, string, string, string, string) error
	StreamObjectToHTTP(context.Context, string, string, bool, http.ResponseWriter) error
}

// MountPrefetchPolicy lets slower backends opt out of directory preview prefetch.
type MountPrefetchPolicy interface {
	SupportsMountPrefetch() bool
}

// PartialFileUploader exposes optional prefix upload support for append-heavy mount writes.
type PartialFileUploader interface {
	UploadFilePrefix(context.Context, string, string, string, os.FileInfo, int64, int) error
}

// SupportsMountPrefetch defaults to true so existing backends keep current behavior.
func SupportsMountPrefetch(backend Backend) bool {
	policy, ok := backend.(MountPrefetchPolicy)
	if !ok {
		return true
	}
	return policy.SupportsMountPrefetch()
}

func ForConfig(cfg storageconfig.RemoteStorageConfig) Backend {
	normalized := cfg.Normalized()
	if normalized.StorageType == storageconfig.StorageTypeWebDAV {
		return NewWebDAVBackend(normalized)
	}
	if normalized.StorageType == storageconfig.StorageTypeBaiduPan {
		return newBaiduPanBackend(normalized)
	}
	return s3Backend{cfg: normalized}
}
