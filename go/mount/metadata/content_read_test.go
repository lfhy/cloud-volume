// Pending content read tests pin chunk-backed bytes before remote confirmation.
package metadata

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestReadPendingRangeUsesStagedChunks(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	inode, ref, err := service.WritePath(
		context.Background(), "draft.txt", strings.NewReader("0123456789"), 10,
		WriteOptions{Origin: "test"},
	)
	if err != nil {
		t.Fatal(err)
	}
	data, handled, err := service.ReadPendingRange(context.Background(), inode, 3, 4)
	if err != nil || !handled || string(data) != "3456" {
		t.Fatalf("pending range = %q handled=%t err=%v", data, handled, err)
	}
	var rebuilt bytes.Buffer
	handled, err = service.CopyPendingContent(context.Background(), inode, &rebuilt)
	if err != nil || !handled || rebuilt.String() != "0123456789" {
		t.Fatalf("pending copy = %q handled=%t err=%v", rebuilt.String(), handled, err)
	}
	if err := service.retireContent(inode, ref.Generation); err != nil {
		t.Fatal(err)
	}
	data, handled, err = service.ReadPendingRange(context.Background(), inode, 0, 1)
	if err != nil && !errors.Is(err, ErrNotFound) {
		t.Fatal(err)
	}
	if handled || len(data) != 0 {
		t.Fatalf("retired content remained readable: data=%q handled=%t err=%v", data, handled, err)
	}
}
