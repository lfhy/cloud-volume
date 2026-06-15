// Baidu Pan backend tests pin the path rewriting rules used by list/upload/move flows.
package storage

import (
	"strings"
	"testing"

	xpanfile "github.com/lfhy/xpan/file"
	xpantypes "github.com/lfhy/xpan/types"

	storageconfig "remote-storage/go/config"
)

func TestBaiduPanCleanKey(t *testing.T) {
	t.Parallel()

	cases := map[string]string{
		"":             "",
		"/":            "",
		"docs":         "docs",
		"/docs//a.txt": "docs/a.txt",
		"docs/../a":    "a",
	}
	for input, want := range cases {
		if got := baiduPanCleanKey(input); got != want {
			t.Fatalf("clean key %q: got %q want %q", input, got, want)
		}
	}
}

func TestBaiduPanMoveTarget(t *testing.T) {
	t.Parallel()

	dir, name := baiduPanMoveTarget("folder/report.txt")
	if dir != "/folder" || name != "report.txt" {
		t.Fatalf("unexpected move target dir=%q name=%q", dir, name)
	}

	rootDir, rootName := baiduPanMoveTarget("top.txt")
	if rootDir != "/" || rootName != "top.txt" {
		t.Fatalf("unexpected root move target dir=%q name=%q", rootDir, rootName)
	}
}

func TestBaiduPanTempUploadPath(t *testing.T) {
	t.Parallel()

	got := baiduPanTempUploadPath("archive.zip", "folder/archive.zip")
	if !strings.HasPrefix(got, baiduPanUploadRoot+"/") {
		t.Fatalf("temp upload path should stay under upload root, got %q", got)
	}
	if !strings.HasSuffix(got, "-archive.zip") {
		t.Fatalf("temp upload path should preserve the filename suffix, got %q", got)
	}
}

func TestBaiduPanListItemSkipsSelfEntry(t *testing.T) {
	t.Parallel()

	item := &xpanfile.ListItem{
		Path:  "/AI/cpa",
		Name:  "cpa",
		IsDir: xpantypes.BoolIntTrue,
	}
	if !baiduPanListItemIsSelf("/AI/cpa", item) {
		t.Fatalf("expected current directory entry to be treated as self")
	}
}

func TestBaiduPanListItemKeepsReturnedPath(t *testing.T) {
	t.Parallel()

	item := &xpanfile.ListItem{
		Path:  "/AI/cpa/report.txt",
		Name:  "ignored.txt",
		IsDir: xpantypes.BoolIntFalse,
	}
	if got := baiduPanListItemKey("/AI/cpa", item); got != "AI/cpa/report.txt" {
		t.Fatalf("list item key = %q, want %q", got, "AI/cpa/report.txt")
	}
}

func TestBaiduPanListItemFallsBackToName(t *testing.T) {
	t.Parallel()

	item := &xpanfile.ListItem{Name: "child", IsDir: xpantypes.BoolIntTrue}
	info := baiduPanObjectInfo("/AI/cpa", item)
	if info.Key != "AI/cpa/child/" {
		t.Fatalf("fallback directory key = %q, want %q", info.Key, "AI/cpa/child/")
	}
}

func TestBaiduPanBucketLabel(t *testing.T) {
	t.Parallel()

	cfg := storageconfig.RemoteStorageConfig{
		StorageType:      storageconfig.StorageTypeBaiduPan,
		MappedBucketName: "我的百度网盘",
	}
	if got := baiduPanBucketLabel(cfg); got != "我的百度网盘" {
		t.Fatalf("bucket label: got %q", got)
	}
}

func TestBaiduPanDirectoryUploadConcurrency(t *testing.T) {
	t.Parallel()

	backend := baiduPanBackend{}
	if got := backend.DirectoryUploadConcurrency(); got != 2 {
		t.Fatalf("directory upload concurrency = %d, want 2", got)
	}
}
