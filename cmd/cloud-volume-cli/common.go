// Shared CLI helpers keep bucket-targeted subcommands consistent.
package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type bucketRequest struct {
	bucket    string
	mountPath string
}

type loadedConfig struct {
	path string
	cfg  storageconfig.RemoteStorageConfig
}

func parseBucketRequest(command string, args []string) (bucketRequest, error) {
	flags := newFlagSet(command)
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	mountPoint := flags.String("mount-point", "", "mount point path")
	if err := flags.Parse(args); err != nil {
		return bucketRequest{}, err
	}
	if remaining := flags.Args(); len(remaining) > 2 {
		return bucketRequest{}, fmt.Errorf("%s 只接受最多两个位置参数：bucket 和 mount point", command)
	} else {
		if strings.TrimSpace(*bucketName) == "" && len(remaining) >= 1 {
			*bucketName = remaining[0]
		}
		if strings.TrimSpace(*mountPoint) == "" && len(remaining) == 2 {
			*mountPoint = remaining[1]
		}
	}

	loaded, err := loadConfig(*configPath)
	if err != nil {
		return bucketRequest{}, err
	}

	bucket := strings.TrimSpace(*bucketName)
	if bucket == "" {
		selected, err := resolveActiveBucket(loaded, false)
		if err != nil {
			return bucketRequest{}, err
		}
		bucket = selected
	}
	resolvedMountPath := strings.TrimSpace(*mountPoint)
	if bucket == "" && resolvedMountPath == "" {
		return bucketRequest{}, errors.New("缺少 bucket，请通过 --bucket 指定、传入 mount point，或先先选择一个 bucket")
	}
	return bucketRequest{
		bucket:    bucket,
		mountPath: resolvedMountPath,
	}, nil
}

func openConfigStore(explicitPath string) (storageconfig.Store, string, error) {
	if strings.TrimSpace(explicitPath) == "" && activeShell != nil && strings.TrimSpace(activeShell.configPath) != "" {
		explicitPath = activeShell.configPath
	}
	if strings.TrimSpace(explicitPath) != "" {
		path := strings.TrimSpace(explicitPath)
		return storageconfig.NewStore(path), path, nil
	}
	path, err := storageconfig.DefaultConfigPath()
	if err != nil {
		return storageconfig.Store{}, "", err
	}
	return storageconfig.NewStore(path), path, nil
}

func loadConfig(explicitPath string) (loadedConfig, error) {
	store, resolvedPath, err := openConfigStore(explicitPath)
	if err != nil {
		return loadedConfig{}, err
	}
	cfg, err := store.Load()
	if err != nil {
		return loadedConfig{}, err
	}
	return loadedConfig{
		path: resolvedPath,
		cfg:  cfg.Normalized(),
	}, nil
}

func loadConfiguredConfig(explicitPath string) (loadedConfig, error) {
	loaded, err := loadConfig(explicitPath)
	if err != nil {
		return loadedConfig{}, err
	}
	if !loaded.cfg.IsConfigured() {
		return loadedConfig{}, errors.New("当前还没有完整配置，请先运行 cloud-volume-cli init")
	}
	return loaded, nil
}

func resolveActiveBucket(loaded loadedConfig, allowEmpty bool) (string, error) {
	if activeShell != nil && strings.TrimSpace(activeShell.bucketOverride) != "" {
		return strings.TrimSpace(activeShell.bucketOverride), nil
	}
	if strings.TrimSpace(loaded.cfg.Bucket) != "" {
		return strings.TrimSpace(loaded.cfg.Bucket), nil
	}
	if allowEmpty {
		return "", nil
	}
	selected, err := chooseBucketInteractively(loaded)
	if err != nil {
		return "", err
	}
	applySelectedBucket(selected)
	return selected, nil
}

func chooseBucketInteractively(loaded loadedConfig) (string, error) {
	buckets, err := s3ops.ListBuckets(loaded.cfg)
	if err != nil {
		return "", fmt.Errorf("拉取 bucket 列表失败: %w", err)
	}
	options := make([]string, 0, len(buckets))
	for _, bucket := range buckets {
		if strings.TrimSpace(bucket.Name) == "" {
			continue
		}
		options = append(options, strings.TrimSpace(bucket.Name))
	}
	if len(options) == 0 {
		return "", errors.New("当前账号下没有可用 bucket")
	}
	ui := newPromptUI()
	selected, err := ui.askChoice("请选择 Bucket", options, "")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(selected), nil
}

func stdoutWriter() io.Writer {
	return os.Stdout
}
