// Task projection exposes a read-only, coalesced view of journal work.
package metadata

import (
	"encoding/base64"
	"fmt"
	"sort"
	"strings"
	"time"
)

// TaskState is the stable wire state for one effective task.
type TaskState string

const (
	TaskStatePending         TaskState = "pending"
	TaskStateRunning         TaskState = "running"
	TaskStateBlocked         TaskState = "blocked"
	TaskStateVerifying       TaskState = "verifying"
	TaskStateRetryWait       TaskState = "retry_wait"
	TaskStateFailed          TaskState = "failed"
	TaskStateConflict        TaskState = "conflict"
	TaskStateDone            TaskState = "done"
	TaskStateCancelRequested TaskState = "cancel_requested"
	TaskStateCanceled        TaskState = "canceled"
	TaskStateReconciling     TaskState = "reconciling"
)

// Task is an effective journal operation. SourceSeqs records journal entries
// folded into this task; PhysicalSnapshot maps work to the worker transfer ID.
type Task struct {
	ID                string    `json:"id"`
	Namespace         string    `json:"namespace"`
	NamespaceID       string    `json:"namespaceId"`
	ProfileID         string    `json:"profileId,omitempty"`
	Bucket            string    `json:"bucket,omitempty"`
	Seq               uint64    `json:"seq"`
	TaskGroupID       string    `json:"taskGroupId,omitempty"`
	LastSeq           uint64    `json:"lastSeq"`
	SourceSeqs        []uint64  `json:"sourceSeqs,omitempty"`
	Type              OpType    `json:"type"`
	State             TaskState `json:"state"`
	Kind              string    `json:"kind"`
	Status            string    `json:"status"`
	Source            string    `json:"source"`
	InodeID           uint64    `json:"inodeId"`
	ParentID          uint64    `json:"parentId,omitempty"`
	Name              string    `json:"name,omitempty"`
	OldParent         uint64    `json:"oldParent,omitempty"`
	OldName           string    `json:"oldName,omitempty"`
	NewParent         uint64    `json:"newParent,omitempty"`
	NewName           string    `json:"newName,omitempty"`
	Path              string    `json:"path,omitempty"`
	SourcePath        string    `json:"sourcePath,omitempty"`
	TargetPath        string    `json:"targetPath,omitempty"`
	DisplayPath       string    `json:"displayPath,omitempty"`
	Phase             string    `json:"phase,omitempty"`
	PhaseDetail       string    `json:"phaseDetail,omitempty"`
	BlockedReason     string    `json:"blockedReason,omitempty"`
	Dependencies      []string  `json:"dependencies,omitempty"`
	DependencySeqs    []uint64  `json:"dependencySeqs,omitempty"`
	ContentGeneration uint64    `json:"contentGeneration,omitempty"`
	PhysicalSeq       uint64    `json:"physicalSeq,omitempty"`
	PhysicalSnapshot  string    `json:"physicalSnapshot,omitempty"`
	PhysicalTaskIDs   []string  `json:"physicalTaskIds,omitempty"`
	Retry             int       `json:"retry,omitempty"`
	LastError         string    `json:"lastError,omitempty"`
	NextAttemptUnixNs int64     `json:"nextAttemptUnixNs,omitempty"`
	Origin            string    `json:"origin,omitempty"`
	CreatedAtUnixNs   int64     `json:"createdAtUnixNs,omitempty"`
	AppliedAtUnixNs   int64     `json:"appliedAtUnixNs,omitempty"`
	CanceledAtUnixNs  int64     `json:"canceledAtUnixNs,omitempty"`
	CreatedAt         string    `json:"createdAt,omitempty"`
	UpdatedAt         string    `json:"updatedAt,omitempty"`
	FinishedAt        string    `json:"finishedAt,omitempty"`
	NextRetryAt       string    `json:"nextRetryAt,omitempty"`
	Cancelable        bool      `json:"cancelable"`
	Retryable         bool      `json:"retryable"`
	Triggerable       bool      `json:"triggerable"`
}

// TaskSummary gives callers aggregate counts without reinterpreting states.
type TaskSummary struct {
	Total   int `json:"total"`
	Pending int `json:"pending"`
	Running int `json:"running"`
	Blocked int `json:"blocked"`
	Failed  int `json:"failed"`
}

// TaskGroup is the namespace-level wire payload for a task-list refresh.
type TaskGroup struct {
	Namespace string      `json:"namespace"`
	Tasks     []Task      `json:"tasks"`
	Summary   TaskSummary `json:"summary"`
}

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

func taskIDNamespace(taskID string) string {
	if namespace, _, ok := taskIDGroup(taskID); ok {
		return namespace
	}
	return ""
}

type taskEntry struct {
	op      Op
	created int64
	typeOp  OpType
	seqs    []uint64
	lastSeq uint64
	deps    []*taskEntry
}

// ListTasks derives effective work directly from the journal snapshot.
func (s *Service) ListTasks() ([]Task, error) {
	s.operationMu.RLock()
	defer s.operationMu.RUnlock()
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
		entry := &taskEntry{op: op, created: op.CreatedAtUnixNano, typeOp: op.Type, seqs: []uint64{op.Seq}, lastSeq: op.Seq}
		if op.TaskGroupID != "" && taskStateFoldable(op.State) {
			for j := i + 1; j < len(ops); j++ {
				if consumed[j] || ops[j].TaskGroupID != op.TaskGroupID || ops[j].State != op.State || !canFoldTaskOps(entry.op, ops[j]) {
					continue
				}
				entry.op = ops[j]
				entry.seqs = append(entry.seqs, ops[j].Seq)
				entry.lastSeq = ops[j].Seq
				consumed[j] = true
			}
		}
		entries = append(entries, entry)
		i++
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
		task := s.taskFromEntry(entry, inodes)
		result = append(result, task)
	}
	return result, nil
}

func (s *Service) taskFromEntry(entry *taskEntry, inodes map[uint64]Inode) Task {
	op := entry.op
	namespace := s.NamespaceID()
	groupID := op.TaskGroupID
	if groupID == "" {
		groupID = fmt.Sprintf("journal-%d", entry.seqs[0])
	}
	task := Task{ID: taskIDForGroup(namespace, groupID), Namespace: namespace, NamespaceID: namespace, ProfileID: s.store.namespace.Config.ProfileID, Bucket: s.store.namespace.Bucket, Seq: entry.seqs[0], TaskGroupID: groupID, LastSeq: entry.lastSeq, SourceSeqs: append([]uint64(nil), entry.seqs...), Type: entry.typeOp, Kind: taskKind(entry.typeOp), Source: "metadata", InodeID: op.InodeID, OldParent: op.OldParent, OldName: op.OldName, NewParent: op.NewParent, NewName: op.NewName, ContentGeneration: op.ContentGeneration, Retry: op.Retry, LastError: op.LastError, NextAttemptUnixNs: op.NextAttemptUnixNano, Origin: op.Origin, CreatedAtUnixNs: entry.created, AppliedAtUnixNs: op.AppliedAtUnixNano, CanceledAtUnixNs: op.CanceledAtUnixNano}
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
			task.PhysicalTaskIDs = append(task.PhysicalTaskIDs, fmt.Sprintf("metadata-op-%d", seq))
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
		depGroup := dep.op.TaskGroupID
		if depGroup == "" {
			depGroup = fmt.Sprintf("journal-%d", dep.seqs[0])
		}
		depID := taskIDForGroup(s.NamespaceID(), depGroup)
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
	return state == OpStatePending || state == OpStateRunning || state == OpStateFailed || state == OpStateReconciling || state == OpStateVerifying || state == OpStateCancelRequested
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
