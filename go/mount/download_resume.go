// Download resume helpers track remote stamps for full cache files and partial fragments.
package mount

import (
	"encoding/json"
	"os"
	"path/filepath"

	s3ops "remote-storage/go/s3"
)

type downloadStamp struct {
	Size               int64  `json:"size"`
	LastModified       string `json:"lastModified"`
	ETag               string `json:"etag,omitempty"`
	MetadataInode      uint64 `json:"metadataInode,omitempty"`
	MetadataGeneration uint64 `json:"metadataGeneration,omitempty"`
}

func partialDownloadPath(localPath string) string {
	return localPath + ".downloading"
}

func partialStampPath(localPath string) string {
	return stampPath(partialDownloadPath(localPath))
}

func stampPath(localPath string) string {
	return localPath + ".stamp.json"
}

func matchesDownloadStamp(localPath string, info s3ops.ObjectInfo) bool {
	stamp, ok := loadDownloadStamp(localPath)
	if !ok {
		return false
	}
	return stamp.Size == info.Size && stamp.LastModified == info.LastModified && stamp.ETag == info.ETag &&
		stamp.MetadataInode == 0 && stamp.MetadataGeneration == 0
}

func matchesPendingDownloadStamp(localPath string, info s3ops.ObjectInfo, inode, generation uint64) bool {
	stamp, ok := loadDownloadStamp(localPath)
	return ok && stamp.Size == info.Size && stamp.LastModified == info.LastModified &&
		stamp.ETag == info.ETag && stamp.MetadataInode == inode && stamp.MetadataGeneration == generation
}

func loadDownloadStamp(localPath string) (downloadStamp, bool) {
	data, err := os.ReadFile(stampPath(localPath))
	if err != nil {
		return downloadStamp{}, false
	}
	var stamp downloadStamp
	if err := json.Unmarshal(data, &stamp); err != nil {
		return downloadStamp{}, false
	}
	return stamp, true
}

func writeDownloadStamp(localPath string, info s3ops.ObjectInfo) error {
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return err
	}
	data, err := json.Marshal(downloadStamp{
		Size:         info.Size,
		LastModified: info.LastModified,
		ETag:         info.ETag,
	})
	if err != nil {
		return err
	}
	return os.WriteFile(stampPath(localPath), data, 0o644)
}

func writePendingDownloadStamp(localPath string, info s3ops.ObjectInfo, inode, generation uint64) error {
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return err
	}
	data, err := json.Marshal(downloadStamp{
		Size: info.Size, LastModified: info.LastModified, ETag: info.ETag,
		MetadataInode: inode, MetadataGeneration: generation,
	})
	if err != nil {
		return err
	}
	return os.WriteFile(stampPath(localPath), data, 0o644)
}

// promoteConfirmedPendingStamp converts a chunk-materialized cache stamp into
// a normal confirmed-remote stamp once the worker confirmed that generation.
// Without this, the first post-confirmation read would evict the identical
// cache file and re-download it from the provider.
func promoteConfirmedPendingStamp(localPath string, info s3ops.ObjectInfo, inode, generation uint64) {
	if inode == 0 || generation == 0 {
		return
	}
	stamp, ok := loadDownloadStamp(localPath)
	if !ok || stamp.MetadataInode != inode || stamp.MetadataGeneration != generation {
		return
	}
	if stamp.Size != info.Size {
		return
	}
	_ = writeDownloadStamp(localPath, info)
}

func renameDownloadStamp(oldPath, newPath string) error {
	if err := os.MkdirAll(filepath.Dir(newPath), 0o755); err != nil {
		return err
	}
	if err := os.Remove(newPath); err != nil && !os.IsNotExist(err) {
		return err
	}
	if err := os.Rename(oldPath, newPath); err != nil {
		return err
	}
	return nil
}

func clearDownloadArtifacts(localPath string) {
	_ = os.Remove(localPath)
	_ = os.Remove(partialDownloadPath(localPath))
	_ = os.Remove(stampPath(localPath))
	_ = os.Remove(partialStampPath(localPath))
}

func isCompleteDownloadUsable(localPath string, info s3ops.ObjectInfo) bool {
	return isUsableLocalFile(localPath, info.Size) && matchesDownloadStamp(localPath, info)
}

func isPartialDownloadUsable(localPath string, info s3ops.ObjectInfo) bool {
	path := partialDownloadPath(localPath)
	fileInfo, err := os.Stat(path)
	if err != nil || fileInfo.IsDir() {
		return false
	}
	if fileInfo.Size() < 0 || fileInfo.Size() > info.Size {
		return false
	}
	return matchesDownloadStamp(path, info)
}

// reconcileDownloadArtifacts evicts cache files whose recorded remote stamp no longer matches.
func reconcileDownloadArtifacts(localPath string, info s3ops.ObjectInfo) {
	if !isCompleteDownloadUsable(localPath, info) {
		_ = os.Remove(localPath)
		_ = os.Remove(stampPath(localPath))
	}
	if !isPartialDownloadUsable(localPath, info) {
		_ = os.Remove(partialDownloadPath(localPath))
		_ = os.Remove(partialStampPath(localPath))
	}
}
