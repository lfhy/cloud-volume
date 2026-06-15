// Shared object helpers keep CLI key resolution and local tree walking consistent.
package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	s3ops "remote-storage/go/s3"
)

type objectTarget struct {
	config     loadedConfig
	bucket     string
	visibleKey string
	remoteKey  string
}

func resolveObjectTarget(configPath, bucketName, visiblePath string) (objectTarget, error) {
	loaded, err := loadConfiguredConfig(configPath)
	if err != nil {
		return objectTarget{}, err
	}
	bucket := strings.TrimSpace(bucketName)
	if bucket == "" {
		if activeShell != nil && strings.TrimSpace(activeShell.bucketOverride) != "" {
			bucket = strings.TrimSpace(activeShell.bucketOverride)
		} else {
			bucket = strings.TrimSpace(loaded.cfg.Bucket)
		}
	}
	if bucket == "" {
		return objectTarget{}, errors.New("缺少 bucket，请通过 --bucket 指定、在 shell 里设置 bucket，或先在 init 中保存默认 bucket")
	}

	cleanVisible := cleanObjectPath(visiblePath)
	return objectTarget{
		config:     loaded,
		bucket:     bucket,
		visibleKey: cleanVisible,
		remoteKey:  applyRootPrefix(loaded.cfg.RootPrefix, cleanVisible, false),
	}, nil
}

func ensureLocalSourceExists(localPath string) error {
	info, err := os.Stat(localPath)
	if err != nil {
		return err
	}
	if info.IsDir() {
		return nil
	}
	return nil
}

func ensureLocalFileSource(localPath string) error {
	info, err := os.Stat(localPath)
	if err != nil {
		return err
	}
	if info.IsDir() {
		return fmt.Errorf("暂不支持把目录当作单文件上传: %s", localPath)
	}
	return nil
}

func isLocalDirectory(localPath string) (bool, error) {
	info, err := os.Stat(localPath)
	if err != nil {
		return false, err
	}
	return info.IsDir(), nil
}

type localUploadEntry struct {
	localPath   string
	visiblePath string
	isDir       bool
}

func collectLocalUploadEntries(localPath, remoteBase string) ([]localUploadEntry, error) {
	info, err := os.Stat(localPath)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return []localUploadEntry{{
			localPath:   localPath,
			visiblePath: cleanObjectPath(remoteBase),
			isDir:       false,
		}}, nil
	}

	entries := make([]localUploadEntry, 0)
	rootName := filepath.Base(strings.TrimSpace(localPath))
	rootVisible := resolveVisiblePath(currentShellDir(), remoteBase)
	if rootVisible == "" {
		rootVisible = resolveVisiblePath(currentShellDir(), rootName)
	}
	entries = append(entries, localUploadEntry{
		localPath:   localPath,
		visiblePath: rootVisible,
		isDir:       true,
	})

	err = filepath.WalkDir(localPath, func(path string, d os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if path == localPath {
			return nil
		}
		relative, err := filepath.Rel(localPath, path)
		if err != nil {
			return err
		}
		visible := resolveVisiblePath(rootVisible, filepath.ToSlash(relative))
		entries = append(entries, localUploadEntry{
			localPath:   path,
			visiblePath: visible,
			isDir:       d.IsDir(),
		})
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].isDir != entries[j].isDir {
			return entries[i].isDir
		}
		return entries[i].visiblePath < entries[j].visiblePath
	})
	return entries, nil
}

func collectRemoteDownloadEntries(cfg loadedConfig, bucket, remoteBase string) ([]s3ops.ObjectInfo, error) {
	baseKey := applyRootPrefix(cfg.cfg.RootPrefix, remoteBase, true)
	items, err := s3ops.ListObjects(cfg.cfg, bucket, baseKey)
	if err != nil {
		return nil, err
	}
	result := make([]s3ops.ObjectInfo, 0, len(items)+1)
	result = append(result, s3ops.ObjectInfo{Key: remoteBase, IsDir: true})
	for _, item := range items {
		visible, ok := stripRootPrefix(cfg.cfg.RootPrefix, item.Key, item.IsDir)
		if !ok {
			continue
		}
		item.Key = visible
		result = append(result, item)
	}
	return result, nil
}

func listVisibleObjects(cfg loadedConfig, bucket, prefix string) ([]s3ops.ObjectInfo, error) {
	items, err := s3ops.ListObjects(cfg.cfg, bucket, applyRootPrefix(
		cfg.cfg.RootPrefix,
		prefix,
		true,
	))
	if err != nil {
		return nil, err
	}
	visibleItems := make([]s3ops.ObjectInfo, 0, len(items))
	for _, item := range items {
		visible, ok := stripRootPrefix(cfg.cfg.RootPrefix, item.Key, item.IsDir)
		if !ok {
			continue
		}
		item.Key = relativeListedPath(prefix, visible, item.IsDir)
		visibleItems = append(visibleItems, item)
	}
	return visibleItems, nil
}
