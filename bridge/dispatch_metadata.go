// Metadata bridge routes the unified inode view into the page listing path.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strconv"
	"strings"

	bucketmetadata "remote-storage/go/mount/metadata"

	storageconfig "remote-storage/go/config"
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

// listObjectPageFromMetadata routes page listing through the persistent inode
// view. Returns handled=false when the namespace cannot be acquired (missing
// ProfileID) so callers can fall back to the provider-direct path.
func listObjectPageFromMetadata(input objectPageArgs) (objectPageWire, bool, error) {
	manager, err := bucketmetadata.DefaultManager()
	if err != nil {
		log.Printf("[bridge/metadata] manager-unavailable err=%v", err)
		return objectPageWire{}, false, nil
	}
	handle, err := manager.Acquire(input.Config, input.Bucket)
	if err != nil {
		if errors.Is(err, bucketmetadata.ErrNoProfileID) {
			return objectPageWire{}, false, nil
		}
		return objectPageWire{}, true, err
	}
	defer manager.Release(handle)
	dirInode, err := resolveDirectoryInode(handle.Service, input.Prefix)
	if errors.Is(err, bucketmetadata.ErrNotFound) {
		return objectPageWire{Items: []objectInfoWire{}, NextToken: ""}, true, nil
	}
	if err != nil {
		return objectPageWire{}, true, err
	}
	page, err := handle.Service.ListPage(context.Background(), dirInode, input.NextToken, input.PageSize)
	if errors.Is(err, bucketmetadata.ErrStaleCursor) {
		return objectPageWire{}, true, staleCursorError{inner: err}
	}
	if err != nil {
		return objectPageWire{}, true, err
	}
	return objectPageAdapter(page), true, nil
}

// staleCursorError marks a stale page token so callers reload from page one.
type staleCursorError struct{ inner error }

func (e staleCursorError) Error() string { return e.inner.Error() }
func (e staleCursorError) Unwrap() error { return e.inner }

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
