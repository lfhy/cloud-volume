// WebDAV mkdir helpers keep directory creation diagnostics focused and visible.
package storage

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"path"
	"strings"
	"time"
)

func (b webDAVBackend) CreateDirectory(ctx context.Context, bucket, prefix, name string) error {
	startedAt := time.Now()
	dir := path.Join(cleanRemotePath(prefix), strings.Trim(strings.TrimSpace(name), "/"))
	log.Printf(
		"[webdav/mkdir] start bucket=%q prefix=%q name=%q dir=%q",
		bucket,
		prefix,
		name,
		dir,
	)
	if err := b.ensureBucketWritable(bucket); err != nil {
		logWebDAVMkdirError(bucket, prefix, name, dir, startedAt, err)
		return err
	}
	if err := b.ensureWritableDirectory(ctx, bucket, prefix); err != nil {
		logWebDAVMkdirError(bucket, prefix, name, dir, startedAt, err)
		return err
	}
	if dir == "." || dir == "" {
		err := fmt.Errorf("directory name is required")
		logWebDAVMkdirError(bucket, prefix, name, dir, startedAt, err)
		return err
	}
	req, err := b.request(ctx, "MKCOL", dir+"/", nil)
	if err != nil {
		logWebDAVMkdirError(bucket, prefix, name, dir, startedAt, err)
		return err
	}
	resp, err := b.client.Do(req)
	if err != nil {
		logWebDAVMkdirError(bucket, prefix, name, dir, startedAt, err)
		return err
	}
	statusCode := resp.StatusCode
	status := resp.Status
	_ = resp.Body.Close()
	log.Printf(
		"[webdav/mkdir] mkcol-response bucket=%q prefix=%q name=%q dir=%q status=%q duration=%s",
		bucket,
		prefix,
		name,
		dir,
		status,
		time.Since(startedAt).Round(time.Millisecond),
	)
	if statusCode >= 200 && statusCode < 300 {
		return nil
	}
	if statusCode == http.StatusMethodNotAllowed {
		exists, probeErr := b.directoryExists(ctx, dir)
		log.Printf(
			"[webdav/mkdir] exists-probe bucket=%q prefix=%q name=%q dir=%q exists=%t error=%v",
			bucket,
			prefix,
			name,
			dir,
			exists,
			probeErr,
		)
		if probeErr == nil && exists {
			return nil
		}
	}
	err = fmt.Errorf("webdav mkcol: %s", status)
	logWebDAVMkdirError(bucket, prefix, name, dir, startedAt, err)
	return err
}

func (b webDAVBackend) directoryExists(ctx context.Context, key string) (bool, error) {
	dirKey := webDAVDirectoryKey(key)
	entries, err := b.propfind(ctx, dirKey, "0")
	if err != nil {
		return false, err
	}
	requested := cleanRemotePath(dirKey)
	for _, entry := range entries {
		info, ok := b.objectInfoFromHeadResponse(entry, requested)
		if ok && info.IsDir {
			return true, nil
		}
	}
	return false, nil
}

func logWebDAVMkdirError(
	bucket string,
	prefix string,
	name string,
	dir string,
	startedAt time.Time,
	err error,
) {
	log.Printf(
		"[webdav/mkdir] error bucket=%q prefix=%q name=%q dir=%q duration=%s err=%v",
		bucket,
		prefix,
		name,
		dir,
		time.Since(startedAt).Round(time.Millisecond),
		err,
	)
}
