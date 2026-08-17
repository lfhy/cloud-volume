// Metadata bridge routes the unified inode view into the page listing path.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"

	bucketmetadata "remote-storage/go/mount/metadata"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

// objectInfoWire matches the bridge ObjectInfo JSON shape shared with Dart.
type objectInfoWire struct {
	Key          string `json:"key"`
	Size         int64  `json:"size"`
	LastModified string `json:"lastModified,omitempty"`
	ETag         string `json:"etag,omitempty"`
	IsDir        bool   `json:"isDir"`
}

// objectPageWire matches the bridge ObjectPage JSON shape shared with Dart.
type objectPageWire struct {
	Items     []objectInfoWire `json:"items"`
	NextToken string           `json:"nextToken"`
}

// trimPrefixPath normalizes a listing prefix into a clean virtual path.
func trimPrefixPath(prefix string) string {
	return strings.Trim(strings.TrimSpace(prefix), "/")
}

// parseInodeString decodes the string-encoded inode id used on the wire.
func parseInodeString(value string) (uint64, error) {
	parsed, err := strconv.ParseUint(strings.TrimSpace(value), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("metadata: invalid inode %q", value)
	}
	return parsed, nil
}

// objectPageAdapter converts metadata pages into the bridge ObjectPage wire shape.
func objectPageAdapter(page bucketmetadata.Page) objectPageWire {
	items := make([]objectInfoWire, 0, len(page.Items))
	for _, item := range page.Items {
		items = append(items, objectInfoWire{
			Key:          item.Key,
			Size:         item.Size,
			LastModified: item.LastModified,
			ETag:         item.ETag,
			IsDir:        item.IsDir,
		})
	}
	return objectPageWire{Items: items, NextToken: page.NextToken}
}

func objectInfoFromMetadata(object bucketmetadata.Object) storageops.ObjectInfo {
	return storageops.ObjectInfo{
		Key: object.Key, Size: object.Size, LastModified: object.LastModified,
		ETag: object.ETag, IsDir: object.IsDir,
	}
}

func objectInfosFromWire(items []objectInfoWire) []storageops.ObjectInfo {
	infos := make([]storageops.ObjectInfo, 0, len(items))
	for _, item := range items {
		infos = append(infos, storageops.ObjectInfo{
			Key: item.Key, Size: item.Size, LastModified: item.LastModified, ETag: item.ETag, IsDir: item.IsDir,
		})
	}
	return infos
}

// resolveDirectoryInode walks ancestor materialization for a prefix path.
func resolveDirectoryInode(service *bucketmetadata.Service, prefix string) (uint64, error) {
	trimmed := trimPrefixPath(prefix)
	if trimmed == "" {
		return 1, nil
	}
	inode, err := service.StatPath(context.Background(), trimmed)
	if err != nil {
		return 0, err
	}
	if !inode.IsDir {
		return 0, fmt.Errorf("metadata: prefix %q is not a directory", prefix)
	}
	parsed, err := parseInodeString(inode.Inode)
	if err != nil {
		return 0, err
	}
	return parsed, nil
}

// metadataListFunc allows tests to substitute the manager/backend wiring.
var metadataListFunc = listObjectPageFromMetadata

func swapMetadataListFunc(next func(objectPageArgs) (objectPageWire, bool, error)) func(objectPageArgs) (objectPageWire, bool, error) {
	previous := metadataListFunc
	metadataListFunc = next
	return previous
}

// metadataListViaHandle runs the listing pipeline against an acquired handle.
func metadataListViaHandle(handle *bucketmetadata.AcquireHandle, input objectPageArgs) (objectPageWire, bool, error) {
	dirInode, err := resolveDirectoryInode(handle.Service, input.Prefix)
	if errors.Is(err, bucketmetadata.ErrNotFound) {
		return objectPageWire{Items: []objectInfoWire{}, NextToken: ""}, true, nil
	}
	if err != nil {
		return objectPageWire{}, true, err
	}
	if input.ForceRefresh {
		if err := handle.Service.MaterializeDirectory(context.Background(), dirInode); err != nil {
			return objectPageWire{}, true, err
		}
	}
	page, err := listPageWithStaleRestart(handle.Service, dirInode, input.NextToken, input.PageSize)
	if err != nil {
		return objectPageWire{}, true, err
	}
	return objectPageAdapter(page), true, nil
}

