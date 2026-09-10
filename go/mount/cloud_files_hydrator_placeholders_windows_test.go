//go:build windows && cgo

package mount

import (
	"errors"
	"reflect"
	"testing"
)

func TestPlaceholderFetchGateCachesAndCoalesces(t *testing.T) {
	hydrator := &cloudFilesHydrator{
		placeholderInflight: map[string]*cloudFilesPlaceholderFetch{},
		placeholderFetched:  map[string]cloudFilesPlaceholderCache{},
	}

	shouldFetch, cached, wait := hydrator.beginPlaceholderFetch(`C:\root`)
	if !shouldFetch || wait != nil {
		t.Fatalf("expected first fetch to proceed")
	}
	if cached != nil {
		t.Fatalf("first cached placeholders = %#v, want nil", cached)
	}

	shouldFetch, cached, wait = hydrator.beginPlaceholderFetch(`C:\root`)
	if shouldFetch || wait == nil {
		t.Fatalf("expected concurrent fetch to coalesce")
	}
	if cached != nil {
		t.Fatalf("coalesced cached placeholders = %#v, want nil", cached)
	}

	want := []cloudPlaceholderInfo{{RelativePath: "deep", IsDirectory: true}}
	hydrator.finishPlaceholderFetch(`C:\root`, want, nil)
	<-wait.done
	if !reflect.DeepEqual(wait.placeholders, want) {
		t.Fatalf("coalesced placeholders = %#v, want %#v", wait.placeholders, want)
	}

	shouldFetch, cached, wait = hydrator.beginPlaceholderFetch(`C:\root`)
	if shouldFetch || wait != nil {
		t.Fatalf("expected recent fetch to use cache")
	}
	if !reflect.DeepEqual(cached, want) {
		t.Fatalf("cached placeholders = %#v, want %#v", cached, want)
	}
	cached[0].RelativePath = "mutated"
	_, nextCached, _ := hydrator.beginPlaceholderFetch(`C:\root`)
	if !reflect.DeepEqual(nextCached, want) {
		t.Fatalf("cached placeholders leaked caller mutation: %#v", nextCached)
	}
}

func TestPlaceholderFetchGatePropagatesCoalescedFailure(t *testing.T) {
	hydrator := &cloudFilesHydrator{
		placeholderInflight: map[string]*cloudFilesPlaceholderFetch{},
		placeholderFetched:  map[string]cloudFilesPlaceholderCache{},
	}

	shouldFetch, cached, wait := hydrator.beginPlaceholderFetch(`C:\root\docs`)
	if !shouldFetch || wait != nil {
		t.Fatal("expected first fetch to proceed")
	}
	if cached != nil {
		t.Fatalf("first cached placeholders = %#v, want nil", cached)
	}
	shouldFetch, cached, wait = hydrator.beginPlaceholderFetch(`C:\root\docs`)
	if shouldFetch || wait == nil {
		t.Fatal("expected second fetch to wait")
	}
	if cached != nil {
		t.Fatalf("coalesced cached placeholders = %#v, want nil", cached)
	}

	wantErr := errors.New("remote listing failed")
	hydrator.finishPlaceholderFetch(`C:\root\docs`, nil, wantErr)
	<-wait.done
	if !errors.Is(wait.err, wantErr) {
		t.Fatalf("coalesced error = %v, want %v", wait.err, wantErr)
	}

	shouldFetch, cached, wait = hydrator.beginPlaceholderFetch(`C:\root\docs`)
	if !shouldFetch || wait != nil {
		t.Fatal("failed fetch must not mark the directory as populated")
	}
	if cached != nil {
		t.Fatalf("failed fetch cached placeholders = %#v, want nil", cached)
	}
}

func TestPlaceholderTransferPlanCarriesCallbackEntries(t *testing.T) {
	items := []cloudPlaceholderInfo{
		{RelativePath: "deep", IsDirectory: true},
		{RelativePath: "report.txt", FileSize: 12},
	}
	plan := cloudFilesPlaceholderTransferPlanFor(items, nil)
	if plan.totalCount != int64(len(items)) {
		t.Fatalf("transfer total = %d, want %d", plan.totalCount, len(items))
	}
	if !reflect.DeepEqual(plan.placeholders, items) {
		t.Fatalf("transfer placeholders = %#v, want %#v", plan.placeholders, items)
	}
	if !plan.stopOnError || !plan.disableOnDemandPopulation {
		t.Fatalf("transfer plan flags = %#v, want final successful transfer flags", plan)
	}

	failure := cloudFilesPlaceholderTransferPlanFor(items, errors.New("listing failed"))
	if failure.totalCount != 0 || len(failure.placeholders) != 0 ||
		failure.stopOnError || failure.disableOnDemandPopulation {
		t.Fatalf("failed transfer plan = %#v, want empty error completion", failure)
	}
}
