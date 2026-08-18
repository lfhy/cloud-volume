// Metadata-backed mount reads consume page-owned pending chunks before remote bytes.
package mount

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"remote-storage/go/mount/metadata"
)

func metadataPendingState(state metadata.State) bool {
	return state == metadata.StatePending || state == metadata.StateConflict
}

func (a *bucketAccess) readMetadataPendingRange(
	ctx context.Context,
	item metadataMountObject,
	offset, length int64,
) ([]byte, bool, error) {
	if a == nil || a.metadataService() == nil || item.inode == 0 || !metadataPendingState(item.state) {
		return nil, false, nil
	}
	return a.metadataService().ReadPendingRange(ctx, item.inode, offset, length)
}

// materializeMetadataPendingFile creates the ordinary mount cache file for
// FUSE/WinFsp handles, while preserving the chunks as the durable source.
func (a *bucketAccess) materializeMetadataPendingFile(
	ctx context.Context,
	virtualPath, localPath string,
	item metadataMountObject,
) (string, metadataMountObject, bool, error) {
	if a == nil || a.metadataService() == nil || item.inode == 0 || !metadataPendingState(item.state) {
		return "", metadataMountObject{}, false, nil
	}
	key := "metadata-pending:" + cleanVirtualPath(virtualPath)
	value, err, _ := a.group.Do(key, func() (any, error) {
		current := item
		for attempt := 0; attempt < 2; attempt++ {
			if !metadataPendingState(current.state) || current.contentGeneration == 0 {
				return pendingMaterializationResult{}, nil
			}
			if matchesPendingDownloadStamp(localPath, current.info, current.inode, current.contentGeneration) {
				return pendingMaterializationResult{path: localPath, item: current, handled: true}, nil
			}
			path, handled, copyErr := a.materializeMetadataPendingFileOnce(ctx, localPath, current)
			if copyErr != nil || !handled {
				return pendingMaterializationResult{path: path, item: current, handled: handled}, copyErr
			}
			latest, statErr := a.metadataStat(ctx, virtualPath)
			if statErr != nil {
				return pendingMaterializationResult{}, statErr
			}
			if latest.inode == current.inode && latest.contentGeneration == current.contentGeneration {
				return pendingMaterializationResult{path: path, item: latest, handled: true}, nil
			}
			current = latest
		}
		return pendingMaterializationResult{}, fmt.Errorf("metadata pending content changed during materialization")
	})
	if err != nil {
		return "", metadataMountObject{}, true, err
	}
	result, ok := value.(pendingMaterializationResult)
	if !ok {
		return "", metadataMountObject{}, false, nil
	}
	return result.path, result.item, result.handled, nil
}

type pendingMaterializationResult struct {
	path    string
	item    metadataMountObject
	handled bool
}

func (a *bucketAccess) materializeMetadataPendingFileOnce(
	ctx context.Context,
	localPath string,
	item metadataMountObject,
) (string, bool, error) {
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return "", true, err
	}
	temp, err := os.CreateTemp(filepath.Dir(localPath), ".metadata-pending-*")
	if err != nil {
		return "", true, err
	}
	tempPath := temp.Name()
	removeTemp := true
	defer func() {
		if removeTemp {
			_ = os.Remove(tempPath)
		}
	}()
	handled, copyErr := a.metadataService().CopyPendingContent(ctx, item.inode, temp)
	if copyErr != nil {
		_ = temp.Close()
		return "", true, copyErr
	}
	if !handled {
		_ = temp.Close()
		return "", false, nil
	}
	if err := temp.Sync(); err != nil {
		_ = temp.Close()
		return "", true, err
	}
	if err := temp.Close(); err != nil {
		return "", true, err
	}
	if err := os.Remove(localPath); err != nil && !os.IsNotExist(err) {
		return "", true, err
	}
	if err := os.Rename(tempPath, localPath); err != nil {
		return "", true, err
	}
	removeTemp = false
	if err := writePendingDownloadStamp(localPath, item.info, item.inode, item.contentGeneration); err != nil {
		_ = os.Remove(localPath)
		return "", true, err
	}
	return localPath, true, nil
}
