// Task control tests pin rollback, scheduling controls, and conservative cancellation.
package metadata

import (
	"context"
	"errors"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

func TestCancelTaskRollsBackPendingMkdirAndRename(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	dir, err := service.CreateDirectory(rootInode, "draft", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(dir, rootInode, "final", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	task, err := service.GetTask(TaskID(service.NamespaceID(), 1))
	if err != nil {
		t.Fatal(err)
	}
	if len(task.SourceSeqs) != 2 {
		t.Fatalf("task source sequences = %+v", task)
	}
	canceled, err := service.CancelTask(task.ID)
	if err != nil {
		t.Fatal(err)
	}
	if canceled.State != TaskStateCanceled || len(canceled.SourceSeqs) != 2 {
		t.Fatalf("canceled task = %+v", canceled)
	}
	if _, err := service.Resolve(rootInode, "final"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("canceled directory remained in Desired tree: %v", err)
	}
	if status := service.Status(); status.InodeCount != 1 || status.PendingOps != 0 {
		t.Fatalf("rollback status = %+v", status)
	}
}

func TestCancelTaskCleansPendingWriteContent(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	_, ref, err := service.WritePath(context.Background(), "draft.txt", strings.NewReader("pending bytes"), 13, WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	task, err := service.GetTask(TaskID(service.NamespaceID(), 1))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.CancelTask(task.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Resolve(rootInode, "draft.txt"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("canceled write remained in Desired tree: %v", err)
	}
	if status := service.Status(); status.PendingContent != 0 || status.InodeCount != 1 {
		t.Fatalf("write cleanup status = %+v", status)
	}
	for _, hash := range ref.Chunks {
		if _, err := os.Stat(service.chunkPath(hash)); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("zero-link chunk %q was retained: %v", hash, err)
		}
	}
}

func TestCancelTaskCleansEveryFoldedPendingWrite(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	_, first, err := service.StageWriteForName(rootInode, "rapid.txt", 1, strings.NewReader("one"), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "rapid.txt", first, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	_, second, err := service.StageWriteForName(rootInode, "rapid.txt", 2, strings.NewReader("two"), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "rapid.txt", second, WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	tasks, err := service.ListTasks()
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 1 || len(tasks[0].SourceSeqs) != 2 {
		t.Fatalf("rapid writes were not folded: %+v", tasks)
	}
	if _, err := service.CancelTask(tasks[0].ID); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Resolve(rootInode, "rapid.txt"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("folded write remained in Desired tree: %v", err)
	}
	if status := service.Status(); status.InodeCount != 1 || status.PendingContent != 0 || status.PendingOps != 0 {
		t.Fatalf("folded write cleanup status = %+v", status)
	}
}

func TestRetryAndTriggerTask(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "retry", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	id := TaskID(service.NamespaceID(), 1)
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) {
			op.State = OpStateFailed
			op.Retry = 2
			op.LastError = "temporary"
		})
	}); err != nil {
		t.Fatal(err)
	}
	retried, err := service.RetryTask(id)
	if err != nil {
		t.Fatal(err)
	}
	if retried.State != TaskStatePending || retried.Retry != 0 || retried.LastError != "" {
		t.Fatalf("retried task = %+v", retried)
	}
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) { op.NextAttemptUnixNano = time.Now().Add(time.Hour).UnixNano() })
	}); err != nil {
		t.Fatal(err)
	}
	before := time.Now().UnixNano()
	triggered, err := service.TriggerTask(id)
	if err != nil {
		t.Fatal(err)
	}
	if triggered.NextAttemptUnixNs < before || triggered.NextAttemptUnixNs > time.Now().Add(time.Second).UnixNano() {
		t.Fatalf("trigger did not make task due now: %+v", triggered)
	}
}

type cancelBlockingBackend struct {
	*fakeBackend
	started chan struct{}
	ended   chan struct{}
	once    sync.Once
}

func (b *cancelBlockingBackend) CreateDirectory(ctx context.Context, _, _, _ string) error {
	b.once.Do(func() { close(b.started) })
	<-ctx.Done()
	close(b.ended)
	return ctx.Err()
}

// HeadObject keeps the provider outcome unknown after cancellation so this
// test exercises the durable reconciling state rather than a valid immediate
// canceled result when a probe can prove the directory was never created.
func (b *cancelBlockingBackend) HeadObject(context.Context, string, string) (storageops.ObjectInfo, error) {
	return storageops.ObjectInfo{}, errors.New("temporary provider outage")
}

func TestCancelRunningTaskRequestsReconciliationAndHistoryStays(t *testing.T) {
	backend := &cancelBlockingBackend{
		fakeBackend: newFakeBackend(), started: make(chan struct{}), ended: make(chan struct{}),
	}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	if _, err := service.CreateDirectory(rootInode, "running", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	select {
	case <-backend.started:
	case <-time.After(time.Second):
		t.Fatal("worker did not start provider operation")
	}
	id := TaskID(service.NamespaceID(), 1)
	canceled, err := service.CancelTask(id)
	if err != nil {
		t.Fatal(err)
	}
	if (canceled.State != TaskStateCancelRequested && canceled.State != TaskStateReconciling) || canceled.Cancelable {
		t.Fatalf("running cancel state = %+v", canceled)
	}
	select {
	case <-backend.ended:
	case <-time.After(time.Second):
		t.Fatal("cancel did not reach provider context")
	}
	cleared, err := service.ClearTaskHistory(time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if cleared != 0 {
		t.Fatalf("running/reconciling history was removed: %d", cleared)
	}
	deadline := time.Now().Add(time.Second)
	for {
		task, err := service.GetTask(id)
		if err == nil && task.State == TaskStateReconciling {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("reconciling task disappeared or changed: %+v, %v", task, err)
		}
		time.Sleep(10 * time.Millisecond)
	}
}
