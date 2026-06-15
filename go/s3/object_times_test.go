// Object time tests keep S3 timestamps aligned with the local display timezone.
package s3

import (
	"testing"
	"time"
)

func TestFormatObjectLastModifiedConvertsUTCToLocal(t *testing.T) {
	originalLocal := time.Local
	localZone := time.FixedZone("UTC+8", 8*60*60)
	time.Local = localZone
	t.Cleanup(func() {
		time.Local = originalLocal
	})

	value := time.Date(2026, time.June, 8, 12, 34, 56, 0, time.UTC)
	if got := formatObjectLastModified(&value); got != "2026-06-08 20:34:56" {
		t.Fatalf("formatObjectLastModified() = %q, want %q", got, "2026-06-08 20:34:56")
	}
}

func TestFormatObjectLastModifiedHandlesNil(t *testing.T) {
	t.Parallel()

	if got := formatObjectLastModified(nil); got != "" {
		t.Fatalf("formatObjectLastModified(nil) = %q, want empty", got)
	}
}
