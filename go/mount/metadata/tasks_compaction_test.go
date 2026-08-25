// Task-compaction tests pin the reverse-scan dependency barrier and bulk path.
package metadata

import (
	"fmt"
	"testing"
	"time"
)

func TestClearTaskHistoryRetainsTerminalParentReferencedByUnsettledOp(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	parent, err := service.CreateDirectory(rootInode, "finished-parent", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(parent, "pending-child", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) {
			op.State = OpStateApplied
			op.AppliedAtUnixNano = time.Now().Add(-time.Minute).UnixNano()
		})
	}); err != nil {
		t.Fatal(err)
	}

	cleared, err := service.ClearTaskHistory(time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if cleared != 0 {
		t.Fatalf("cleared %d terminal tasks despite later parent reference", cleared)
	}
	if _, err := service.GetTask(TaskID(service.NamespaceID(), 1)); err != nil {
		t.Fatalf("protected history disappeared: %v", err)
	}
}

func TestClearTaskHistoryCompactsLargeTerminalBatch(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	const taskCount = 256
	finishedAt := time.Now().Add(-time.Minute).UnixNano()
	if err := service.store.update(func(tx boltTxT) error {
		for index := 0; index < taskCount; index++ {
			if err := appendOp(tx, Op{
				TaskGroupID:       fmt.Sprintf("compaction-%03d", index),
				Type:              OpMkdir,
				InodeID:           uint64(index + 2),
				NewParent:         rootInode,
				NewName:           fmt.Sprintf("finished-%03d", index),
				State:             OpStateApplied,
				Origin:            "test",
				CreatedAtUnixNano: finishedAt,
				AppliedAtUnixNano: finishedAt,
			}); err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}

	cleared, err := service.ClearTaskHistory(time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if cleared != taskCount {
		t.Fatalf("cleared %d tasks, want %d", cleared, taskCount)
	}
	tasks, err := service.ListTasks()
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 0 {
		t.Fatalf("terminal batch remained in journal: %+v", tasks)
	}
}
