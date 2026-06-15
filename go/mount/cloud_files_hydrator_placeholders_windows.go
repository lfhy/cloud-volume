//go:build windows && cgo

// Cloud Files placeholder callback gating avoids Explorer-triggered refresh loops.
package mount

import (
	"path/filepath"
	"time"
)

const windowsCloudFilesPlaceholderRefreshTTL = 3 * time.Second

func (h *cloudFilesHydrator) beginPlaceholderFetch(localPath string) (bool, <-chan struct{}) {
	h.placeholderMu.Lock()
	defer h.placeholderMu.Unlock()

	cleanLocalPath := filepath.Clean(localPath)
	if wait, ok := h.placeholderInflight[cleanLocalPath]; ok {
		return false, wait
	}
	if lastFetch, ok := h.placeholderFetched[cleanLocalPath]; ok &&
		time.Since(lastFetch) < windowsCloudFilesPlaceholderRefreshTTL {
		return false, nil
	}
	done := make(chan struct{})
	h.placeholderInflight[cleanLocalPath] = done
	return true, nil
}

func (h *cloudFilesHydrator) finishPlaceholderFetch(localPath string, success bool) {
	h.placeholderMu.Lock()
	defer h.placeholderMu.Unlock()

	cleanLocalPath := filepath.Clean(localPath)
	if done, ok := h.placeholderInflight[cleanLocalPath]; ok {
		close(done)
		delete(h.placeholderInflight, cleanLocalPath)
	}
	if success {
		h.placeholderFetched[cleanLocalPath] = time.Now()
	} else {
		delete(h.placeholderFetched, cleanLocalPath)
	}
}
