// Metadata dispatch tests cover wire adaptation and fallback gating for the unified read view.
package main

import (
	"encoding/json"
	"errors"
	"testing"

	bucketmetadata "remote-storage/go/mount/metadata"

	storageconfig "remote-storage/go/config"
)

func TestListObjectPageFallsBackWithoutProfileID(t *testing.T) {
	// A config without a persisted identity must not error or create a namespace;
	// the caller falls back to the provider-direct listing path.
	page, handled, err := listObjectPageFromMetadata(objectPageArgs{
		Config: storageconfig.RemoteStorageConfig{StorageType: storageconfig.StorageTypeS3},
		Bucket: "bucket",
	})
	if err != nil {
		t.Fatalf("metadata listing error: %v", err)
	}
	if handled {
		t.Fatalf("handled = true without profileId, page=%+v", page)
	}
}

func TestObjectPageAdapterKeepsWireShape(t *testing.T) {
	page := bucketmetadata.Page{
		Items: []bucketmetadata.Object{
			{Key: "dir/", IsDir: true},
			{Key: "a.txt", Size: 12},
		},
		NextToken: "next",
	}
	adapted := objectPageAdapter(page)
	if len(adapted.Items) != 2 || !adapted.Items[0].IsDir || adapted.Items[1].Size != 12 {
		t.Fatalf("unexpected adapter output: %+v", adapted)
	}
	if adapted.NextToken != "next" {
		t.Fatalf("next token = %q", adapted.NextToken)
	}
	// The wire shape must stay JSON-compatible with the Dart ObjectListPage model.
	encoded, err := json.Marshal(adapted)
	if err != nil {
		t.Fatalf("marshal adapted page: %v", err)
	}
	if string(encoded) == "" {
		t.Fatal("empty encoding")
	}
}

func TestStaleCursorErrorUnwraps(t *testing.T) {
	wrapped := staleCursorError{inner: bucketmetadata.ErrStaleCursor}
	if !errors.Is(wrapped, bucketmetadata.ErrStaleCursor) {
		t.Fatal("stale cursor error must unwrap to metadata.ErrStaleCursor")
	}
}

