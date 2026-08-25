// Worker execution tests preserve remote ordering when drain overlaps polling.
package metadata

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

type blockingReplacementDeleteBackend struct {
	*fakeBackend
	deleteStarted chan struct{}
	deleteRelease chan struct{}
	moveStarted   chan struct{}
	deleteOnce    sync.Once
	moveOnce      sync.Once
	releaseOnce   sync.Once
}

func (b *blockingReplacementDeleteBackend) DeleteObject(
	ctx context.Context, bucket, key string, isDir bool, taskID string,
) error {
	b.deleteOnce.Do(func() { close(b.deleteStarted) })
	select {
	case <-b.deleteRelease:
		return b.fakeBackend.DeleteObject(ctx, bucket, key, isDir, taskID)
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (b *blockingReplacementDeleteBackend) MoveObject(
	ctx context.Context, bucket, source, target string, isDir bool, taskID string,
) error {
	b.moveOnce.Do(func() { close(b.moveStarted) })
	return b.fakeBackend.MoveObject(ctx, bucket, source, target, isDir, taskID)
}

func (b *blockingReplacementDeleteBackend) releaseDelete() {
	b.releaseOnce.Do(func() { close(b.deleteRelease) })
}

func TestWorkerSerializesOverlappingDrainAndPollPasses(t *testing.T) {
	backend := &blockingReplacementDeleteBackend{
		fakeBackend: newFakeBackend(), deleteStarted: make(chan struct{}),
		deleteRelease: make(chan struct{}), moveStarted: make(chan struct{}),
	}
	defer backend.releaseDelete()
	backend.objects["/source.txt"] = storageops.ObjectInfo{Key: "source.txt", Size: 2}
	backend.objects["/victim.txt"] = storageops.ObjectInfo{Key: "victim.txt", Size: 1}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	if _, err := service.ListPage(context.Background(), rootInode, "", 10); err != nil {
		t.Fatal(err)
	}
	source, err := service.Resolve(rootInode, "source.txt")
	if err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(source, rootInode, "victim.txt", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	setRemoteQuietForTest(service, time.Now().Add(-time.Second).UnixNano())
	worker := newClaimWorker(service)
	firstDone := make(chan struct{})
	go func() {
		worker.runDueOnce(context.Background())
		close(firstDone)
	}()
	select {
	case <-backend.deleteStarted:
	case <-time.After(time.Second):
		t.Fatal("first pass did not start replacement delete")
	}

	secondDone := make(chan struct{})
	go func() {
		worker.runDueOnceIgnoringRemoteQuiet(context.Background())
		close(secondDone)
	}()
	select {
	case <-backend.moveStarted:
		t.Fatal("second pass moved source before replacement delete completed")
	case <-time.After(100 * time.Millisecond):
	}

	backend.releaseDelete()
	for _, done := range []<-chan struct{}{firstDone, secondDone} {
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Fatal("worker pass did not finish")
		}
	}
	select {
	case <-backend.moveStarted:
	case <-time.After(time.Second):
		t.Fatal("move did not start after replacement delete")
	}
	if target, ok := backend.objects["/victim.txt"]; !ok || target.Size != 2 {
		t.Fatalf("replacement rename target = %+v, want moved source", backend.objects)
	}
}

func TestWorkerDrainContextReturnsWhileAnotherPassRuns(t *testing.T) {
	backend := &blockingCreateBackend{
		fakeBackend: newFakeBackend(), started: make(chan struct{}), release: make(chan struct{}),
	}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Nanosecond)
	if _, err := service.CreateDirectory(rootInode, "running", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	worker := newClaimWorker(service)
	passDone := make(chan struct{})
	go func() {
		worker.runDueOnce(context.Background())
		close(passDone)
	}()
	select {
	case <-backend.started:
	case <-time.After(time.Second):
		t.Fatal("background pass did not enter provider call")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 350*time.Millisecond)
	defer cancel()
	drainDone := make(chan error, 1)
	go func() { drainDone <- worker.Drain(ctx) }()
	select {
	case err := <-drainDone:
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("drain error = %v, want context deadline", err)
		}
	case <-time.After(time.Second):
		close(backend.release)
		t.Fatal("drain blocked behind an active pass mutex")
	}
	close(backend.release)
	select {
	case <-passDone:
	case <-time.After(time.Second):
		t.Fatal("background pass did not finish after provider release")
	}
}
