// Task projection exposes a read-only, coalesced view of journal work.
package metadata

import (
	"encoding/base64"
	"fmt"
	"sort"
	"strings"
	"time"
)

// TaskID returns the namespace-qualified stable ID for the default journal
// group created by a sequence. Group IDs are encoded so provider/user labels
// cannot make the namespace portion ambiguous.
func TaskID(namespace string, seq uint64) string {
	return taskIDForGroup(namespace, fmt.Sprintf("journal-%d", seq))
}

func taskIDForGroup(namespace, group string) string {
	encoded := base64.RawURLEncoding.EncodeToString([]byte(group))
	return fmt.Sprintf("sync:%s:g%s", namespace, encoded)
}

// taskIDForEntry keeps a coalesced group's stable ID when it has one visible
// state. Mixed lifecycle segments get a source-sequence suffix so controls
// cannot accidentally mutate a concurrently running sibling segment.
func taskIDForEntry(namespace, group string, seq uint64, segmented bool) string {
	id := taskIDForGroup(namespace, group)
	if !segmented {
		return id
	}
	return fmt.Sprintf("%s:s%d", id, seq)
}

func taskIDGroup(taskID string) (namespace, group string, ok bool) {
	trimmed := strings.TrimSpace(taskID)
	if strings.HasPrefix(trimmed, "sync:") {
		rest := strings.TrimPrefix(trimmed, "sync:")
		separator := strings.IndexByte(rest, ':')
		if separator <= 0 || separator == len(rest)-1 {
			return "", "", false
		}
		namespace = rest[:separator]
		encoded := strings.TrimPrefix(rest[separator+1:], "g")
		if segment := strings.LastIndex(encoded, ":s"); segment > 0 {
			encoded = encoded[:segment]
		}
		decoded, err := base64.RawURLEncoding.DecodeString(encoded)
		if err != nil || len(decoded) == 0 {
			return "", "", false
		}
		return namespace, string(decoded), true
	}
	// Accept the pre-projection namespace:seq form for one development cycle.
	separator := strings.LastIndexByte(trimmed, ':')
	if separator <= 0 || strings.TrimSpace(trimmed[separator+1:]) == "" {
		return "", "", false
	}
	return trimmed[:separator], "journal-" + strings.TrimSpace(trimmed[separator+1:]), true
}

func taskIDSegment(taskID string) uint64 {
	trimmed := strings.TrimSpace(taskID)
	if !strings.HasPrefix(trimmed, "sync:") {
		return 0
	}
	index := strings.LastIndex(trimmed, ":s")
	if index < 0 || index+2 == len(trimmed) {
		return 0
	}
	var seq uint64
	_, _ = fmt.Sscanf(trimmed[index+2:], "%d", &seq)
	return seq
}

func taskIDNamespace(taskID string) string {
	if namespace, _, ok := taskIDGroup(taskID); ok {
		return namespace
	}
	return ""
}

type taskEntry struct {
	op        Op
	ops       []Op
	created   int64
	typeOp    OpType
	seqs      []uint64
	kinds     []string
	lastSeq   uint64
	deps      []*taskEntry
	id        string
	segmented bool
}

