// SFTP file I/O: upload, download, range read, stream, and directory operations.
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

	"github.com/pkg/sftp"
)

func (b sftpBackend) ReadObjectRange(
	ctx context.Context,
	_, key string,
	offset, length int64,
) ([]byte, error) {
	if length <= 0 {
		return []byte{}, nil
	}
	client, sshConn, err := b.sftpClient(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		_ = client.Close()
		_ = sshConn.Close()
	}()

	f, err := client.Open(sftpRemotePath(key))
	if err != nil {
		return nil, fmt.Errorf("sftp open %q: %w", key, err)
	}
	defer f.Close()
	if offset > 0 {
		if _, err := f.Seek(offset, io.SeekStart); err != nil {
			return nil, err
		}
	}
	return io.ReadAll(io.LimitReader(f, length))
}

func (b sftpBackend) DirectoryAccess(
	ctx context.Context,
	bucket, _ string,
) (DirectoryAccess, error) {
	return DirectoryAccess{
		Writable: !b.bucketConfig(bucket).BucketSettingsFor(bucket).ReadOnly,
		Known:    true,
	}, nil
}

func (b sftpBackend) CreateDirectory(
	ctx context.Context,
	bucket, prefix, name string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	client, sshConn, err := b.sftpClient(ctx)
	if err != nil {
		return err
	}
	defer func() {
		_ = client.Close()
		_ = sshConn.Close()
	}()
	dir := path.Join(sftpRemotePath(prefix), strings.Trim(strings.TrimSpace(name), "/"))
	return client.Mkdir(dir)
}

func (b sftpBackend) DeleteObject(
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
			client, sshConn, err := b.sftpClient(operationCtx)
			if err != nil {
				return err
			}
			defer func() {
				_ = client.Close()
				_ = sshConn.Close()
			}()
			remotePath := sftpRemotePath(key)
			if isDirectory {
				return removeSFTPDirectoryRecursive(operationCtx, client, remotePath)
			}
			return client.Remove(remotePath)
		},
	)
}

// removeSFTPDirectoryRecursive removes files before each directory so the
// shared backend contract can delete non-empty folders like FTP and S3 do.
func removeSFTPDirectoryRecursive(ctx context.Context, client *sftp.Client, dir string) error {
	if ctx != nil {
		if err := ctx.Err(); err != nil {
			return err
		}
	}
	entries, err := client.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("sftp list directory %q: %w", dir, err)
	}
	for _, entry := range entries {
		child := path.Join(dir, entry.Name())
		if entry.IsDir() {
			if err := removeSFTPDirectoryRecursive(ctx, client, child); err != nil {
				return err
			}
			continue
		}
		if err := client.Remove(child); err != nil {
			return fmt.Errorf("sftp remove %q: %w", child, err)
		}
	}
	if err := client.RemoveDirectory(dir); err != nil {
		return fmt.Errorf("sftp remove directory %q: %w", dir, err)
	}
	return nil
}

func (b sftpBackend) DeleteObjectHard(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	taskID string,
) error {
	return b.DeleteObject(ctx, bucket, key, isDirectory, taskID)
}

func (b sftpBackend) RenameObject(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	newName string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	target, err := sftpRenamedTarget(key, isDirectory, newName)
	if err != nil {
		return err
	}
	client, sshConn, err := b.sftpClient(ctx)
	if err != nil {
		return err
	}
	defer func() {
		_ = client.Close()
		_ = sshConn.Close()
	}()
	return client.Rename(sftpRemotePath(key), sftpRemotePath(target))
}

func (b sftpBackend) CopyObject(
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
			_ = isDirectory // SFTP copy preserves the provider's native source type.
			return b.sftpCopy(operationCtx, bucket, sourceKey, targetKey)
		},
	)
}

func (b sftpBackend) MoveObject(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
	_ bool,
	taskID string,
) error {
	return runTrackedMutation(
		ctx, "move", bucket, sourceKey, targetKey, taskID, b.cfg.ProfileID,
		func(operationCtx context.Context) error {
			if err := b.ensureBucketWritable(bucket); err != nil {
				return err
			}
			client, sshConn, err := b.sftpClient(operationCtx)
			if err != nil {
				return err
			}
			defer func() {
				_ = client.Close()
				_ = sshConn.Close()
			}()
			return client.Rename(sftpRemotePath(sourceKey), sftpRemotePath(targetKey))
		},
	)
}

