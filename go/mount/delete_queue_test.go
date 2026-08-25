// Delete queue tests keep remote delete intent aligned with path mutations.
package mount

import "testing"

func TestDeleteQueueRebaseMovesPendingAndRunningTargets(t *testing.T) {
	pending := &pendingDelete{taskID: "pending", virtualPath: "old/child.txt"}
	running := &pendingDelete{taskID: "running", virtualPath: "old/nested/item.txt"}
	queue := &deleteQueue{
		entries: map[string]*pendingDelete{pending.virtualPath: pending},
		running: map[string]*pendingDelete{running.taskID: running},
	}

	queue.rebase("old", "new", true)
	if queue.entries["new/child.txt"] != pending || queue.entries["old/child.txt"] != nil {
		t.Fatalf("pending delete did not rebase: %+v", queue.entries)
	}
	if running.virtualPath != "new/nested/item.txt" {
		t.Fatalf("running delete target = %q, want new/nested/item.txt", running.virtualPath)
	}
}

func TestDeleteQueueRebaseDoesNotRewriteStartedDelete(t *testing.T) {
	running := &pendingDelete{
		taskID:          "running",
		virtualPath:     "old/item.txt",
		providerStarted: true,
	}
	queue := &deleteQueue{running: map[string]*pendingDelete{running.taskID: running}}

	queue.rebase("old", "new", true)
	if running.virtualPath != "old/item.txt" {
		t.Fatalf("started delete target = %q, want old/item.txt", running.virtualPath)
	}
}
