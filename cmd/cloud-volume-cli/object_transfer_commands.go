// Transfer commands support file and directory upload/download using the shared S3 layer.
package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	s3ops "remote-storage/go/s3"
)

func runPutCommand(args []string) error {
	flags := newFlagSet("put")
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	if err := flags.Parse(args); err != nil {
		return err
	}
	remaining := flags.Args()
	if len(remaining) < 1 || len(remaining) > 2 {
		return errors.New("put 用法: cloud-volume-cli put [--bucket name] <local-path> [remote-path]")
	}

	target, err := resolveObjectTarget(*configPath, *bucketName, "")
	if err != nil {
		return err
	}
	localPath := strings.TrimSpace(remaining[0])
	if localPath == "" {
		return errors.New("local path 不能为空")
	}
	if err := ensureLocalSourceExists(localPath); err != nil {
		return err
	}

	isDir, err := isLocalDirectory(localPath)
	if err != nil {
		return err
	}
	remotePath := ""
	if len(remaining) == 2 {
		remotePath = remaining[1]
	} else {
		remotePath = defaultRemoteObjectPath(localPath)
	}

	if !isDir {
		if err := ensureLocalFileSource(localPath); err != nil {
			return err
		}
		target.visibleKey = resolveVisiblePath(currentShellDir(), remotePath)
		target.remoteKey = applyRootPrefix(target.config.cfg.RootPrefix, target.visibleKey, false)
		if target.remoteKey == "" {
			return errors.New("remote path 不能为空")
		}
		if err := s3ops.UploadFile(target.config.cfg, target.bucket, target.remoteKey, localPath, ""); err != nil {
			return err
		}
		fmt.Fprintf(stdoutWriter(), "uploaded %s -> s3://%s/%s\n", localPath, target.bucket, target.visibleKey)
		return nil
	}

	entries, err := collectLocalUploadEntries(localPath, remotePath)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.isDir {
			parent := parentObjectDir(entry.visiblePath)
			name := filepath.Base(strings.TrimSuffix(entry.visiblePath, "/"))
			if err := s3ops.CreateDirectory(target.config.cfg, target.bucket, applyRootPrefix(
				target.config.cfg.RootPrefix,
				parent,
				true,
			), name); err != nil {
				return err
			}
			fmt.Fprintf(stdoutWriter(), "mkdir s3://%s/%s\n", target.bucket, entry.visiblePath)
			continue
		}
		remoteKey := applyRootPrefix(target.config.cfg.RootPrefix, entry.visiblePath, false)
		if err := s3ops.UploadFile(target.config.cfg, target.bucket, remoteKey, entry.localPath, ""); err != nil {
			return err
		}
		fmt.Fprintf(stdoutWriter(), "uploaded %s -> s3://%s/%s\n", entry.localPath, target.bucket, entry.visiblePath)
	}
	return nil
}

func runGetCommand(args []string) error {
	flags := newFlagSet("get")
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	if err := flags.Parse(args); err != nil {
		return err
	}
	remaining := flags.Args()
	if len(remaining) < 1 || len(remaining) > 2 {
		return errors.New("get 用法: cloud-volume-cli get [--bucket name] <remote-path> [local-path]")
	}

	visibleRemote := resolveVisiblePath(currentShellDir(), remaining[0])
	target, err := resolveObjectTarget(*configPath, *bucketName, visibleRemote)
	if err != nil {
		return err
	}
	localPath := ""
	if len(remaining) == 2 {
		localPath = strings.TrimSpace(remaining[1])
	}
	if localPath == "" {
		localPath = defaultDownloadPath(target.visibleKey)
	}
	if localPath == "" {
		return errors.New("local path 不能为空")
	}

	if info, err := s3ops.HeadObject(target.config.cfg, target.bucket, target.remoteKey); err == nil && !info.IsDir {
		if err := s3ops.DownloadFile(target.config.cfg, target.bucket, target.remoteKey, localPath, ""); err != nil {
			return err
		}
		fmt.Fprintf(stdoutWriter(), "downloaded s3://%s/%s -> %s\n", target.bucket, target.visibleKey, localPath)
		return nil
	}

	entries, err := collectRemoteDownloadEntries(target.config, target.bucket, target.visibleKey)
	if err != nil {
		return err
	}
	baseDir := localPath
	if strings.TrimSpace(baseDir) == "" {
		baseDir = filepath.Base(strings.TrimSuffix(target.visibleKey, "/"))
	}
	for _, entry := range entries {
		relative := relativeDownloadPath(target.visibleKey, entry.Key)
		localTarget := filepath.Join(baseDir, filepath.FromSlash(relative))
		if entry.IsDir {
			if err := os.MkdirAll(localTarget, 0o755); err != nil {
				return err
			}
			fmt.Fprintf(stdoutWriter(), "mkdir %s\n", localTarget)
			continue
		}
		if err := s3ops.DownloadFile(
			target.config.cfg,
			target.bucket,
			applyRootPrefix(target.config.cfg.RootPrefix, entry.Key, false),
			localTarget,
			"",
		); err != nil {
			return err
		}
		fmt.Fprintf(stdoutWriter(), "downloaded s3://%s/%s -> %s\n", target.bucket, entry.Key, localTarget)
	}
	return nil
}

func parentObjectDir(value string) string {
	clean := cleanObjectPath(value)
	if clean == "" {
		return ""
	}
	index := strings.LastIndex(clean, "/")
	if index < 0 {
		return ""
	}
	return clean[:index]
}

func relativeDownloadPath(baseDir, value string) string {
	cleanBase := cleanObjectPath(baseDir)
	cleanValue := cleanObjectPath(value)
	if cleanBase == "" {
		return cleanValue
	}
	prefix := cleanBase + "/"
	if strings.HasPrefix(cleanValue, prefix) {
		return strings.TrimPrefix(cleanValue, prefix)
	}
	return filepath.Base(cleanValue)
}