func (b sftpBackend) UploadFile(
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
			return b.sftpStore(uploadCtx, key, body)
		},
		b.cfg.ProfileID,
	)
}

func (b sftpBackend) UploadReader(
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
			return b.sftpStore(uploadCtx, key, tracked)
		},
		b.cfg.ProfileID,
	)
}

func (b sftpBackend) DownloadFile(
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
	client, sshConn, err := b.sftpClient(ctx)
	if err != nil {
		return err
	}
	defer func() {
		_ = client.Close()
		_ = sshConn.Close()
	}()

	r, err := client.Open(sftpRemotePath(key))
	if err != nil {
		return fmt.Errorf("sftp open %q: %w", key, err)
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

func (b sftpBackend) StreamObjectToHTTP(
	ctx context.Context,
	_, key string,
	_ bool,
	w http.ResponseWriter,
) error {
	client, sshConn, err := b.sftpClient(ctx)
	if err != nil {
		return err
	}
	defer func() {
		_ = client.Close()
		_ = sshConn.Close()
	}()
	r, err := client.Open(sftpRemotePath(key))
	if err != nil {
		return fmt.Errorf("sftp open %q: %w", key, err)
	}
	defer r.Close()
	_, err = io.Copy(w, r)
	return err
}

// sftpStore uploads a reader, creating parent directories first.
func (b sftpBackend) sftpStore(ctx context.Context, key string, body io.Reader) error {
	client, sshConn, err := b.sftpClient(ctx)
	if err != nil {
		return err
	}
	defer func() {
		_ = client.Close()
		_ = sshConn.Close()
	}()
	if err := sftpEnsureDir(client, path.Dir(sftpRemotePath(key))); err != nil {
		return err
	}
	f, err := client.Create(sftpRemotePath(key))
	if err != nil {
		return fmt.Errorf("sftp create %q: %w", key, err)
	}
	defer f.Close()
	_, err = io.Copy(f, body)
	return err
}

// sftpEnsureDir creates each parent segment if it does not already exist.
func sftpEnsureDir(client sftpDirMaker, dir string) error {
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
		_ = client.Mkdir(current)
	}
	return nil
}

// sftpDirMaker allows tests to inject a mock client.
type sftpDirMaker interface {
	Mkdir(string) error
}

// sftpCopy emulates a copy by downloading and re-uploading since SFTP has no server-side copy.
// For directories it walks the tree recursively.
func (b sftpBackend) sftpCopy(ctx context.Context, bucket, sourceKey, targetKey string) error {
	info, err := b.HeadObject(ctx, bucket, sourceKey)
	if err != nil {
		return err
	}
	if info.IsDir {
		return b.sftpCopyDir(ctx, bucket, sourceKey, targetKey)
	}

	client, sshConn, err := b.sftpClient(ctx)
	if err != nil {
		return err
	}
	defer func() {
		_ = client.Close()
		_ = sshConn.Close()
	}()

	r, err := client.Open(sftpRemotePath(sourceKey))
	if err != nil {
		return err
	}
	defer r.Close()
	if err := sftpEnsureDir(client, path.Dir(sftpRemotePath(targetKey))); err != nil {
		return err
	}
	f, err := client.Create(sftpRemotePath(targetKey))
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, r)
	return err
}

// sftpCopyDir walks a remote directory and copies each file to the target tree.
func (b sftpBackend) sftpCopyDir(ctx context.Context, bucket, sourceDir, targetDir string) error {
	page, err := b.ListObjectsPage(ctx, bucket, sourceDir, "", 0)
	if err != nil {
		return err
	}
	for _, item := range page.Items {
		baseName := strings.TrimSuffix(item.Key, "/")
		baseName = baseName[strings.LastIndexByte(baseName, '/')+1:]
		targetChild := strings.TrimSuffix(targetDir, "/") + "/" + baseName
		if item.IsDir {
			targetChild += "/"
		}
		if err := b.sftpCopy(ctx, bucket, item.Key, targetChild); err != nil {
			return err
		}
	}
	return nil
}

// sftpRenamedTarget computes the new path after a rename.
func sftpRenamedTarget(key string, isDirectory bool, newName string) (string, error) {
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
