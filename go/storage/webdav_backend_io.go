// WebDAV backend I/O helpers keep ranged reads and downloads reusable across mount code paths.
package storage

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
)

func (b webDAVBackend) DownloadFile(ctx context.Context, _, key, localPath, _ string) error {
	req, err := b.request(ctx, http.MethodGet, key, nil)
	if err != nil {
		return err
	}
	resp, err := b.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("webdav get: %s", resp.Status)
	}
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return err
	}
	out, err := os.Create(localPath)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, resp.Body)
	return err
}

func (b webDAVBackend) StreamObjectToHTTP(ctx context.Context, _, key string, _ bool, w http.ResponseWriter) error {
	req, err := b.request(ctx, http.MethodGet, key, nil)
	if err != nil {
		return err
	}
	resp, err := b.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("webdav get: %s", resp.Status)
	}
	_, err = io.Copy(w, resp.Body)
	return err
}

func (b webDAVBackend) readObjectRange(
	ctx context.Context,
	key string,
	offset, length int64,
) ([]byte, error) {
	if length <= 0 {
		return []byte{}, nil
	}
	if offset < 0 {
		offset = 0
	}
	req, err := b.request(ctx, http.MethodGet, key, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", offset, offset+length-1))
	resp, err := b.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusPartialContent:
		return io.ReadAll(io.LimitReader(resp.Body, length))
	case http.StatusRequestedRangeNotSatisfiable:
		return []byte{}, nil
	case http.StatusOK:
		if offset > 0 {
			if _, err := io.CopyN(io.Discard, resp.Body, offset); err != nil {
				if err == io.EOF {
					return []byte{}, nil
				}
				return nil, err
			}
		}
		return io.ReadAll(io.LimitReader(resp.Body, length))
	default:
		return nil, fmt.Errorf("webdav get: %s", resp.Status)
	}
}
