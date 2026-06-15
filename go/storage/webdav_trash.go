// WebDAV trash helpers mirror the app-level soft delete contract used by S3 backends.
package storage

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"net/http"
	"path"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	storageconfig "remote-storage/go/config"
)

const webDAVTrashMetadataSuffix = ".trashinfo.json"

type webDAVTrashMetadata struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	OriginalKey string `json:"originalKey"`
	TrashKey    string `json:"trashKey"`
	DeletedAt   string `json:"deletedAt"`
	IsDir       bool   `json:"isDir"`
	Size        int64  `json:"size"`
	ObjectCount int    `json:"objectCount"`
}

func (b webDAVBackend) ListTrashPage(
	ctx context.Context,
	bucket, nextToken string,
	pageSize int32,
) (TrashPage, error) {
	cfg := b.bucketConfig(bucket)
	if !cfg.BucketSettingsFor(bucket).IsTrashEnabled() {
		return TrashPage{Items: []TrashItem{}}, nil
	}
	items, err := b.listAllTrashItems(ctx, cfg)
	if err != nil {
		return TrashPage{}, err
	}
	if pageSize <= 0 {
		pageSize = 200
	}
	start := parseWebDAVTrashOffset(nextToken, len(items))
	end := start + int(pageSize)
	if end > len(items) {
		end = len(items)
	}
	next := ""
	if end < len(items) {
		next = strconv.Itoa(end)
	}
	return TrashPage{Items: items[start:end], NextToken: next}, nil
}

func (b webDAVBackend) RestoreTrashItem(ctx context.Context, bucket, trashID string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	cfg := b.bucketConfig(bucket)
	metadata, err := b.loadTrashMetadata(ctx, cfg, trashID)
	if err != nil {
		return err
	}
	if err := b.ensureDirectoryPath(ctx, path.Dir(strings.TrimSuffix(metadata.OriginalKey, "/"))); err != nil {
		return err
	}
	if err := b.copyMove(ctx, "MOVE", metadata.TrashKey, metadata.OriginalKey); err != nil {
		return err
	}
	return b.deletePath(ctx, webDAVTrashMetadataKey(cfg, trashID))
}

func (b webDAVBackend) DeleteTrashItem(ctx context.Context, bucket, trashID string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	cfg := b.bucketConfig(bucket)
	metadata, err := b.loadTrashMetadata(ctx, cfg, trashID)
	if err != nil {
		return err
	}
	if err := b.deletePath(ctx, metadata.TrashKey); err != nil {
		return err
	}
	return b.deletePath(ctx, webDAVTrashMetadataKey(cfg, trashID))
}

func (b webDAVBackend) ClearTrash(ctx context.Context, bucket string) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	cfg := b.bucketConfig(bucket)
	items, err := b.listAllTrashItems(ctx, cfg)
	if err != nil {
		return err
	}
	for _, item := range items {
		if err := b.DeleteTrashItem(ctx, bucket, item.ID); err != nil {
			return err
		}
	}
	return nil
}

func (b webDAVBackend) moveObjectToTrash(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
) error {
	cfg := b.bucketConfig(bucket)
	sourceKey := strings.Trim(strings.TrimSpace(key), "/")
	if sourceKey == "" || webDAVIsTrashKey(cfg, sourceKey) {
		return nil
	}
	if err := b.ensureTrashLayout(ctx, cfg); err != nil {
		return err
	}
	trashID := uuid.NewString()
	targetKey := webDAVTrashObjectTarget(cfg, trashID, sourceKey)
	if isDirectory {
		targetKey = ensureRemoteDirSuffix(targetKey)
	}
	if err := b.ensureDirectoryPath(ctx, path.Dir(strings.TrimSuffix(targetKey, "/"))); err != nil {
		return err
	}
	size, objectCount := b.trashPayloadMetrics(ctx, bucket, sourceKey, isDirectory)
	if err := b.copyMove(ctx, "MOVE", sourceKey, targetKey); err != nil {
		return err
	}
		metadata := webDAVTrashMetadata{
			ID:          trashID,
			Name:        webDAVTrashDisplayName(sourceKey),
			OriginalKey: sourceKey,
			TrashKey:    strings.Trim(strings.TrimSpace(targetKey), "/"),
			DeletedAt:   time.Now().UTC().Format(time.RFC3339),
		IsDir:       isDirectory,
		Size:        size,
		ObjectCount: objectCount,
	}
	if err := b.putJSON(ctx, webDAVTrashMetadataKey(cfg, trashID), metadata); err != nil {
		_ = b.copyMove(ctx, "MOVE", targetKey, sourceKey)
		return err
	}
	return nil
}

