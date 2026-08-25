// Namespace quiet tests keep recursive local copy work off the provider.
package metadata

import (
	"context"
	"sync"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

func newClaimWorker(service *Service) *Worker {
	return &Worker{service: service, wake: make(chan struct{}, 1), running: map[uint64]struct{}{}}
}

func setRemoteQuietForTest(service *Service, until int64) {
	service.remoteQuietMu.Lock()
	service.remoteQuietUntilNano = until
	service.remoteQuietMu.Unlock()
}

func setOpAttemptForTest(t *testing.T, service *Service, seq uint64, attempt int64) {
	t.Helper()
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, seq, func(op *Op) { op.NextAttemptUnixNano = attempt })
	}); err != nil {
		t.Fatal(err)
	}
}

func TestNamespaceQuietDefersEarlierDueWorkAndProjectsDeadline(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "earlier", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	setOpAttemptForTest(t, service, 1, time.Now().Add(-time.Second).UnixNano())
	if _, err := service.CreateDirectory(rootInode, "later", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}

	deadline := service.remoteQuietDeadline()
	if deadline <= time.Now().UnixNano() {
		t.Fatalf("quiet deadline = %d, want future", deadline)
	}
	task, err := service.GetTask(TaskID(service.NamespaceID(), 1))
	if err != nil {
		t.Fatal(err)
	}
	if task.NextAttemptUnixNs != deadline || task.Phase != "quiet_period" {
		t.Fatalf("task did not expose namespace quiet: %+v, deadline=%d", task, deadline)
	}

	worker := newClaimWorker(service)
	if claimed := worker.claimDue(); len(claimed) != 0 {
		t.Fatalf("claimed during namespace quiet: %+v", claimed)
	}
	setRemoteQuietForTest(service, time.Now().Add(-time.Second).UnixNano())
	claimed := worker.claimDue()
	if len(claimed) != 1 || claimed[0].Seq != 1 {
		t.Fatalf("claim after quiet = %+v, want earlier op", claimed)
	}
	worker.releaseInode(claimed[0].InodeID)
}

func TestNamespaceQuietClaimsOneOperationPerPass(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "first", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(rootInode, "second", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	setOpAttemptForTest(t, service, 1, time.Now().Add(-time.Second).UnixNano())
	setOpAttemptForTest(t, service, 2, time.Now().Add(-time.Second).UnixNano())
	setRemoteQuietForTest(service, time.Now().Add(-time.Second).UnixNano())

	worker := newClaimWorker(service)
	claimed := worker.claimDue()
	if len(claimed) != 1 || claimed[0].Seq != 1 {
		t.Fatalf("first pass claimed %+v, want only first op", claimed)
	}
	worker.releaseInode(claimed[0].InodeID)
	claimed = worker.claimDue()
	if len(claimed) != 1 || claimed[0].Seq != 2 {
		t.Fatalf("second pass claimed %+v, want only second op", claimed)
	}
	worker.releaseInode(claimed[0].InodeID)
}

func TestTriggerQuietBypassIsOneShotAndKeepsDependencies(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	parent, err := service.CreateDirectory(rootInode, "parent", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(parent, "child", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	childTask := TaskID(service.NamespaceID(), 2)
	if _, err := service.TriggerTask(childTask); err != nil {
		t.Fatal(err)
	}

	worker := newClaimWorker(service)
	if claimed := worker.claimDue(); len(claimed) != 0 {
		t.Fatalf("triggered child bypassed parent dependency: %+v", claimed)
	}
	if _, err := service.TriggerTask(TaskID(service.NamespaceID(), 1)); err != nil {
		t.Fatal(err)
	}
	claimed := worker.claimDue()
	if len(claimed) != 1 || claimed[0].Seq != 1 {
		t.Fatalf("triggered parent claim = %+v", claimed)
	}
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) {
			op.State = OpStateApplied
			op.AppliedAtUnixNano = nowUnix()
		})
	}); err != nil {
		t.Fatal(err)
	}
	worker.releaseInode(parent)

	claimed = worker.claimDue()
	if len(claimed) != 1 || claimed[0].Seq != 2 || claimed[0].SkipQuiet {
		t.Fatalf("triggered child claim = %+v", claimed)
	}
	worker.releaseInode(claimed[0].InodeID)
	var child Op
	if err := service.store.view(func(tx boltTxT) error {
		var getErr error
		child, getErr = getOp(tx, 2)
		return getErr
	}); err != nil {
		t.Fatal(err)
	}
	if child.SkipQuiet {
		t.Fatalf("claim did not consume one-shot SkipQuiet: %+v", child)
	}
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 2, func(op *Op) {
			op.State = OpStatePending
			op.NextAttemptUnixNano = time.Now().Add(-time.Second).UnixNano()
		})
	}); err != nil {
		t.Fatal(err)
	}
	if claimed := worker.claimDue(); len(claimed) != 0 {
		t.Fatalf("requeued child bypassed a later namespace quiet: %+v", claimed)
	}
}

