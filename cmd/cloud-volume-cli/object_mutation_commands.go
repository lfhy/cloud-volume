// Mutation commands expose mkdir and hard delete flows for server-side object management.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	s3ops "remote-storage/go/s3"
)

func runMkdirCommand(args []string) error {
	flags := newFlagSet("mkdir")
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	if err := flags.Parse(args); err != nil {
		return err
	}
	remaining := flags.Args()
	if len(remaining) != 1 {
		return errors.New("mkdir 用法: cloud-volume-cli mkdir [--bucket name] <remote-dir>")
	}

	visibleDir := resolveVisiblePath(currentShellDir(), remaining[0])
	if visibleDir == "" {
		return errors.New("remote dir 不能为空")
	}
	target, err := resolveObjectTarget(*configPath, *bucketName, visibleDir)
	if err != nil {
		return err
	}
	parent := parentObjectDir(target.visibleKey)
	name := filepathBaseObject(target.visibleKey)
	if err := s3ops.CreateDirectory(target.config.cfg, target.bucket, applyRootPrefix(
		target.config.cfg.RootPrefix,
		parent,
		true,
	), name); err != nil {
		return err
	}
	fmt.Fprintf(stdoutWriter(), "mkdir s3://%s/%s\n", target.bucket, ensureObjectDirSuffix(target.visibleKey))
	return nil
}

func runRemoveCommand(args []string) error {
	flags := newFlagSet("rm")
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	jsonOutput := flags.Bool("json", false, "print JSON output")
	if err := flags.Parse(args); err != nil {
		return err
	}
	remaining := flags.Args()
	if len(remaining) != 1 {
		return errors.New("rm/delete 用法: cloud-volume-cli rm [--bucket name] <remote-path>")
	}

	visiblePath := resolveVisiblePath(currentShellDir(), remaining[0])
	target, err := resolveObjectTarget(*configPath, *bucketName, visiblePath)
	if err != nil {
		return err
	}

	isDir, err := detectRemoteDirectory(target)
	if err != nil {
		return err
	}
	if err := s3ops.DeleteObjectHard(
		target.config.cfg,
		target.bucket,
		applyRootPrefix(target.config.cfg.RootPrefix, target.visibleKey, isDir),
		isDir,
	); err != nil {
		return err
	}

	result := map[string]any{
		"ok":        true,
		"bucket":    target.bucket,
		"path":      target.visibleKey,
		"isDir":     isDir,
		"operation": "delete_hard",
	}
	if *jsonOutput {
		encoder := json.NewEncoder(stdoutWriter())
		encoder.SetIndent("", "  ")
		return encoder.Encode(result)
	}
	fmt.Fprintf(stdoutWriter(), "deleted s3://%s/%s\n", target.bucket, target.visibleKey)
	return nil
}

func detectRemoteDirectory(target objectTarget) (bool, error) {
	dirKey := applyRootPrefix(target.config.cfg.RootPrefix, target.visibleKey, true)
	page, err := s3ops.ListObjectsPage(target.config.cfg, target.bucket, dirKey, "", 1)
	if err != nil {
		return false, err
	}
	if len(page.Items) > 0 {
		return true, nil
	}
	if _, err := s3ops.HeadObject(target.config.cfg, target.bucket, target.remoteKey); err == nil {
		return false, nil
	}
	if _, err := s3ops.HeadObject(target.config.cfg, target.bucket, dirKey); err == nil {
		return true, nil
	}
	return false, fmt.Errorf("远端对象不存在: %s", target.visibleKey)
}

func filepathBaseObject(value string) string {
	clean := strings.TrimSuffix(cleanObjectPath(value), "/")
	if clean == "" {
		return ""
	}
	index := strings.LastIndex(clean, "/")
	if index < 0 {
		return clean
	}
	return clean[index+1:]
}