func (b webDAVBackend) listAllTrashItems(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
) ([]TrashItem, error) {
	entries, exists, err := b.propfindIfExists(ctx, webDAVTrashMetadataPrefix(cfg), "1")
	if err != nil {
		return nil, err
	}
	if !exists {
		return []TrashItem{}, nil
	}
	items := make([]TrashItem, 0, len(entries))
	base := cleanRemotePath(webDAVTrashMetadataPrefix(cfg))
	for _, entry := range entries {
		info, ok := b.objectInfoFromResponse(entry, base)
		if !ok || info.IsDir || !strings.HasSuffix(info.Key, webDAVTrashMetadataSuffix) {
			continue
		}
		metadata, err := b.loadTrashMetadataByKey(ctx, info.Key)
		if err != nil {
			continue
		}
		items = append(items, trashItemFromWebDAVMetadata(metadata))
	}
	sort.Slice(items, func(i, j int) bool { return items[i].DeletedAt > items[j].DeletedAt })
	return items, nil
}

func (b webDAVBackend) loadTrashMetadata(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	trashID string,
) (webDAVTrashMetadata, error) {
	return b.loadTrashMetadataByKey(ctx, webDAVTrashMetadataKey(cfg, trashID))
}

func (b webDAVBackend) loadTrashMetadataByKey(
	ctx context.Context,
	key string,
) (webDAVTrashMetadata, error) {
	req, err := b.request(ctx, http.MethodGet, key, nil)
	if err != nil {
		return webDAVTrashMetadata{}, err
	}
	resp, err := b.client.Do(req)
	if err != nil {
		return webDAVTrashMetadata{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return webDAVTrashMetadata{}, fmt.Errorf("trash item not found")
	}
	if resp.StatusCode >= 300 {
		return webDAVTrashMetadata{}, fmt.Errorf("webdav get: %s", resp.Status)
	}
	var metadata webDAVTrashMetadata
	if err := json.NewDecoder(resp.Body).Decode(&metadata); err != nil {
		return webDAVTrashMetadata{}, err
	}
	metadata.ID = strings.TrimSpace(metadata.ID)
	metadata.Name = strings.TrimSpace(metadata.Name)
	metadata.OriginalKey = strings.Trim(strings.TrimSpace(metadata.OriginalKey), "/")
	metadata.TrashKey = strings.Trim(strings.TrimSpace(metadata.TrashKey), "/")
	return metadata, nil
}

func (b webDAVBackend) putJSON(ctx context.Context, key string, value any) error {
	body, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	return b.put(ctx, key, strings.NewReader(string(body)))
}

func (b webDAVBackend) deletePath(ctx context.Context, key string) error {
	req, err := b.request(ctx, http.MethodDelete, key, nil)
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

func (b webDAVBackend) ensureTrashLayout(ctx context.Context, cfg storageconfig.RemoteStorageConfig) error {
	if err := b.ensureDirectoryPath(ctx, cleanRemotePath(cfg.TrashDirectoryName)); err != nil {
		return err
	}
	if err := b.ensureDirectoryPath(ctx, cleanRemotePath(webDAVTrashObjectsPrefix(cfg))); err != nil {
		return err
	}
	return b.ensureDirectoryPath(ctx, cleanRemotePath(webDAVTrashMetadataPrefix(cfg)))
}

func (b webDAVBackend) ensureDirectoryPath(ctx context.Context, key string) error {
	clean := cleanRemotePath(key)
	if clean == "" || clean == "." {
		return nil
	}
	current := ""
	for _, segment := range strings.Split(clean, "/") {
		trimmed := strings.TrimSpace(segment)
		if trimmed == "" {
			continue
		}
		if current == "" {
			current = trimmed
		} else {
			current = current + "/" + trimmed
		}
		req, err := b.request(ctx, "MKCOL", current+"/", nil)
		if err != nil {
			return err
		}
		resp, err := b.client.Do(req)
		if err != nil {
			return err
		}
		resp.Body.Close()
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			continue
		}
		if resp.StatusCode == http.StatusMethodNotAllowed || resp.StatusCode == http.StatusConflict {
			continue
		}
		return fmt.Errorf("webdav mkcol: %s", resp.Status)
	}
	return nil
}

func (b webDAVBackend) propfindIfExists(
	ctx context.Context,
	key, depth string,
) ([]webDAVResponse, bool, error) {
	req, err := b.request(ctx, "PROPFIND", key, strings.NewReader(webDAVPropfindBody))
	if err != nil {
		return nil, false, err
	}
	req.Header.Set("Depth", depth)
	req.Header.Set("Content-Type", `application/xml; charset="utf-8"`)
	resp, err := b.client.Do(req)
	if err != nil {
		return nil, false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return nil, false, nil
	}
	if resp.StatusCode >= 300 {
		return nil, false, fmt.Errorf("webdav propfind: %s", resp.Status)
	}
	var multi webDAVMultistatus
	if err := xml.NewDecoder(resp.Body).Decode(&multi); err != nil {
		return nil, false, err
	}
	return multi.Responses, true, nil
}

func (b webDAVBackend) trashPayloadMetrics(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
) (int64, int) {
	if isDirectory {
		return 0, 1
	}
	info, err := b.HeadObject(ctx, bucket, key)
	if err != nil {
		return 0, 1
	}
	return info.Size, 1
}

func webDAVTrashPrefix(cfg storageconfig.RemoteStorageConfig) string {
	return ensureRemoteDirSuffix(cleanRemotePath(cfg.TrashDirectoryName))
}

func webDAVTrashObjectsPrefix(cfg storageconfig.RemoteStorageConfig) string {
	return webDAVTrashPrefix(cfg) + "objects/"
}

func webDAVTrashMetadataPrefix(cfg storageconfig.RemoteStorageConfig) string {
	return webDAVTrashPrefix(cfg) + "entries/"
}

func webDAVTrashObjectTarget(
	cfg storageconfig.RemoteStorageConfig,
	id, originalKey string,
) string {
	base := strings.Trim(strings.TrimSpace(originalKey), "/")
	if base == "" {
		base = "_root"
	}
	return webDAVTrashObjectsPrefix(cfg) + id + "/" + base
}

func webDAVTrashMetadataKey(cfg storageconfig.RemoteStorageConfig, id string) string {
	return webDAVTrashMetadataPrefix(cfg) + strings.TrimSpace(id) + webDAVTrashMetadataSuffix
}

func webDAVIsTrashKey(cfg storageconfig.RemoteStorageConfig, key string) bool {
	trimmed := strings.Trim(strings.TrimSpace(key), "/")
	if trimmed == "" {
		return false
	}
	for _, alias := range storageconfig.TrashDirectoryAliases(cfg.TrashDirectoryName) {
		root := strings.Trim(strings.TrimSpace(alias), "/")
		if trimmed == root || strings.HasPrefix(trimmed, root+"/") {
			return true
		}
	}
	return false
}

func webDAVIsTrashRootEntry(cfg storageconfig.RemoteStorageConfig, key string) bool {
	trimmed := strings.Trim(strings.TrimSpace(key), "/")
	for _, alias := range storageconfig.TrashDirectoryAliases(cfg.TrashDirectoryName) {
		if trimmed == strings.Trim(strings.TrimSpace(alias), "/") {
			return true
		}
	}
	return false
}

func trashItemFromWebDAVMetadata(metadata webDAVTrashMetadata) TrashItem {
	return TrashItem{
		ID:          metadata.ID,
		Name:        metadata.Name,
		OriginalKey: metadata.OriginalKey,
		TrashKey:    metadata.TrashKey,
		DeletedAt:   metadata.DeletedAt,
		IsDir:       metadata.IsDir,
		Size:        metadata.Size,
		ObjectCount: metadata.ObjectCount,
	}
}

func webDAVTrashDisplayName(originalKey string) string {
	trimmed := strings.Trim(strings.TrimSpace(originalKey), "/")
	if trimmed == "" {
		return "/"
	}
	return path.Base(trimmed)
}

func ensureRemoteDirSuffix(value string) string {
	trimmed := strings.TrimSuffix(strings.TrimSpace(value), "/")
	if trimmed == "" {
		return ""
	}
	return trimmed + "/"
}

func parseWebDAVTrashOffset(nextToken string, length int) int {
	offset, err := strconv.Atoi(strings.TrimSpace(nextToken))
	if err != nil || offset < 0 || offset > length {
		return 0
	}
	return offset
}
