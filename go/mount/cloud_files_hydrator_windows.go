//go:build windows && cgo

// Cloud Files hydration translates placeholder callbacks into direct S3 reads.
package mount

import (
	"context"
	"fmt"
	"log"
	"path/filepath"
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

	placeholderMu        sync.Mutex
	placeholderInflight  map[string]*cloudFilesPlaceholderFetch
	placeholderFetched   map[string]time.Time
	projectionMu         sync.Mutex
	projectedDirectories map[string]map[string]cloudPlaceholderInfo
}

func newCloudFilesHydrator(
	syncRoot string,
	access *bucketAccess,
	provider *cloudFilesProvider,
	watcher *windowsSyncWatcher,
	reader cloudFilesReader,
) *cloudFilesHydrator {
	return &cloudFilesHydrator{
		syncRoot:             syncRoot,
		access:               access,
		provider:             provider,
		watcher:              watcher,
		reader:               reader,
		cancels:              map[string]context.CancelFunc{},
		placeholderInflight:  map[string]*cloudFilesPlaceholderFetch{},
		placeholderFetched:   map[string]time.Time{},
		projectedDirectories: map[string]map[string]cloudPlaceholderInfo{},
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

func (h *cloudFilesHydrator) OnFetchPlaceholders(localPath string) (resultErr error) {
	cleanLocalPath := filepath.Clean(localPath)
	shouldFetch, inflight := h.beginPlaceholderFetch(cleanLocalPath)
	if inflight != nil {
		<-inflight.done
		return inflight.err
	}
	if !shouldFetch {
		return nil
	}
	defer func() {
		h.finishPlaceholderFetch(cleanLocalPath, resultErr)
	}()

	virtualPath, valid := cloudFilesLocalPathToVirtualChecked(h.syncRoot, localPath)
	if !valid {
		return fmt.Errorf(
			"resolve Cloud Files placeholder path %q under %q",
			localPath,
			h.syncRoot,
		)
	}
	h.access.noteDirectoryActivity(virtualPath)
	log.Printf(
		"[mount/cloud-files] fetch-placeholders local=%q virtual=%q",
		localPath,
		virtualPath,
	)
	items, err := h.access.listRemoteDirectoryMetadata(context.Background(), virtualPath)
	if err != nil {
		return fmt.Errorf("list remote directory %q: %w", virtualPath, err)
	}
	placeholders := cloudFilesMetadataDirectoryPlaceholders(items, h.access.metadataNamespaceID())
	log.Printf(
		"[mount/cloud-files] fetch-placeholders-done local=%q virtual=%q count=%d",
		localPath,
		virtualPath,
		len(placeholders),
	)
	if h.hasProjectedDirectory(localPath) {
		if err := h.refreshProjectedDirectory(localPath, placeholders); err != nil {
			return err
		}
		return nil
	}

	h.watcher.RememberPlaceholders(localPath, placeholders)
	if err := h.provider.CreatePlaceholders(localPath, placeholders); err != nil {
		h.watcher.watchPlaceholderDirectories(localPath, placeholders)
		return err
	}
	h.rememberProjectedDirectory(localPath, placeholders)
	h.watcher.watchPlaceholderDirectories(localPath, placeholders)
	return nil
}
