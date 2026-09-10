//go:build windows && cgo

// Cloud Files placeholder callback gating avoids Explorer-triggered refresh loops.
package mount

import (
	"path/filepath"
	"time"
)

const windowsCloudFilesPlaceholderRefreshTTL = 3 * time.Second

type cloudFilesPlaceholderFetch struct {
	done         chan struct{}
	err          error
	placeholders []cloudPlaceholderInfo
}

type cloudFilesPlaceholderCache struct {
	fetchedAt    time.Time
	placeholders []cloudPlaceholderInfo
}

func (h *cloudFilesHydrator) beginPlaceholderFetch(
	localPath string,
) (bool, []cloudPlaceholderInfo, *cloudFilesPlaceholderFetch) {
	h.placeholderMu.Lock()
	defer h.placeholderMu.Unlock()

	cleanLocalPath := filepath.Clean(localPath)
	if wait, ok := h.placeholderInflight[cleanLocalPath]; ok {
		return false, nil, wait
	}
	if cached, ok := h.placeholderFetched[cleanLocalPath]; ok &&
		time.Since(cached.fetchedAt) < windowsCloudFilesPlaceholderRefreshTTL {
		return false, cloneCloudPlaceholderInfos(cached.placeholders), nil
	}
	flight := &cloudFilesPlaceholderFetch{done: make(chan struct{})}
	h.placeholderInflight[cleanLocalPath] = flight
	return true, nil, nil
}

func (h *cloudFilesHydrator) finishPlaceholderFetch(
	localPath string,
	placeholders []cloudPlaceholderInfo,
	fetchErr error,
) {
	h.placeholderMu.Lock()
	defer h.placeholderMu.Unlock()

	cleanLocalPath := filepath.Clean(localPath)
	if flight, ok := h.placeholderInflight[cleanLocalPath]; ok {
		flight.err = fetchErr
		flight.placeholders = cloneCloudPlaceholderInfos(placeholders)
		close(flight.done)
		delete(h.placeholderInflight, cleanLocalPath)
	}
	if fetchErr == nil {
		h.placeholderFetched[cleanLocalPath] = cloudFilesPlaceholderCache{
			fetchedAt:    time.Now(),
			placeholders: cloneCloudPlaceholderInfos(placeholders),
		}
	} else {
		delete(h.placeholderFetched, cleanLocalPath)
	}
}
