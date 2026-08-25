// Bulk task-sync tests pin quiet-period bypass without weakening worker ordering.
package metadata

import (
	"testing"
	"time"
)

func TestTriggerPendingTasksKeepsParentDependencyOrder(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	parent, err := service.CreateDirectory(rootInode, "parent", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(parent, "child", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}

	triggered, err := service.TriggerPendingTasks()
	if err != nil {
		t.Fatal(err)
	}
	if triggered != 2 {
		t.Fatalf("triggered %d task groups, want 2", triggered)
	}
	worker := newClaimWorker(service)
	claimed := worker.claimDue()
	if len(claimed) != 1 || claimed[0].Seq != 1 {
		t.Fatalf("first bulk-sync claim = %+v, want parent only", claimed)
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
	if len(claimed) != 1 || claimed[0].Seq != 2 {
		t.Fatalf("second bulk-sync claim = %+v, want child after parent", claimed)
	}
	worker.releaseInode(claimed[0].InodeID)
}

func TestTriggerPendingTasksKeepsSameInodeOrder(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	inode, err := service.CreateDirectory(rootInode, "draft", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(inode, rootInode, "final", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}

	triggered, err := service.TriggerPendingTasks()
	if err != nil {
		t.Fatal(err)
	}
	if triggered != 1 {
		t.Fatalf("triggered %d folded task groups, want 1", triggered)
	}
	worker := newClaimWorker(service)
	claimed := worker.claimDue()
	if len(claimed) != 1 || claimed[0].Seq != 1 {
		t.Fatalf("first same-inode claim = %+v, want mkdir", claimed)
	}
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) {
			op.State = OpStateApplied
			op.AppliedAtUnixNano = nowUnix()
		})
	}); err != nil {
		t.Fatal(err)
	}
	worker.releaseInode(inode)

	claimed = worker.claimDue()
	if len(claimed) != 1 || claimed[0].Seq != 2 {
		t.Fatalf("second same-inode claim = %+v, want rename", claimed)
	}
	worker.releaseInode(claimed[0].InodeID)
}

func TestTriggerPendingTasksNotifiesSubscribers(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	service.SetQuietPeriod(time.Hour)
	if _, err := service.CreateDirectory(rootInode, "queued", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	stop, changes := service.SubscribeTaskChanges()
	defer stop()
	if _, err := service.TriggerPendingTasks(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-changes:
	case <-time.After(time.Second):
		t.Fatal("bulk trigger did not notify task subscribers")
	}
}
