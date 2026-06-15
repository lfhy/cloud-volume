// WebDAV backend lets account profiles browse and mutate a remote WebDAV tree.
package storage

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path"
	"sort"
	"strconv"
	"strings"
	"time"

	storageconfig "remote-storage/go/config"
)

type webDAVBackend struct {
	cfg    storageconfig.RemoteStorageConfig
	client *http.Client
}

func NewWebDAVBackend(cfg storageconfig.RemoteStorageConfig) Backend {
	return webDAVBackend{
		cfg:    cfg.Normalized(),
		client: &http.Client{Timeout: 60 * time.Second},
	}
}

func (b webDAVBackend) ListBuckets(context.Context) ([]BucketInfo, error) {
	return []BucketInfo{{Name: b.cfg.MappedBucketLabel()}}, nil
}

func (b webDAVBackend) ListObjectsPage(
	ctx context.Context,
	bucket, prefix, _ string,
	_ int32,
) (ObjectPage, error) {
	entries, err := b.propfind(ctx, prefix, "1")
	if err != nil {
		return ObjectPage{}, err
	}
	base := cleanRemotePath(prefix)
	items := make([]ObjectInfo, 0, len(entries))
	for _, entry := range entries {
		info, ok := b.objectInfoFromResponse(entry, base)
		if ok && !webDAVIsTrashRootEntry(b.bucketConfig(bucket), info.Key) {
			items = append(items, info)
		}
	}
	sortWebDAVObjects(items)
	return ObjectPage{Items: items}, nil
}

func (b webDAVBackend) HeadObject(ctx context.Context, _, key string) (ObjectInfo, error) {
	entries, err := b.propfind(ctx, key, "0")
	if err != nil {
		return ObjectInfo{}, err
	}
	requested := cleanRemotePath(key)
	for _, entry := range entries {
		if info, ok := b.objectInfoFromHeadResponse(entry, requested); ok {
			return info, nil
		}
	}
	return ObjectInfo{}, os.ErrNotExist
}

func (b webDAVBackend) ReadObjectRange(
	ctx context.Context,
	_ string,
	key string,
	offset, length int64,
) ([]byte, error) {
	return b.readObjectRange(ctx, key, offset, length)
}

func (b webDAVBackend) DeleteObject(ctx context.Context, bucket, key string, isDirectory bool, _ string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	if b.cfg.BucketSettingsFor(bucket).IsTrashEnabled() {
		return b.moveObjectToTrash(ctx, bucket, key, isDirectory)
	}
	req, err := b.request(ctx, "DELETE", key, nil)
	if err != nil {
		return err
	}
	resp, err := b.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound || resp.StatusCode < 300 {
		return nil
	}
	return fmt.Errorf("webdav delete: %s", resp.Status)
}

func (b webDAVBackend) DeleteObjectHard(
	ctx context.Context,
	bucket, key string,
	_ bool,
	_ string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return b.deletePath(ctx, key)
}

func (b webDAVBackend) RenameObject(ctx context.Context, bucket, key string, isDirectory bool, newName string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	target, err := renamedWebDAVTarget(key, isDirectory, newName)
	if err != nil {
		return err
	}
	return b.MoveObject(ctx, bucket, key, target, isDirectory, "")
}

func (b webDAVBackend) CopyObject(ctx context.Context, bucket, sourceKey, targetKey string, _ bool, _ string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return b.copyMove(ctx, "COPY", sourceKey, targetKey)
}

func (b webDAVBackend) MoveObject(ctx context.Context, bucket, sourceKey, targetKey string, _ bool, _ string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	return b.copyMove(ctx, "MOVE", sourceKey, targetKey)
}

func (b webDAVBackend) UploadFile(ctx context.Context, bucket, key, localPath, _ string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	if err := b.ensureWritableDirectory(ctx, bucket, path.Dir(cleanRemotePath(key))); err != nil {
		return err
	}
	file, err := os.Open(localPath)
	if err != nil {
		return err
	}
	defer file.Close()
	return b.put(ctx, key, file)
}

func (b webDAVBackend) UploadReader(
	ctx context.Context,
	bucket, key string,
	body io.Reader,
	_ int64,
	_, _ string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	if err := b.ensureWritableDirectory(ctx, bucket, path.Dir(cleanRemotePath(key))); err != nil {
		return err
	}
	return b.put(ctx, key, body)
}

