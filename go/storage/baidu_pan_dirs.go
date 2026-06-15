// Baidu Pan directory helpers keep mkdir idempotent despite server-side auto-renames.
package storage

import (
	"fmt"
	"path"
	"strings"
	"sync"

	xpanclient "github.com/lfhy/xpan/client"
	xpanfile "github.com/lfhy/xpan/file"
	xpantypes "github.com/lfhy/xpan/types"
)

var (
	baiduPanDirMu    sync.Mutex
	baiduPanKnownDir sync.Map
)

func ensureBaiduPanDir(client *xpanclient.Client, remoteDir string) error {
	clean := cleanBaiduPanDirPath(remoteDir)
	if clean == "" {
		return nil
	}
	if knownBaiduPanDir(clean) {
		return nil
	}
	baiduPanDirMu.Lock()
	defer baiduPanDirMu.Unlock()

	current := ""
	for _, part := range strings.Split(strings.TrimPrefix(clean, "/"), "/") {
		if strings.TrimSpace(part) == "" {
			continue
		}
		current += "/" + part
		if knownBaiduPanDir(current) {
			continue
		}
		if err := ensureBaiduPanDirLocked(client, current); err != nil {
			return err
		}
		rememberBaiduPanKnownDir(current)
	}
	return nil
}

func ensureBaiduPanDirLocked(client *xpanclient.Client, remoteDir string) error {
	exists, err := existingBaiduPanDir(client, remoteDir)
	if err != nil {
		return err
	}
	if exists {
		return nil
	}
	if _, err := client.Mkdir(remoteDir); err != nil {
		if statErr := ensureExistingBaiduPanDir(client, remoteDir, err); statErr != nil {
			return err
		}
	}
	return nil
}

func existingBaiduPanDir(
	client *xpanclient.Client,
	remoteDir string,
) (bool, error) {
	clean := cleanBaiduPanDirPath(remoteDir)
	if clean == "" {
		return true, nil
	}
	parent := path.Dir(clean)
	name := path.Base(clean)
	res, err := client.ListObjects(parent, &xpanfile.ListAllReq{
		Limit: 1000,
		Order: xpantypes.ListOrderName,
	})
	if err != nil {
		return false, err
	}
	for _, item := range res.List {
		if item.Name != name {
			continue
		}
		if item.IsDir == xpantypes.BoolIntTrue {
			return true, nil
		}
		return false, fmt.Errorf("baidu pan path exists and is not a directory: %s", remoteDir)
	}
	return false, nil
}

func ensureExistingBaiduPanDir(
	client *xpanclient.Client,
	remoteDir string,
	originalErr error,
) error {
	meta, err := client.StatObject(remoteDir)
	if err != nil {
		return originalErr
	}
	if meta.IsDir == xpantypes.BoolIntTrue {
		return nil
	}
	return originalErr
}

func cleanBaiduPanDirPath(remoteDir string) string {
	clean := path.Clean(strings.TrimSpace(remoteDir))
	if clean == "." || clean == "/" || clean == "" {
		return ""
	}
	return "/" + strings.Trim(clean, "/")
}

func knownBaiduPanDir(remoteDir string) bool {
	_, ok := baiduPanKnownDir.Load(remoteDir)
	return ok
}

func rememberBaiduPanKnownDir(remoteDir string) {
	if clean := cleanBaiduPanDirPath(remoteDir); clean != "" {
		baiduPanKnownDir.Store(clean, struct{}{})
	}
}

func forgetBaiduPanKnownDir(remotePath string) {
	clean := cleanBaiduPanDirPath(remotePath)
	if clean == "" {
		return
	}
	baiduPanKnownDir.Range(func(key, _ any) bool {
		dir, ok := key.(string)
		if ok && (dir == clean || strings.HasPrefix(dir, clean+"/")) {
			baiduPanKnownDir.Delete(dir)
		}
		return true
	})
}

func resetBaiduPanKnownDirsForTest() {
	baiduPanKnownDir.Range(func(key, _ any) bool {
		baiduPanKnownDir.Delete(key)
		return true
	})
}