// listObjectPageFromMetadata routes page listing through the persistent inode
// view. Returns handled=false when the namespace cannot be acquired (missing
// ProfileID) so callers can fall back to the provider-direct path.
func listObjectPageFromMetadata(input objectPageArgs) (objectPageWire, bool, error) {
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		log.Printf("[bridge/metadata] manager-unavailable err=%v", err)
		if strings.TrimSpace(input.Config.ProfileID) != "" {
			return objectPageWire{}, true, err
		}
		return objectPageWire{}, false, nil
	}
	handle, err := manager.Acquire(input.Config, input.Bucket)
	if err != nil {
		if errors.Is(err, bucketmetadata.ErrNoProfileID) {
			return objectPageWire{}, false, nil
		}
		log.Printf("[bridge/metadata] acquire-failed bucket=%q err=%v", input.Bucket, err)
		return objectPageWire{}, true, err
	}
	defer manager.Release(handle)
	return metadataListViaHandle(handle, input)
}

// metadataHeadFunc allows tests to substitute the manager/backend wiring for
// stat requests, just as metadataListFunc does for paginated directories.
var metadataHeadFunc = headObjectFromMetadata

func swapMetadataHeadFunc(next func(objectHeadArgs) (storageops.ObjectInfo, bool, error)) func(objectHeadArgs) (storageops.ObjectInfo, bool, error) {
	previous := metadataHeadFunc
	metadataHeadFunc = next
	return previous
}

func headObjectFromMetadata(input objectHeadArgs) (storageops.ObjectInfo, bool, error) {
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		if strings.TrimSpace(input.Config.ProfileID) != "" {
			return storageops.ObjectInfo{}, true, err
		}
		return storageops.ObjectInfo{}, false, nil
	}
	handle, err := manager.Acquire(input.Config, input.Bucket)
	if errors.Is(err, bucketmetadata.ErrNoProfileID) {
		return storageops.ObjectInfo{}, false, nil
	}
	if err != nil {
		return storageops.ObjectInfo{}, true, err
	}
	defer manager.Release(handle)
	return metadataHeadViaHandle(handle, input)
}

func metadataHeadViaHandle(
	handle *bucketmetadata.AcquireHandle, input objectHeadArgs,
) (storageops.ObjectInfo, bool, error) {
	if handle == nil || handle.Service == nil {
		return storageops.ObjectInfo{}, true, fmt.Errorf("metadata: head handle is unavailable")
	}
	object, err := handle.Service.StatPath(context.Background(), trimPrefixPath(input.Key))
	if errors.Is(err, bucketmetadata.ErrNotFound) {
		return storageops.ObjectInfo{}, true, os.ErrNotExist
	}
	if err != nil {
		return storageops.ObjectInfo{}, true, err
	}
	return objectInfoFromMetadata(object), true, nil
}

// listPageWithStaleRestart transparently restarts pagination from page one
// when the directory revision changed under the caller's token; until the
// Dart side learns to reload on stale cursors this degrades to a reload.
func listPageWithStaleRestart(service *bucketmetadata.Service, dirInode uint64, token string, pageSize int32) (bucketmetadata.Page, error) {
	page, err := service.ListPage(context.Background(), dirInode, token, pageSize)
	if errors.Is(err, bucketmetadata.ErrStaleCursor) {
		return service.ListPage(context.Background(), dirInode, "", pageSize)
	}
	return page, err
}

// staleCursorError marks a stale page token so callers reload from page one.
type staleCursorError struct{ inner error }

func (e staleCursorError) Error() string { return e.inner.Error() }
func (e staleCursorError) Unwrap() error { return e.inner }

var _ = staleCursorError{} // retained for future Dart-side stale-cursor signaling

// metadataStatusArgs mirror the page-listing config shape for diagnostics.
type metadataStatusArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
}

// metadataNamespaceStatus exposes per-namespace worker diagnostics.
func metadataNamespaceStatus(args json.RawMessage) (any, error) {
	var input metadataStatusArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		return nil, err
	}
	handle, err := manager.Acquire(input.Config, input.Bucket)
	if err != nil {
		return nil, err
	}
	defer manager.Release(handle)
	return handle.Service.Status(), nil
}
