package s3

import (
	"context"
	"testing"
)

func TestForgetTerminalTransfersScopesAndSkipsRunning(t *testing.T) {
	resetTransferMonitorForTest()
	startTransfer("history-a", "upload", "bucket-a", "a", "", 0, func() {})
	finishTransfer("history-a", nil)
	startTransfer("history-b", "upload", "bucket-b", "b", "", 0, func() {})
	finishTransfer("history-b", context.Canceled)
	startTransfer("history-running", "upload", "bucket-a", "running", "", 0, func() {})

	if removed := ForgetTerminalTransfers(nil, "", "bucket-a"); removed != 1 {
		t.Fatalf("removed scoped terminal transfers = %d; want 1", removed)
	}
	if _, ok := GetTransferSnapshot("history-a"); ok {
		t.Fatal("scoped terminal snapshot was retained")
	}
	if _, ok := GetTransferSnapshot("history-b"); !ok {
		t.Fatal("other-bucket terminal snapshot was removed")
	}
	if _, ok := GetTransferSnapshot("history-running"); !ok {
		t.Fatal("running snapshot was removed")
	}
}
