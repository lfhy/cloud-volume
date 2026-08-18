// Task projection tests pin journal coalescing and dependency wire fields.
package metadata

import (
	"strings"
	"testing"
	"time"
)

func TestListTasksFoldsMkdirAndRenames(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	dir, err := service.CreateDirectory(rootInode, "draft", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(dir, rootInode, "final", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(dir, rootInode, "latest", WriteOptions{Origin: "test"}); err != nil {
		t.Fatal(err)
	}
	tasks, err := service.ListTasks()
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 1 {
		t.Fatalf("tasks = %+v, want one folded task", tasks)
	}
	task := tasks[0]
	if task.Type != OpMkdir || task.NewName != "latest" || len(task.SourceSeqs) != 3 {
		t.Fatalf("folded task = %+v", task)
	}
	if task.ID != TaskID(service.NamespaceID(), 1) || task.PhysicalSnapshot != "" {
		t.Fatalf("task identity/snapshot = %+v", task)
	}
	if task.Kind != "mkdir" || task.Status != "waiting" || task.TargetPath != "latest" || task.DisplayPath != "latest" {
		t.Fatalf("mkdir wire fields = %+v", task)
	}
}

func TestListTasksWriteDependencyAndPhysicalSnapshot(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	dir, err := service.CreateDirectory(rootInode, "dir", WriteOptions{Origin: "test"})
	if err != nil {
		t.Fatal(err)
	}
	_, ref, err := service.StageWriteForName(dir, "file.txt", 7, strings.NewReader("hello"), 5)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(dir, "file.txt", ref, WriteOptions{Origin: "page"}); err != nil {
		t.Fatal(err)
	}
	tasks, err := service.ListTasks()
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 2 {
		t.Fatalf("tasks = %+v, want mkdir + write", tasks)
	}
	write := tasks[1]
	if write.Type != OpWrite || write.ContentGeneration != 7 || write.PhysicalSeq != 2 || write.PhysicalSnapshot != physicalTaskID(service.NamespaceID(), 2) {
		t.Fatalf("write mapping = %+v", write)
	}
	if write.State != TaskStateBlocked || len(write.Dependencies) != 1 || write.DependencySeqs[0] != 1 {
		t.Fatalf("write dependency = %+v", write)
	}
	if write.Kind != "write" || write.Status != "blocked" || write.Phase != "dependency" || write.BlockedReason == "" || len(write.PhysicalTaskIDs) != 1 {
		t.Fatalf("write wire fields = %+v", write)
	}
}

func TestListTasksDoesNotBlockSiblingMkdir(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	if _, err := service.CreateDirectory(rootInode, "one", WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(rootInode, "two", WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	tasks, err := service.ListTasks()
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 2 || tasks[1].State != TaskStatePending || len(tasks[1].Dependencies) != 0 {
		t.Fatalf("sibling mkdir dependency = %+v", tasks)
	}
}

func TestListTasksDoesNotFoldStartedMkdir(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	dir, err := service.CreateDirectory(rootInode, "draft", WriteOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) { op.State = OpStateRunning })
	}); err != nil {
		t.Fatal(err)
	}
	if err := service.Rename(dir, rootInode, "final", WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	tasks, err := service.ListTasks()
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 2 || tasks[0].State != TaskStateRunning || tasks[1].Type != OpRename {
		t.Fatalf("started mkdir was folded: %+v", tasks)
	}
}

func TestListTasksUsesDistinctIDsForMixedGroupStates(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	_, first, err := service.StageWriteForName(rootInode, "rapid.txt", 1, strings.NewReader("first"), 5)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "rapid.txt", first, WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) { op.State = OpStateRunning })
	}); err != nil {
		t.Fatal(err)
	}
	_, second, err := service.StageWriteForName(rootInode, "rapid.txt", 2, strings.NewReader("second"), 6)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Write(rootInode, "rapid.txt", second, WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	tasks, err := service.ListTasks()
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 2 || tasks[0].ID == tasks[1].ID {
		t.Fatalf("mixed lifecycle tasks reused an ID: %+v", tasks)
	}
	if tasks[0].SourceSeqs[0] != 1 || tasks[1].SourceSeqs[0] != 2 {
		t.Fatalf("mixed lifecycle source sequences = %+v", tasks)
	}
}

func TestJournalSequenceDoesNotReuseAfterHistoryClear(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	if _, err := service.CreateDirectory(rootInode, "old", WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := service.store.update(func(tx boltTxT) error {
		return replaceOp(tx, 1, func(op *Op) {
			op.State = OpStateApplied
			op.AppliedAtUnixNano = time.Now().Add(-time.Hour).UnixNano()
		})
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := service.ClearTaskHistory(time.Now()); err != nil {
		t.Fatal(err)
	}
	if _, err := service.CreateDirectory(rootInode, "new", WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	var seq uint64
	if err := service.store.view(func(tx boltTxT) error {
		return tx.Bucket([]byte(bucketJournal)).ForEach(func(key, _ []byte) error {
			seq = decodeUint64(key)
			return nil
		})
	}); err != nil {
		t.Fatal(err)
	}
	if seq != 2 {
		t.Fatalf("journal sequence reused after clear: %d", seq)
	}
}

func TestManagerTaskAPIsReturnNamespaceGroup(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	if _, err := service.CreateDirectory(rootInode, "dir", WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	manager := NewManager(t.TempDir())
	manager.services[service.NamespaceID()] = &managedService{service: service}
	group, err := manager.ListTaskGroup(service.NamespaceID())
	if err != nil {
		t.Fatal(err)
	}
	if group.Namespace != service.NamespaceID() || group.Summary.Total != 1 || len(group.Tasks) != 1 {
		t.Fatalf("task group = %+v", group)
	}
	if _, err := manager.GetTask(service.NamespaceID(), group.Tasks[0].ID); err != nil {
		t.Fatal(err)
	}
}

func TestGetTaskRejectsUnqualifiedID(t *testing.T) {
	service := newTestService(t, newFakeBackend())
	if _, err := service.CreateDirectory(rootInode, "dir", WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if _, err := service.GetTask("1"); err == nil {
		t.Fatal("expected namespace-qualified ID lookup to fail")
	}
}
