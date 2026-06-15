//go:build windows && cgo

// Cloud Files hydration translates placeholder callbacks into direct S3 reads.
package mount

import (
	"context"
	"fmt"
	"log"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type cloudFilesHydrator struct {
	syncRoot string
	access   *bucketAccess
	provider *cloudFilesProvider
	watcher  *windowsSyncWatcher
	reader   cloudFilesReader

	cancelMu sync.Mutex
	cancels  map[string]context.CancelFunc

	placeholderMu       sync.Mutex
	placeholderInflight map[string]chan struct{}
	placeholderFetched  map[string]time.Time
}

func newCloudFilesHydrator(
	syncRoot string,
	access *bucketAccess,
	provider *cloudFilesProvider,
	watcher *windowsSyncWatcher,
	reader cloudFilesReader,
) *cloudFilesHydrator {
	return &cloudFilesHydrator{
		syncRoot:            syncRoot,
		access:              access,
		provider:            provider,
		watcher:             watcher,
		reader:              reader,
		cancels:             map[string]context.CancelFunc{},
		placeholderInflight: map[string]chan struct{}{},
		placeholderFetched:  map[string]time.Time{},
	}
}

func (h *cloudFilesHydrator) OnFetchData(req cloudFilesFetchRequest) error {
	ctx, cancel := context.WithCancel(context.Background())
	h.cancelMu.Lock()
	h.cancels[req.LocalPath] = cancel
	h.cancelMu.Unlock()
	defer func() {
		cancel()
		h.cancelMu.Lock()
		delete(h.cancels, req.LocalPath)
		h.cancelMu.Unlock()
	}()

	virtualPath := cloudFilesLocalPathToVirtual(h.syncRoot, req.LocalPath)
	if virtualPath == "" {
		return fmt.Errorf("resolve Cloud Files fetch path")
	}
	log.Printf(
		"[mount/cloud-files] fetch-data path=%q local=%q offset=%d length=%d",
		virtualPath,
		req.LocalPath,
		req.Offset,
		req.Length,
	)
	h.watcher.MarkHydrating(req.LocalPath)

	transferRange := cloudFilesAlignedTransferRange(req.Offset, req.Length, req.FileSize)
	log.Printf(
		"[mount/cloud-files] fetch-data-plan path=%q fileSize=%d requestedOffset=%d requestedLength=%d transferOffset=%d transferLength=%d",
		virtualPath,
		req.FileSize,
		req.Offset,
		req.Length,
		transferRange.Offset,
		transferRange.Length,
	)
	data, err := h.reader.Read(
		ctx,
		virtualPath,
		transferRange.Offset,
		transferRange.Length,
	)
	if err != nil {
		_ = h.provider.ReportError(req, err)
		return fmt.Errorf("read remote range %q: %w", virtualPath, err)
	}
	if err := h.provider.ExecuteTransfer(transferRange.Offset, req, data); err != nil {
		_ = h.provider.ReportError(req, err)
		return fmt.Errorf("execute Cloud Files transfer %q: %w", virtualPath, err)
	}
	h.watcher.MarkHydrated(req.LocalPath)
	log.Printf(
		"[mount/cloud-files] fetch-data-done path=%q local=%q requested=%d transferred=%d transferOffset=%d",
		virtualPath,
		req.LocalPath,
		req.Length,
		len(data),
		transferRange.Offset,
	)
	return nil
}

func (h *cloudFilesHydrator) OnCancelFetch(req cloudFilesFetchRequest) {
	log.Printf("[mount/cloud-files] cancel-fetch local=%q", req.LocalPath)
	h.cancelMu.Lock()
	cancel := h.cancels[req.LocalPath]
	h.cancelMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func (h *cloudFilesHydrator) OnFetchPlaceholders(localPath string) error {
	cleanLocalPath := filepath.Clean(localPath)
	shouldFetch, wait := h.beginPlaceholderFetch(cleanLocalPath)
	if wait != nil {
		<-wait
		return nil
	}
	if !shouldFetch {
		return nil
	}
	success := false
	defer func() {
		h.finishPlaceholderFetch(cleanLocalPath, success)
	}()

	virtualPath := cloudFilesLocalPathToVirtual(h.syncRoot, localPath)
	log.Printf(
		"[mount/cloud-files] fetch-placeholders local=%q virtual=%q",
		localPath,
		virtualPath,
	)
	items, err := h.access.listRemoteDirectory(context.Background(), virtualPath)
	if err != nil {
		return fmt.Errorf("list remote directory %q: %w", virtualPath, err)
	}

	placeholders := make([]cloudPlaceholderInfo, 0, len(items))
	for _, item := range items {
		relativeName := strings.TrimSuffix(baseName(item.Key), "/")
		if relativeName == "" {
			continue
		}
		placeholder := cloudFilesPlaceholderInfo(item)
		placeholder.RelativePath = relativeName
		placeholders = append(placeholders, placeholder)
	}
	h.watcher.RememberPlaceholders(localPath, placeholders)
	log.Printf(
		"[mount/cloud-files] fetch-placeholders-done local=%q virtual=%q count=%d",
		localPath,
		virtualPath,
		len(placeholders),
	)
	if err := h.provider.CreatePlaceholders(localPath, placeholders); err != nil {
		h.watcher.watchPlaceholderDirectories(localPath, placeholders)
		return err
	}
	h.watcher.watchPlaceholderDirectories(localPath, placeholders)
	success = true
	return nil
}