// ListTasks derives effective work directly from the journal snapshot.
func (s *Service) ListTasks() ([]Task, error) {
	s.operationMu.RLock()
	defer s.operationMu.RUnlock()
	remoteQuietUntil := s.remoteQuietDeadline()
	var ops []Op
	var inodes map[uint64]Inode
	err := s.store.view(func(tx boltTxT) error {
		inodes = map[uint64]Inode{}
		if err := tx.Bucket([]byte(bucketInodes)).ForEach(func(_, value []byte) error {
			var inode Inode
			if err := decodeJSON(value, &inode); err != nil {
				return err
			}
			inodes[inode.ID] = inode
			return nil
		}); err != nil {
			return err
		}
		return tx.Bucket([]byte(bucketJournal)).ForEach(func(_, value []byte) error {
			var op Op
			if err := decodeJSON(value, &op); err != nil {
				return err
			}
			ops = append(ops, op)
			return nil
		})
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(ops, func(i, j int) bool { return ops[i].Seq < ops[j].Seq })
	entries := make([]*taskEntry, 0, len(ops))
	consumed := make([]bool, len(ops))
	for i := 0; i < len(ops); {
		if consumed[i] {
			i++
			continue
		}
		op := ops[i]
		entry := &taskEntry{op: op, ops: []Op{op}, created: op.CreatedAtUnixNano, typeOp: op.Type, seqs: []uint64{op.Seq}, kinds: []string{taskKind(op.Type)}, lastSeq: op.Seq}
		if op.TaskGroupID != "" && taskStateFoldable(op.State) {
			for j := i + 1; j < len(ops); j++ {
				if consumed[j] || ops[j].TaskGroupID != op.TaskGroupID || ops[j].State != op.State || !canFoldTaskOps(entry.op, ops[j]) {
					continue
				}
				entry.op = ops[j]
				entry.ops = append(entry.ops, ops[j])
				entry.seqs = append(entry.seqs, ops[j].Seq)
				entry.kinds = append(entry.kinds, taskKind(ops[j].Type))
				entry.lastSeq = ops[j].Seq
				consumed[j] = true
			}
		}
		entries = append(entries, entry)
		i++
	}
	groupEntries := make(map[string]int, len(entries))
	for _, entry := range entries {
		group := entry.op.TaskGroupID
		if group == "" {
			group = fmt.Sprintf("journal-%d", entry.seqs[0])
		}
		groupEntries[group]++
	}
	for _, entry := range entries {
		group := entry.op.TaskGroupID
		if group == "" {
			group = fmt.Sprintf("journal-%d", entry.seqs[0])
		}
		entry.segmented = groupEntries[group] > 1
		entry.id = taskIDForEntry(s.NamespaceID(), group, entry.seqs[0], entry.segmented)
	}
	// Earlier same-inode work and parent mkdir/rename work are explicit deps.
	for _, entry := range entries {
		for _, prior := range entries {
			if prior == entry || prior.lastSeq >= entry.op.Seq {
				continue
			}
			if !taskStateUnsettled(prior.op.State) {
				continue
			}
			if prior.op.InodeID == entry.op.InodeID ||
				(prior.op.Type == OpMkdir && prior.op.InodeID == entry.op.NewParent) ||
				(prior.op.Type == OpRename && prior.op.InodeID == entry.op.NewParent) {
				entry.deps = append(entry.deps, prior)
			}
		}
	}
	result := make([]Task, 0, len(entries))
	for _, entry := range entries {
		task := s.taskFromEntry(entry, inodes, remoteQuietUntil)
		result = append(result, task)
	}
	return result, nil
}

func (s *Service) taskFromEntry(entry *taskEntry, inodes map[uint64]Inode, remoteQuietUntil int64) Task {
	op := entry.op
	namespace := s.NamespaceID()
	groupID := op.TaskGroupID
	if groupID == "" {
		groupID = fmt.Sprintf("journal-%d", entry.seqs[0])
	}
	taskID := entry.id
	if taskID == "" {
		taskID = taskIDForEntry(namespace, groupID, entry.seqs[0], entry.segmented)
	}
	nextAttempt := op.NextAttemptUnixNano
	if op.State == OpStatePending && !op.SkipQuiet && remoteQuietUntil > nextAttempt {
		nextAttempt = remoteQuietUntil
	}
	task := Task{ID: taskID, Namespace: namespace, NamespaceID: namespace, ProfileID: s.store.namespace.Config.ProfileID, Bucket: s.store.namespace.Bucket, Seq: entry.seqs[0], TaskGroupID: groupID, LastSeq: entry.lastSeq, SourceSeqs: append([]uint64(nil), entry.seqs...), SourceKinds: append([]string(nil), entry.kinds...), Type: entry.typeOp, Kind: taskKind(entry.typeOp), Source: "metadata", InodeID: op.InodeID, OldParent: op.OldParent, OldName: op.OldName, NewParent: op.NewParent, NewName: op.NewName, ContentGeneration: op.ContentGeneration, Retry: op.Retry, LastError: op.LastError, NextAttemptUnixNs: nextAttempt, Origin: op.Origin, CreatedAtUnixNs: entry.created, AppliedAtUnixNs: op.AppliedAtUnixNano, CanceledAtUnixNs: op.CanceledAtUnixNano}
	for index, raw := range entry.ops {
		kind := taskKind(raw.Type)
		sourcePath := taskPath(inodes, raw.OldParent, raw.OldName)
		targetPath := taskPath(inodes, raw.NewParent, raw.NewName)
		if raw.Type == OpWrite || raw.Type == OpMkdir {
			sourcePath = targetPath
		}
		task.Events = append(task.Events, TaskEvent{
			Sequence: raw.Seq, Kind: kind, State: opStateWire(raw.State),
			SourcePath: sourcePath, TargetPath: targetPath, Detail: raw.LastError,
			Folded:    index != len(entry.ops)-1,
			CreatedAt: time.Unix(0, raw.CreatedAtUnixNano).UTC().Format(time.RFC3339Nano),
		})
	}
	if task.Type == OpMkdir || task.Type == OpWrite {
		task.ParentID, task.Name = op.NewParent, op.NewName
	}
	if task.Type == OpRename {
		task.ParentID, task.Name = op.NewParent, op.NewName
	}
	task.Path = taskPath(inodes, task.NewParent, task.NewName)
	if task.Type == OpRename {
		task.SourcePath = taskPath(inodes, op.OldParent, op.OldName)
		task.TargetPath = task.Path
	}
	if op.Type == OpDelete {
		task.SourcePath = taskPath(inodes, op.OldParent, op.OldName)
	}
	if task.TargetPath == "" {
		task.TargetPath = task.Path
	}
	if task.SourcePath == "" && task.Type == OpWrite {
		task.SourcePath = task.Path
	}
	task.DisplayPath = task.TargetPath
	if task.DisplayPath == "" {
		task.DisplayPath = task.SourcePath
	}
	if task.Type != OpMkdir {
		task.PhysicalSeq = entry.seqs[0]
		for _, seq := range entry.seqs {
			task.PhysicalTaskIDs = append(task.PhysicalTaskIDs, physicalTaskID(namespace, seq))
		}
		task.PhysicalSnapshot = task.PhysicalTaskIDs[0]
	}
	switch op.State {
	case OpStateRunning:
		task.State = TaskStateRunning
	case OpStateVerifying:
		task.State = TaskStateVerifying
	case OpStateCancelRequested:
		task.State = TaskStateCancelRequested
	case OpStateFailed:
		if strings.Contains(strings.ToLower(op.LastError), "conflict") {
			task.State = TaskStateConflict
		} else {
			task.State = TaskStateFailed
		}
	case OpStateApplied:
		task.State = TaskStateDone
	case OpStateCanceled:
		task.State = TaskStateCanceled
	case OpStateReconciling:
		task.State = TaskStateReconciling
	default:
		task.State = TaskStatePending
	}
	for _, dep := range entry.deps {
		depID := dep.id
		if depID == "" {
			depGroup := dep.op.TaskGroupID
			if depGroup == "" {
				depGroup = fmt.Sprintf("journal-%d", dep.seqs[0])
			}
			depID = taskIDForEntry(s.NamespaceID(), depGroup, dep.seqs[0], dep.segmented)
		}
		task.Dependencies = append(task.Dependencies, depID)
		task.DependencySeqs = append(task.DependencySeqs, dep.seqs[0])
	}
	if task.State == TaskStatePending && len(task.Dependencies) > 0 {
		task.State = TaskStateBlocked
	} else if task.State == TaskStatePending && task.Retry > 0 && task.NextAttemptUnixNs > time.Now().UnixNano() {
		task.State = TaskStateRetryWait
	}
	task.setWireState()
	return task
}

func taskStateFoldable(state OpState) bool {
	return state == OpStatePending || state == OpStateCanceled || state == OpStateApplied
}

func taskStateUnsettled(state OpState) bool {
	return opStateUnsettled(state)
}

func canFoldTaskOps(first, next Op) bool {
	if first.InodeID != next.InodeID {
		return false
	}
	if first.Type == OpMkdir {
		return next.Type == OpRename
	}
	if first.Type == OpRename {
		return next.Type == OpRename
	}
	return first.Type == next.Type
}

func (t *Task) setWireState() {
	now := time.Now()
	switch t.State {
	case TaskStateRunning:
		t.Status, t.Phase = "running", "provider"
	case TaskStateVerifying:
		t.Status, t.Phase = "verifying", "verification"
	case TaskStateCancelRequested:
		t.Status, t.Phase = "cancel_requested", "provider"
		t.PhaseDetail = "cancel requested; waiting for provider context to stop"
	case TaskStateFailed:
		t.Status, t.Phase, t.Retryable = "failed", "provider", true
	case TaskStateConflict:
		t.Status, t.Phase, t.Retryable = "conflict", "verification", true
	case TaskStateDone:
		t.Status, t.Phase = "done", "history"
		if t.AppliedAtUnixNs != 0 {
			t.FinishedAt = time.Unix(0, t.AppliedAtUnixNs).UTC().Format(time.RFC3339Nano)
		}
	case TaskStateCanceled:
		t.Status, t.Phase = "canceled", "history"
		if t.CanceledAtUnixNs != 0 {
			t.FinishedAt = time.Unix(0, t.CanceledAtUnixNs).UTC().Format(time.RFC3339Nano)
		}
	case TaskStateReconciling:
		t.Status, t.Phase = "reconciling", "provider"
		t.PhaseDetail = "cancel requested; remote outcome is being reconciled"
	case TaskStateBlocked:
		t.Status, t.Phase = "blocked", "dependency"
		t.BlockedReason = "waiting for journal dependencies"
	default:
		t.Status, t.Phase = "waiting", "provider"
		if t.NextAttemptUnixNs > now.UnixNano() {
			t.NextRetryAt = time.Unix(0, t.NextAttemptUnixNs).UTC().Format(time.RFC3339Nano)
			if t.Retry > 0 {
				t.Status, t.Phase = "retry_wait", "provider"
			} else {
				t.Phase = "quiet_period"
			}
		}
	}
	if t.CreatedAtUnixNs != 0 {
		t.CreatedAt = time.Unix(0, t.CreatedAtUnixNs).UTC().Format(time.RFC3339Nano)
		t.UpdatedAt = t.CreatedAt
	}
	t.Cancelable = t.State == TaskStatePending || t.State == TaskStateBlocked || t.State == TaskStateRunning
	t.Triggerable = t.State == TaskStatePending || t.State == TaskStateBlocked
}

func taskKind(value OpType) string {
	switch value {
	case OpMkdir:
		return "mkdir"
	case OpWrite:
		return "write"
	case OpRename:
		return "rename"
	case OpDelete:
		return "delete"
	default:
		return "unknown"
	}
}

func opStateWire(state OpState) string {
	switch state {
	case OpStatePending:
		return "pending"
	case OpStateRunning:
		return "running"
	case OpStateApplied:
		return "done"
	case OpStateFailed:
		return "failed"
	case OpStateCanceled:
		return "canceled"
	case OpStateReconciling:
		return "reconciling"
	case OpStateVerifying:
		return "verifying"
	case OpStateCancelRequested:
		return "cancel_requested"
	default:
		return "unknown"
	}
}

func taskPath(inodes map[uint64]Inode, parent uint64, name string) string {
	if strings.TrimSpace(name) == "" {
		return ""
	}
	parts := []string{name}
	for depth := 0; parent != rootInode && parent != 0 && depth < 1024; depth++ {
		inode, ok := inodes[parent]
		if !ok {
			break
		}
		if inode.DesiredName != "" {
			parts = append(parts, inode.DesiredName)
		}
		parent = inode.DesiredParentID
	}
	for i, j := 0, len(parts)-1; i < j; i, j = i+1, j-1 {
		parts[i], parts[j] = parts[j], parts[i]
	}
	return strings.Join(parts, "/")
}

// GetTask returns one effective task by its namespace-qualified ID.
func (s *Service) GetTask(id string) (Task, error) {
	tasks, err := s.ListTasks()
	if err != nil {
		return Task{}, err
	}
	for _, task := range tasks {
		if task.ID == id {
			return task, nil
		}
	}
	return Task{}, ErrNotFound
}

// ListTaskGroup returns tasks and their aggregate state from one consistent
// journal projection.
func (s *Service) ListTaskGroup() (TaskGroup, error) {
	tasks, err := s.ListTasks()
	if err != nil {
		return TaskGroup{}, err
	}
	group := TaskGroup{Namespace: s.NamespaceID(), Tasks: tasks}
	group.Summary = summarizeTasks(tasks)
	return group, nil
}

// Summary computes aggregate counts for the current task projection.
func (s *Service) TaskSummary() (TaskSummary, error) {
	tasks, err := s.ListTasks()
	if err != nil {
		return TaskSummary{}, err
	}
	return summarizeTasks(tasks), nil
}

func summarizeTasks(tasks []Task) TaskSummary {
	summary := TaskSummary{Total: len(tasks)}
	for _, task := range tasks {
		switch task.State {
		case TaskStatePending:
			summary.Pending++
		case TaskStateRetryWait, TaskStateCancelRequested, TaskStateVerifying, TaskStateReconciling:
			summary.Pending++
		case TaskStateRunning:
			summary.Running++
		case TaskStateBlocked:
			summary.Blocked++
		case TaskStateFailed:
			summary.Failed++
		}
	}
	return summary
}
