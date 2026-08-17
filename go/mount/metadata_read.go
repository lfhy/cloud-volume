// Metadata read adapter projects persistent inode objects into mount object views.
package mount

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"strconv"

	"remote-storage/go/mount/metadata"
	s3ops "remote-storage/go/s3"
)

// metadataMountObject retains the metadata-only identity fields alongside the
// legacy ObjectInfo shape until platform adapters project stable OIDs in M5.
type metadataMountObject struct {
	info     s3ops.ObjectInfo
	inode    uint64
	revision uint64
	state    metadata.State
}

func (a *bucketAccess) metadataService() *metadata.Service {
	if a == nil || a.metadataHandle == nil {
		return nil
	}
	return a.metadataHandle.Service
}

func (a *bucketAccess) metadataDirectory(
	ctx context.Context,
	virtualPrefix string,
	refresh bool,
) ([]metadataMountObject, error) {
	service := a.metadataService()
	if service == nil {
		return nil, nil
	}
	var (
		objects []metadata.Object
		err     error
	)
	if refresh {
		objects, err = service.RefreshDirectory(ctx, cleanVirtualPath(virtualPrefix))
	} else {
		objects, err = service.ListDirectory(ctx, cleanVirtualPath(virtualPrefix))
	}
	if err != nil {
		return nil, metadataMountReadError(err)
	}
	items := make([]metadataMountObject, 0, len(objects))
	for _, object := range objects {
		item, err := metadataMountObjectFrom(object)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, nil
}

func (a *bucketAccess) metadataStat(
	ctx context.Context,
	virtualPath string,
) (metadataMountObject, error) {
	service := a.metadataService()
	if service == nil {
		return metadataMountObject{}, os.ErrNotExist
	}
	object, err := service.StatPath(ctx, cleanVirtualPath(virtualPath))
	if err != nil {
		return metadataMountObject{}, metadataMountReadError(err)
	}
	return metadataMountObjectFrom(object)
}

func metadataMountObjectFrom(object metadata.Object) (metadataMountObject, error) {
	inode, err := strconv.ParseUint(object.Inode, 10, 64)
	if err != nil || inode == 0 {
		return metadataMountObject{}, fmt.Errorf("invalid metadata inode %q", object.Inode)
	}
	revision, err := strconv.ParseUint(object.Revision, 10, 64)
	if err != nil {
		return metadataMountObject{}, fmt.Errorf("invalid metadata revision %q", object.Revision)
	}
	return metadataMountObject{
		info: s3ops.ObjectInfo{
			Key:          object.Key,
			IsDir:        object.IsDir,
			Size:         object.Size,
			LastModified: object.LastModified,
			ETag:         object.ETag,
		},
		inode: inode, revision: revision, state: object.State,
	}, nil
}

func metadataMountReadError(err error) error {
	if errors.Is(err, metadata.ErrNotFound) {
		return os.ErrNotExist
	}
	return err
}

func metadataObjectInfos(items []metadataMountObject) []s3ops.ObjectInfo {
	infos := make([]s3ops.ObjectInfo, 0, len(items))
	for _, item := range items {
		infos = append(infos, item.info)
	}
	return infos
}

func (a *bucketAccess) listMetadataDirectory(
	ctx context.Context,
	virtualPrefix string,
	allowPrefetch bool,
) ([]s3ops.ObjectInfo, error) {
	items, err := a.metadataDirectory(ctx, virtualPrefix, false)
	if err != nil {
		return nil, err
	}
	merged := a.filterTrashItems(
		a.mergeOverlayItems(
			virtualPrefix,
			a.cache.mergeLocalFiles(virtualPrefix, metadataObjectInfos(items)),
		),
	)
	if allowPrefetch {
		a.prefetchMetadataChildren(items)
	}
	return cloneObjects(merged), nil
}

func (a *bucketAccess) prefetchMetadataChildren(items []metadataMountObject) {
	if a == nil || !a.allowPrefetch || a.metadataService() == nil {
		return
	}
	prefetched := 0
	for _, item := range items {
		if !item.info.IsDir || prefetched >= maxPrefetchChildrenPerDirectory {
			continue
		}
		prefix := cleanVirtualPath(item.info.Key)
		if !a.cache.shouldPrefetch(prefix) {
			continue
		}
		prefetched++
		go func(path string) {
			ctx, cancel := context.WithTimeout(context.Background(), a.requestTimeout)
			defer cancel()
			if _, err := a.metadataDirectory(ctx, path, false); err != nil {
				logMetadataPrefetchError(path, err)
			}
		}(prefix)
	}
}

func logMetadataPrefetchError(prefix string, err error) {
	if err != nil {
		log.Printf("[mount/prefetch] metadata-preview-error prefix=%q err=%v", prefix, err)
	}
}
