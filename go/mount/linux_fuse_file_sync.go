//go:build linux

// Linux FUSE autosync helpers detect append-heavy writes and pre-upload full parts in the background.
package mount

import (
	"context"
	"log"
	"os"

	s3ops "remote-storage/go/s3"
)

func (h *linuxFuseFileHandle) noteWriteRange(off int64, written int) {
	if written <= 0 {
		return
	}
	end := off + int64(written)
	if !h.sequentialDirty {
		h.sequentialDirty = true
		h.sequentialEnd = end
		return
	}
	if off == h.sequentialEnd {
		h.sequentialEnd = end
		return
	}
	h.autoSyncDisabled = true
	h.autoSyncQueued = false
	h.sequentialEnd = maxInt64(h.sequentialEnd, end)
}

func (h *linuxFuseFileHandle) scheduleAutoSyncLocked() {
	readySize := h.autoSyncReadySizeLocked()
	if readySize <= 0 || h.autoSyncQueued {
		return
	}
	h.autoSyncQueued = true
	go h.runAutoSync(readySize)
}

func (h *linuxFuseFileHandle) autoSyncReadySizeLocked() int64 {
	if !h.autoSyncEnabled() || h.autoSyncDisabled || !h.sequentialDirty {
		return 0
	}
	partSize := s3ops.ChooseMultipartUploadPartSize(maxInt64(fileSize(h.localPath), h.sequentialEnd))
	readySize := (h.sequentialEnd / partSize) * partSize
	if readySize <= h.autoSyncedSize {
		return 0
	}
	return readySize
}

func (h *linuxFuseFileHandle) runAutoSync(readySize int64) {
	err := h.autoSyncReadyRange(context.Background(), readySize)

	h.mu.Lock()
	defer h.mu.Unlock()

	h.autoSyncQueued = false
	if err != nil {
		log.Printf(
			"[mount/linux-file] auto-sync path=%q local_path=%q ready_size=%d error=%v",
			h.virtualPath,
			h.localPath,
			readySize,
			err,
		)
		h.autoSyncDisabled = true
		return
	}
	if readySize > h.autoSyncedSize {
		h.autoSyncedSize = readySize
	}
	nextReadySize := h.autoSyncReadySizeLocked()
	if nextReadySize <= 0 {
		return
	}
	h.autoSyncQueued = true
	go h.runAutoSync(nextReadySize)
}

func (h *linuxFuseFileHandle) autoSyncReadyRange(ctx context.Context, readySize int64) error {
	if readySize <= 0 {
		return nil
	}

	h.mu.Lock()
	if h.released || h.autoSyncDisabled || !h.autoSyncEnabled() {
		h.mu.Unlock()
		return nil
	}
	file := h.file
	localPath := h.localPath
	virtualPath := h.virtualPath
	access := h.access
	h.mu.Unlock()

	info, err := file.Stat()
	if err != nil {
		return err
	}
	if info.Size() < readySize {
		return nil
	}
	if err := file.Sync(); err != nil {
		return err
	}
	meta, err := os.Stat(localPath)
	if err != nil {
		return err
	}
	if meta.Size() < readySize {
		return nil
	}
	return access.uploadPartialPrefix(
		ctx,
		virtualPath,
		localPath,
		meta,
		readySize,
	)
}

func (h *linuxFuseFileHandle) autoSyncEnabled() bool {
	return h != nil && h.access != nil && h.access.autoSync
}

func maxInt64(left, right int64) int64 {
	if left > right {
		return left
	}
	return right
}
