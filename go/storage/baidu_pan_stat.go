// Baidu Pan stat helpers reuse cached fsids before falling back to path lists.
package storage

import (
	"errors"

	xpanclient "github.com/lfhy/xpan/client"
	xpanfile "github.com/lfhy/xpan/file"

	storageconfig "remote-storage/go/config"
)

func baiduPanStatObject(
	client *xpanclient.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	key string,
) (*xpanfile.FilemetasItem, error) {
	clean := baiduPanCleanKey(key)
	if clean == "" {
		return nil, errors.New("file not found")
	}
	if fsid, ok := cachedBaiduPanFsid(cfg, bucket, clean); ok {
		meta, err := client.StatObjectUseFsId(fsid)
		if err == nil {
			return meta, nil
		}
		forgetBaiduPanFsid(cfg, bucket, clean)
	}
	found, err := baiduPanListItemByPath(client, baiduPanObjectPath(clean))
	if err != nil {
		return nil, err
	}
	if found == nil {
		return nil, errors.New("file not found")
	}
	rememberBaiduPanFsid(cfg, bucket, clean, found.FsId)
	return client.StatObjectUseFsId(found.FsId)
}