func (b webDAVBackend) propfind(ctx context.Context, key, depth string) ([]webDAVResponse, error) {
	req, err := b.request(ctx, "PROPFIND", key, strings.NewReader(webDAVPropfindBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Depth", depth)
	req.Header.Set("Content-Type", `application/xml; charset="utf-8"`)
	resp, err := b.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("webdav propfind: %s", resp.Status)
	}
	var multi webDAVMultistatus
	if err := xml.NewDecoder(resp.Body).Decode(&multi); err != nil {
		return nil, err
	}
	return multi.Responses, nil
}

func (b webDAVBackend) put(ctx context.Context, key string, body io.Reader) error {
	req, err := b.request(ctx, http.MethodPut, key, body)
	if err != nil {
		return err
	}
	resp, err := b.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	return fmt.Errorf("webdav put: %s", resp.Status)
}

func (b webDAVBackend) copyMove(ctx context.Context, method, sourceKey, targetKey string) error {
	req, err := b.request(ctx, method, sourceKey, nil)
	if err != nil {
		return err
	}
	destination, err := b.remoteURL(targetKey)
	if err != nil {
		return err
	}
	req.Header.Set("Destination", destination)
	req.Header.Set("Overwrite", "T")
	resp, err := b.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	return fmt.Errorf("webdav %s: %s", strings.ToLower(method), resp.Status)
}

func (b webDAVBackend) request(ctx context.Context, method, key string, body io.Reader) (*http.Request, error) {
	remoteURL, err := b.remoteURL(key)
	if err != nil {
		return nil, err
	}
	if ctx == nil {
		ctx = context.Background()
	}
	req, err := http.NewRequestWithContext(ctx, method, remoteURL, body)
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(b.cfg.WebDAVUsername, b.cfg.WebDAVPassword)
	return req, nil
}

func (b webDAVBackend) remoteURL(key string) (string, error) {
	base, err := url.Parse(b.cfg.Endpoint)
	if err != nil {
		return "", err
	}
	remotePath := cleanRemotePath(key)
	base.Path = strings.TrimRight(base.Path, "/") + "/" + remotePath
	if remotePath != "" && strings.HasSuffix(strings.TrimSpace(key), "/") {
		base.Path += "/"
	}
	return base.String(), nil
}

func (b webDAVBackend) objectInfoFromResponse(resp webDAVResponse, base string) (ObjectInfo, bool) {
	key, ok := b.keyFromHref(resp.Href)
	if !ok || key == base || strings.TrimSuffix(key, "/") == strings.TrimSuffix(base, "/") {
		return ObjectInfo{}, false
	}
	return objectInfoFromWebDAVKey(key, resp), true
}

func (b webDAVBackend) objectInfoFromHeadResponse(resp webDAVResponse, requested string) (ObjectInfo, bool) {
	key, ok := b.keyFromHref(resp.Href)
	if !ok || strings.TrimSuffix(key, "/") != strings.TrimSuffix(requested, "/") {
		return ObjectInfo{}, false
	}
	return objectInfoFromWebDAVKey(key, resp), true
}

func objectInfoFromWebDAVKey(key string, resp webDAVResponse) ObjectInfo {
	prop := resp.firstProp()
	isDir := prop.ResourceType.Collection != nil || strings.HasSuffix(key, "/")
	if isDir && !strings.HasSuffix(key, "/") {
		key += "/"
	}
	size, _ := strconv.ParseInt(strings.TrimSpace(prop.ContentLength), 10, 64)
	return ObjectInfo{
		Key:          key,
		Size:         size,
		LastModified: parseHTTPTime(prop.LastModified),
		IsDir:        isDir,
	}
}

func (b webDAVBackend) keyFromHref(href string) (string, bool) {
	value, err := url.QueryUnescape(strings.TrimSpace(href))
	if err != nil {
		value = strings.TrimSpace(href)
	}
	base, err := url.Parse(b.cfg.Endpoint)
	if err != nil {
		return "", false
	}
	parsed, err := url.Parse(value)
	if err == nil && parsed.Path != "" {
		value = parsed.Path
	}
	trimmedBase := strings.TrimRight(base.Path, "/")
	key := strings.TrimPrefix(value, trimmedBase)
	key = strings.TrimPrefix(key, "/")
	return key, true
}

func cleanRemotePath(value string) string {
	return strings.Trim(strings.TrimSpace(value), "/")
}

func renamedWebDAVTarget(key string, isDirectory bool, newName string) (string, error) {
	trimmedName := strings.Trim(strings.TrimSpace(newName), "/")
	if trimmedName == "" {
		return "", fmt.Errorf("new name is required")
	}
	clean := cleanRemotePath(key)
	if !isDirectory {
		dir := path.Dir(clean)
		if dir == "." {
			return trimmedName, nil
		}
		return path.Join(dir, trimmedName), nil
	}
	dir := path.Dir(strings.TrimSuffix(clean, "/"))
	if dir == "." {
		return trimmedName + "/", nil
	}
	return path.Join(dir, trimmedName) + "/", nil
}

func parseHTTPTime(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}
	parsed, err := http.ParseTime(trimmed)
	if err != nil {
		return trimmed
	}
	return parsed.Format("2006-01-02 15:04:05")
}

// sortWebDAVObjects keeps WebDAV listing order aligned with the S3 browser.
func sortWebDAVObjects(items []ObjectInfo) {
	sort.SliceStable(items, func(i, j int) bool {
		left := items[i]
		right := items[j]
		if left.IsDir != right.IsDir {
			return left.IsDir
		}
		leftName := strings.ToLower(webDAVObjectSortName(left.Key))
		rightName := strings.ToLower(webDAVObjectSortName(right.Key))
		if leftName != rightName {
			return leftName < rightName
		}
		return strings.ToLower(left.Key) < strings.ToLower(right.Key)
	})
}

func webDAVObjectSortName(key string) string {
	trimmed := strings.TrimSuffix(strings.TrimSpace(key), "/")
	if trimmed == "" {
		return ""
	}
	return path.Base(trimmed)
}

const webDAVPropfindBody = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:resourcetype/>
    <D:getcontentlength/>
    <D:getlastmodified/>
  </D:prop>
</D:propfind>`

type webDAVMultistatus struct {
	Responses []webDAVResponse `xml:"response"`
}

type webDAVResponse struct {
	Href     string        `xml:"href"`
	Propstat []webDAVProps `xml:"propstat"`
}

func (r webDAVResponse) firstProp() webDAVProp {
	if len(r.Propstat) == 0 {
		return webDAVProp{}
	}
	return r.Propstat[0].Prop
}

type webDAVProps struct {
	Prop webDAVProp `xml:"prop"`
}

type webDAVProp struct {
	ResourceType  webDAVResourceType `xml:"resourcetype"`
	ContentLength string             `xml:"getcontentlength"`
	LastModified  string             `xml:"getlastmodified"`
}

type webDAVResourceType struct {
	Collection *struct{} `xml:"collection"`
}
