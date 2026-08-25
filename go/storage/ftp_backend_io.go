// FTP file I/O: upload, download, range read, stream, and directory operations.
package storage

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
)

func (b ftpBackend) ReadObjectRange(
	ctx context.Context,
	_, key string,
	offset, length int64,
) ([]byte, error) {
	if length <= 0 {
		return []byte{}, nil
	}
	conn, err := b.ftpConnect(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = conn.Quit() }()

	r, err := conn.RetrFrom(ftpRemotePath(key), uint64(offset))
	if err != nil {
		return nil, fmt.Errorf("ftp retr %q: %w", key, err)
	}
	defer r.Close()
	return io.ReadAll(io.LimitReader(r, length))
}

func (b ftpBackend) DirectoryAccess(
	ctx context.Context,
	bucket, prefix string,
) (DirectoryAccess, error) {
	return DirectoryAccess{
		Writable: !b.bucketConfig(bucket).BucketSettingsFor(bucket).ReadOnly,
		Known:    true,
	}, nil
}

func (b ftpBackend) CreateDirectory(
	ctx context.Context,
	bucket, prefix, name string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	dir := path.Join(ftpRemotePath(prefix), strings.Trim(strings.TrimSpace(name), "/"))
	conn, err := b.ftpConnect(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = conn.Quit() }()
	return conn.MakeDir(dir)
}

func (b ftpBackend) DeleteObject(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	taskID string,
) error {
	return runTrackedMutation(
		ctx, "delete", bucket, key, "", taskID, b.cfg.ProfileID,
		func(operationCtx context.Context) error {
			if err := b.ensureBucketWritable(bucket); err != nil {
				return err
			}
			conn, err := b.ftpConnect(operationCtx)
			if err != nil {
				return err
			}
			defer func() { _ = conn.Quit() }()
			remotePath := ftpRemotePath(key)
			if isDirectory {
				return conn.RemoveDirRecur(remotePath)
			}
			return conn.Delete(remotePath)
		},
	)
}

func (b ftpBackend) DeleteObjectHard(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	taskID string,
) error {
	return b.DeleteObject(ctx, bucket, key, isDirectory, taskID)
}

func (b ftpBackend) RenameObject(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	newName string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	conn, err := b.ftpConnect(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = conn.Quit() }()
	target, err := ftpRenamedTarget(key, isDirectory, newName)
	if err != nil {
		return err
	}
	return conn.Rename(ftpRemotePath(key), ftpRemotePath(target))
}

func (b ftpBackend) CopyObject(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
	isDirectory bool,
	taskID string,
) error {
	return runTrackedMutation(
		ctx, "copy", bucket, sourceKey, targetKey, taskID, b.cfg.ProfileID,
		func(operationCtx context.Context) error {
			if err := b.ensureBucketWritable(bucket); err != nil {
				return err
			}
			return b.ftpCopy(operationCtx, bucket, sourceKey, targetKey, isDirectory)
		},
	)
}

func (b ftpBackend) MoveObject(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
	isDirectory bool,
	taskID string,
) error {
	return runTrackedMutation(
		ctx, "move", bucket, sourceKey, targetKey, taskID, b.cfg.ProfileID,
		func(operationCtx context.Context) error {
			if err := b.ensureBucketWritable(bucket); err != nil {
				return err
			}
			conn, err := b.ftpConnect(operationCtx)
			if err != nil {
				return err
			}
			defer func() { _ = conn.Quit() }()
			return conn.Rename(ftpRemotePath(sourceKey), ftpRemotePath(targetKey))
		},
	)
}

func (b ftpBackend) UploadFile(
	ctx context.Context,
	bucket, key, localPath, taskID string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	file, err := os.Open(localPath)
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	return runTrackedUpload(
		ctx,
		bucket,
		key,
		localPath,
		file,
		info.Size(),
		taskID,
		func(uploadCtx context.Context, body io.Reader) error {
			return b.ftpStore(uploadCtx, key, body)
		},
		b.cfg.ProfileID,
	)
}

func (b ftpBackend) UploadReader(
	ctx context.Context,
	bucket, key string,
	body io.Reader,
	size int64,
	taskID, _ string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return runTrackedUpload(
		ctx,
		bucket,
		key,
		"",
		body,
		size,
		taskID,
		func(uploadCtx context.Context, tracked io.Reader) error {
			return b.ftpStore(uploadCtx, key, tracked)
		},
		b.cfg.ProfileID,
	)
}

