// SFTP listing and object inspection operations.
package storage

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
)

func (b sftpBackend) ListObjectsPage(
	ctx context.Context,
	_, prefix, _ string,
	_ int32,
) (ObjectPage, error) {
	client, sshConn, err := b.sftpClient(ctx)
	if err != nil {
		return ObjectPage{}, err
	}
	defer func() {
		_ = client.Close()
		_ = sshConn.Close()
	}()

	entries, err := client.ReadDir(sftpRemotePath(prefix))
	if err != nil {
		return ObjectPage{}, err
	}
	items := make([]ObjectInfo, 0, len(entries))
	for _, entry := range entries {
		name := strings.TrimSpace(entry.Name())
		if name == "" || name == "." || name == ".." {
			continue
		}
		items = append(items, sftpEntryFromInfo(prefix, entry))
	}
	sftpSortObjects(items)
	return ObjectPage{Items: items}, nil
}

func (b sftpBackend) ListObjectsRecursive(
	ctx context.Context,
	bucket, prefix string,
) ([]ObjectInfo, error) {
	result := make([]ObjectInfo, 0, 64)
	queue := []string{strings.Trim(strings.TrimSpace(prefix), "/")}
	seen := map[string]struct{}{}
	for len(queue) > 0 {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		dir := queue[0]
		queue = queue[1:]
		if _, ok := seen[dir]; ok {
			continue
		}
		seen[dir] = struct{}{}
		page, err := b.ListObjectsPage(ctx, bucket, dir, "", 0)
		if err != nil {
			return nil, err
		}
		for _, item := range page.Items {
			if item.IsDir {
				queue = append(queue, strings.TrimSuffix(item.Key, "/"))
				continue
			}
			result = append(result, item)
		}
	}
	return result, nil
}

func (b sftpBackend) HeadObject(
	ctx context.Context,
	_, key string,
) (ObjectInfo, error) {
	client, sshConn, err := b.sftpClient(ctx)
	if err != nil {
		return ObjectInfo{}, err
	}
	defer func() {
		_ = client.Close()
		_ = sshConn.Close()
	}()

	info, err := client.Stat(sftpRemotePath(key))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return ObjectInfo{}, os.ErrNotExist
		}
		return ObjectInfo{}, fmt.Errorf("sftp stat %q: %w", key, err)
	}
	return sftpEntryFromStat(key, info), nil
}

// sftpEntryFromInfo converts an sftp FileInfo into the shared ObjectInfo.
func sftpEntryFromInfo(prefix string, info os.FileInfo) ObjectInfo {
	name := strings.TrimSpace(info.Name())
	key := strings.Trim(strings.TrimSpace(prefix), "/")
	if key == "" {
		key = name
	} else {
		key = key + "/" + name
	}
	isDir := info.IsDir()
	if isDir && !strings.HasSuffix(key, "/") {
		key += "/"
	}
	return ObjectInfo{
		Key:          key,
		Size:         info.Size(),
		LastModified: info.ModTime().Format("2006-01-02 15:04:05"),
		IsDir:        isDir,
	}
}

// sftpEntryFromStat converts a stat result for a specific key.
func sftpEntryFromStat(key string, info os.FileInfo) ObjectInfo {
	isDir := info.IsDir()
	cleanKey := strings.Trim(strings.TrimSpace(key), "/")
	if isDir && !strings.HasSuffix(cleanKey, "/") {
		cleanKey += "/"
	}
	return ObjectInfo{
		Key:          cleanKey,
		Size:         info.Size(),
		LastModified: info.ModTime().Format("2006-01-02 15:04:05"),
		IsDir:        isDir,
	}
}

// sftpSortObjects mirrors WebDAV/S3 ordering: directories first, then by name.
func sftpSortObjects(items []ObjectInfo) {
	sort.SliceStable(items, func(i, j int) bool {
		left := items[i]
		right := items[j]
		if left.IsDir != right.IsDir {
			return left.IsDir
		}
		return strings.ToLower(left.Key) < strings.ToLower(right.Key)
	})
}
