package metadata

// TaskState and Task are the stable JSON projection consumed by desktop/Web.
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

type TaskEvent struct {
	Sequence   uint64 `json:"sequence"`
	Kind       string `json:"kind"`
	State      string `json:"state"`
	SourcePath string `json:"sourcePath,omitempty"`
	TargetPath string `json:"targetPath,omitempty"`
	Detail     string `json:"detail,omitempty"`
	Folded     bool   `json:"folded"`
	CreatedAt  string `json:"createdAt,omitempty"`
}

type Task struct {
	ID                string      `json:"id"`
	Namespace         string      `json:"namespace"`
	NamespaceID       string      `json:"namespaceId"`
	ProfileID         string      `json:"profileId,omitempty"`
	Bucket            string      `json:"bucket,omitempty"`
	Seq               uint64      `json:"seq"`
	TaskGroupID       string      `json:"taskGroupId,omitempty"`
	LastSeq           uint64      `json:"lastSeq"`
	SourceSeqs        []uint64    `json:"sourceSeqs,omitempty"`
	SourceKinds       []string    `json:"sourceKinds,omitempty"`
	Events            []TaskEvent `json:"events,omitempty"`
	Type              OpType      `json:"type"`
	State             TaskState   `json:"state"`
	Kind              string      `json:"kind"`
	Status            string      `json:"status"`
	Source            string      `json:"source"`
	InodeID           uint64      `json:"inodeId"`
	ParentID          uint64      `json:"parentId,omitempty"`
	Name              string      `json:"name,omitempty"`
	OldParent         uint64      `json:"oldParent,omitempty"`
	OldName           string      `json:"oldName,omitempty"`
	NewParent         uint64      `json:"newParent,omitempty"`
	NewName           string      `json:"newName,omitempty"`
	Path              string      `json:"path,omitempty"`
	SourcePath        string      `json:"sourcePath,omitempty"`
	TargetPath        string      `json:"targetPath,omitempty"`
	DisplayPath       string      `json:"displayPath,omitempty"`
	Phase             string      `json:"phase,omitempty"`
	PhaseDetail       string      `json:"phaseDetail,omitempty"`
	BlockedReason     string      `json:"blockedReason,omitempty"`
	Dependencies      []string    `json:"dependencies,omitempty"`
	DependencySeqs    []uint64    `json:"dependencySeqs,omitempty"`
	ContentGeneration uint64      `json:"contentGeneration,omitempty"`
	PhysicalSeq       uint64      `json:"physicalSeq,omitempty"`
	PhysicalSnapshot  string      `json:"physicalSnapshot,omitempty"`
	PhysicalTaskIDs   []string    `json:"physicalTaskIds,omitempty"`
	Retry             int         `json:"retry,omitempty"`
	LastError         string      `json:"lastError,omitempty"`
	NextAttemptUnixNs int64       `json:"nextAttemptUnixNs,omitempty"`
	Origin            string      `json:"origin,omitempty"`
	CreatedAtUnixNs   int64       `json:"createdAtUnixNs,omitempty"`
	AppliedAtUnixNs   int64       `json:"appliedAtUnixNs,omitempty"`
	CanceledAtUnixNs  int64       `json:"canceledAtUnixNs,omitempty"`
	CreatedAt         string      `json:"createdAt,omitempty"`
	UpdatedAt         string      `json:"updatedAt,omitempty"`
	FinishedAt        string      `json:"finishedAt,omitempty"`
	NextRetryAt       string      `json:"nextRetryAt,omitempty"`
	Cancelable        bool        `json:"cancelable"`
	Retryable         bool        `json:"retryable"`
	Triggerable       bool        `json:"triggerable"`
}

type TaskSummary struct {
	Total   int `json:"total"`
	Pending int `json:"pending"`
	Running int `json:"running"`
	Blocked int `json:"blocked"`
	Failed  int `json:"failed"`
}

type TaskGroup struct {
	Namespace string      `json:"namespace"`
	Tasks     []Task      `json:"tasks"`
	Summary   TaskSummary `json:"summary"`
}