func (b ftpBackend) DownloadFile(
	ctx context.Context,
	bucket, key, localPath, taskID string,
) (err error) {
	var total int64
	if taskID != "" {
		if info, statErr := b.HeadObject(ctx, bucket, key); statErr == nil {
			total = info.Size
		}
		var finish func(error)
		ctx, finish = beginTrackedDownload(ctx, bucket, key, localPath, total, taskID, b.cfg.ProfileID)
		defer func() { finish(err) }()
	}
	conn, err := b.ftpConnect(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = conn.Quit() }()

	r, err := conn.Retr(ftpRemotePath(key))
	if err != nil {
		return fmt.Errorf("ftp retr %q: %w", key, err)
	}
	defer r.Close()
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return err
	}
	out, err := os.Create(localPath)
	if err != nil {
		return err
	}
	defer out.Close()
	reader := io.Reader(r)
	if taskID != "" {
		reader = &trackedDownloadReader{ctx: ctx, reader: r, taskID: taskID}
	}
	_, err = io.Copy(out, reader)
	return err
}

func (b ftpBackend) StreamObjectToHTTP(
	ctx context.Context,
	_, key string,
	_ bool,
	w http.ResponseWriter,
) error {
	conn, err := b.ftpConnect(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = conn.Quit() }()
	r, err := conn.Retr(ftpRemotePath(key))
	if err != nil {
		return fmt.Errorf("ftp retr %q: %w", key, err)
	}
	defer r.Close()
	_, err = io.Copy(w, r)
	return err
}

// ftpStore uploads a reader to the FTP server, creating parent directories first.
func (b ftpBackend) ftpStore(ctx context.Context, key string, body io.Reader) error {
	conn, err := b.ftpConnect(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = conn.Quit() }()
	if err := b.ftpEnsureDir(conn, path.Dir(ftpRemotePath(key))); err != nil {
		return err
	}
	return conn.Stor(ftpRemotePath(key), body)
}

// ftpEnsureDir creates each parent segment if it does not already exist.
func (b ftpBackend) ftpEnsureDir(conn ftpConnLike, dir string) error {
	dir = strings.TrimRight(dir, "/")
	if dir == "" || dir == "." {
		return nil
	}
	parts := strings.Split(strings.TrimPrefix(dir, "/"), "/")
	current := ""
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" || part == "." {
			continue
		}
		current += "/" + part
		// MakeDir returns an error if the directory already exists on most servers,
		// so we ignore errors and rely on the final STOR to fail if truly broken.
		_ = conn.MakeDir(current)
	}
	return nil
}

// ftpCopy emulates a file copy via download + upload because FTP has no copy command.
// Directory copies are walked recursively.
func (b ftpBackend) ftpCopy(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
	isDirectory bool,
) error {
	if isDirectory {
		return b.ftpCopyDir(ctx, bucket, sourceKey, targetKey)
	}
	conn, err := b.ftpConnect(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = conn.Quit() }()
	r, err := conn.Retr(ftpRemotePath(sourceKey))
	if err != nil {
		return err
	}
	defer r.Close()
	if err := b.ftpEnsureDir(conn, path.Dir(ftpRemotePath(targetKey))); err != nil {
		return err
	}
	return conn.Stor(ftpRemotePath(targetKey), r)
}

// ftpCopyDir walks a remote directory and copies each file to the target tree.
func (b ftpBackend) ftpCopyDir(
	ctx context.Context,
	bucket, sourceDir, targetDir string,
) error {
	page, err := b.ftpListPage(ctx, sourceDir)
	if err != nil {
		return err
	}
	for _, item := range page.Items {
		sourceChild := item.Key
		targetChild := strings.TrimSuffix(targetDir, "/") + "/" +
			strings.TrimSuffix(item.Key, "/")[strings.LastIndexByte(strings.TrimSuffix(item.Key, "/"), '/')+1:]
		if item.IsDir {
			if err := b.ftpCopyDir(ctx, bucket, sourceChild, targetChild); err != nil {
				return err
			}
			continue
		}
		if err := b.ftpCopy(ctx, bucket, sourceChild, targetChild, false); err != nil {
			return err
		}
	}
	return nil
}

// ftpRenamedTarget computes the new path after a rename, mirroring the WebDAV helper.
func ftpRenamedTarget(key string, isDirectory bool, newName string) (string, error) {
	trimmedName := strings.Trim(strings.TrimSpace(newName), "/")
	if trimmedName == "" {
		return "", fmt.Errorf("new name is required")
	}
	clean := strings.Trim(strings.TrimSpace(key), "/")
	if !isDirectory {
		dir := path.Dir(clean)
		if dir == "." {
			return trimmedName, nil
		}
		return dir + "/" + trimmedName, nil
	}
	dir := path.Dir(strings.TrimSuffix(clean, "/"))
	if dir == "." {
		return trimmedName + "/", nil
	}
	return dir + "/" + trimmedName + "/", nil
}
