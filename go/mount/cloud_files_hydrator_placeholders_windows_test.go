//go:build windows && cgo

package mount

import (
	"testing"
	"time"
)

func TestPlaceholderFetchGateCachesAndCoalesces(t *testing.T) {
	hydrator := &cloudFilesHydrator{
		placeholderInflight: map[string]chan struct{}{},
		placeholderFetched:  map[string]time.Time{},
	}

	shouldFetch, wait := hydrator.beginPlaceholderFetch(`C:\root`)
	if !shouldFetch || wait != nil {
		t.Fatalf("expected first fetch to proceed")
	}

	shouldFetch, wait = hydrator.beginPlaceholderFetch(`C:\root`)
	if shouldFetch || wait == nil {
		t.Fatalf("expected concurrent fetch to coalesce")
	}

	hydrator.finishPlaceholderFetch(`C:\root`, true)

	shouldFetch, wait = hydrator.beginPlaceholderFetch(`C:\root`)
	if shouldFetch || wait != nil {
		t.Fatalf("expected recent fetch to use cache")
	}
}
