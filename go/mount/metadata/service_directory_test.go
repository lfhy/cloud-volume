// Directory helper tests prevent provider listings from flattening deep keys.
package metadata

import (
	"context"
	"sort"
	"strings"
	"testing"

	storageops "remote-storage/go/storage"
)

type deepListingBackend struct{ *fakeBackend }

func (b *deepListingBackend) ListObjectsPage(
	_ context.Context,
	_ string,
	prefix string,
	_ string,
	_ int32,
) (storageops.ObjectPage, error) {
	switch strings.Trim(prefix, "/") {
	case "":
		return storageops.ObjectPage{Items: []storageops.ObjectInfo{
			{Key: "dir/", IsDir: true},
			{Key: "dir/child.txt", Size: 1},
		}}, nil
	case "dir":
		return storageops.ObjectPage{Items: []storageops.ObjectInfo{
			{Key: "dir/child.txt", Size: 1},
			{Key: "dir/nested/deep.txt", Size: 2},
		}}, nil
	default:
		return storageops.ObjectPage{Items: []storageops.ObjectInfo{}}, nil
	}
}

func TestListDirectoryUsesPathLevelHelper(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/docs/"] = storageops.ObjectInfo{Key: "docs/", IsDir: true}
	backend.objects["/docs/report.txt"] = storageops.ObjectInfo{Key: "docs/report.txt", Size: 3}
	service := newTestService(t, backend)

	items, err := service.ListDirectory(context.Background(), "docs")
	if err != nil {
		t.Fatalf("list directory: %v", err)
	}
	if len(items) != 1 || items[0].Key != "docs/report.txt" {
		t.Fatalf("path-level directory items = %+v", items)
	}
}

func TestMaterializeDirectoryRejectsDeepListingEntries(t *testing.T) {
	service := newTestService(t, &deepListingBackend{fakeBackend: newFakeBackend()})
	rootItems, err := service.ListDirectory(context.Background(), "")
	if err != nil {
		t.Fatalf("list root: %v", err)
	}
	if len(rootItems) != 1 || rootItems[0].Key != "dir/" {
		t.Fatalf("deep root entry was flattened: %+v", rootItems)
	}

	items, err := service.ListDirectory(context.Background(), "dir")
	if err != nil {
		t.Fatalf("list dir: %v", err)
	}
	sort.Slice(items, func(i, j int) bool { return items[i].Key < items[j].Key })
	if len(items) != 1 || items[0].Key != "dir/child.txt" {
		t.Fatalf("deep child entry was flattened: %+v", items)
	}
}