func TestDrainBypassesNamespaceQuietOnly(t *testing.T) {
	backend := newFakeBackend()
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "drain", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	setOpAttemptForTest(t, service, 1, time.Now().Add(-time.Second).UnixNano())
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, ok := backend.objects["/drain/"]; !ok {
		t.Fatalf("drain left due local operation behind: %+v", backend.objects)
	}
}

type drainObserveBackend struct {
	*fakeBackend
	created chan struct{}
	once    sync.Once
}

func (b *drainObserveBackend) CreateDirectory(ctx context.Context, bucket, prefix, name string) error {
	err := b.fakeBackend.CreateDirectory(ctx, bucket, prefix, name)
	b.once.Do(func() { close(b.created) })
	return err
}

func TestDrainDoesNotSleepPastDueOperationHeldByNamespaceQuiet(t *testing.T) {
	backend := &drainObserveBackend{fakeBackend: newFakeBackend(), created: make(chan struct{})}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "earlier", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(rootInode, "later", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	setOpAttemptForTest(t, service, 1, time.Now().Add(-time.Second).UnixNano())

	worker := &Worker{
		service: service, wake: make(chan struct{}, 1), stop: make(chan struct{}), running: map[uint64]struct{}{},
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- worker.Drain(ctx) }()
	select {
	case <-backend.created:
	case <-time.After(time.Second):
		cancel()
		close(worker.stop)
		t.Fatal("drain slept past a due operation held only by namespace quiet")
	}
	cancel()
	close(worker.stop)
	select {
	case err := <-done:
		if err != context.Canceled {
			t.Fatalf("drain error = %v, want context cancellation", err)
		}
	case <-time.After(time.Second):
		t.Fatal("drain did not observe cancellation after its forced pass")
	}
}

func TestDrainWaitsForFutureDependencyAfterForcedPass(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	parent, err := service.CreateDirectory(rootInode, "parent", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(parent, "child", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	setRemoteQuietForTest(service, time.Now().Add(-time.Second).UnixNano())
	if err := service.store.update(func(tx boltTxT) error {
		if err := replaceOp(tx, 1, func(op *Op) {
			op.NextAttemptUnixNano = time.Now().Add(20 * time.Millisecond).UnixNano()
		}); err != nil {
			return err
		}
		return replaceOp(tx, 2, func(op *Op) {
			op.NextAttemptUnixNano = time.Now().Add(-time.Second).UnixNano()
		})
	}); err != nil {
		t.Fatal(err)
	}
	worker := NewWorker(service)
	defer worker.Stop()
	if err := worker.Drain(context.Background()); err != nil {
		t.Fatalf("drain returned before future parent dependency: %v", err)
	}
}

func TestNamespaceQuietDoesNotBlockReconciliation(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "verify", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) {
			op.State = OpStateVerifying
			op.NextAttemptUnixNano = time.Now().Add(-time.Second).UnixNano()
		})
	}); err != nil {
		t.Fatal(err)
	}
	worker := newClaimWorker(service)
	claimed := worker.claimDue()
	if len(claimed) != 1 || claimed[0].State != OpStateVerifying {
		t.Fatalf("quiet barrier blocked verification: %+v", claimed)
	}
	worker.releaseInode(claimed[0].InodeID)
}

func TestReopenRestoresRemainingNamespaceQuiet(t *testing.T) {
	root := t.TempDir() + "/metadata"
	cacheRoot := t.TempDir() + "/cache"
	namespace := Namespace{ID: "test", Root: root, CacheRoot: cacheRoot, Bucket: "bucket"}
	store, err := OpenStore(namespace)
	if err != nil {
		t.Fatal(err)
	}
	service := NewService(store, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "reopen", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := store.Close(); err != nil {
		t.Fatal(err)
	}

	reopened, err := OpenStore(namespace)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	resumed := NewService(reopened, newFakeBackend())
	resumed.SetQuietPeriod(time.Hour)
	setOpAttemptForTest(t, resumed, 1, time.Now().Add(-time.Second).UnixNano())
	if deadline := resumed.remoteQuietDeadline(); deadline <= time.Now().UnixNano() {
		t.Fatalf("reopened quiet deadline = %d, want future", deadline)
	}
	if claimed := newClaimWorker(resumed).claimDue(); len(claimed) != 0 {
		t.Fatalf("reopened worker bypassed remaining quiet: %+v", claimed)
	}
}

func TestRenameReplacementSharesMutationQuietDeadline(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["/source.txt"] = storageops.ObjectInfo{Key: "source.txt", Size: 1}
	backend.objects["/victim.txt"] = storageops.ObjectInfo{Key: "victim.txt", Size: 1}
	service := newTestService(t, backend)
	service.SetQuietPeriod(time.Hour)
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
	var deleted, renamed Op
	if err := service.store.view(func(tx boltTxT) error {
		var getErr error
		deleted, getErr = getOp(tx, 1)
		if getErr != nil {
			return getErr
		}
		renamed, getErr = getOp(tx, 2)
		return getErr
	}); err != nil {
		t.Fatal(err)
	}
	if deleted.Type != OpDelete || renamed.Type != OpRename || deleted.NextAttemptUnixNano != renamed.NextAttemptUnixNano {
		t.Fatalf("replacement operation deadlines differ: delete=%+v rename=%+v", deleted, renamed)
	}
}
