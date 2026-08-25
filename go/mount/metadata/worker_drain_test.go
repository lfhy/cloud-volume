// Drain tests cover the worker's interaction with an in-flight provider call.
package metadata

import (
	"context"
	"testing"
	"time"
)

func TestVerificationContextHasBoundedDeadline(t *testing.T) {
	ctx, cancel := verificationContext(context.Background())
	defer cancel()
	deadline, ok := ctx.Deadline()
	if !ok {
		t.Fatal("verification context has no deadline")
	}
	if remaining := time.Until(deadline); remaining <= 0 || remaining > workerVerificationTimeout {
		t.Fatalf("verification deadline remaining=%v, timeout=%v", remaining, workerVerificationTimeout)
	}
}

type blockingCreateBackend struct {
	*fakeBackend
	started chan struct{}
	release chan struct{}
}

func (b *blockingCreateBackend) CreateDirectory(ctx context.Context, bucket, prefix, name string) error {
	close(b.started)
	select {
	case <-b.release:
		return b.fakeBackend.CreateDirectory(ctx, bucket, prefix, name)
	case <-ctx.Done():
		return ctx.Err()
	}
}

func TestWorkerDrainWaitsForRunningOperation(t *testing.T) {
	backend := &blockingCreateBackend{
		fakeBackend: newFakeBackend(), started: make(chan struct{}), release: make(chan struct{}),
	}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	if _, err := service.CreateDirectory(rootInode, "running", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := &Worker{service: service, wake: make(chan struct{}, 1), running: map[uint64]struct{}{}}
	workerDone := make(chan struct{})
	go func() {
		worker.runDueOnce(context.Background())
		close(workerDone)
	}()
	select {
	case <-backend.started:
	case <-time.After(time.Second):
		t.Fatal("worker did not enter provider call")
	}

	drainDone := make(chan error, 1)
	go func() { drainDone <- worker.Drain(context.Background()) }()
	select {
	case err := <-drainDone:
		t.Fatalf("drain returned while operation was running: %v", err)
	case <-time.After(50 * time.Millisecond):
	}
	close(backend.release)
	select {
	case <-workerDone:
	case <-time.After(time.Second):
		t.Fatal("worker did not finish after provider release")
	}
	select {
	case err := <-drainDone:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("drain did not finish after worker")
	}
}
