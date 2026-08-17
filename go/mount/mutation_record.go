// Mutation records serialize queued remote moves so retries survive restarts.
package mount

// mutationRecordVersion gates forward compatibility of persisted mutation records.
const mutationRecordVersion = 1

// mutationKindRename is the only queued remote mutation kind today.
const mutationKindRename = "rename"

// mutationRecord is the durable form of one pending remote move. It replaces
// the former in-memory rename closure: every retry can be reconstructed from
// this data plus the observed provider state.
type mutationRecord struct {
	Version           int    `json:"version"`
	Scope             string `json:"scope"`
	ID                string `json:"id"`
	TaskID            string `json:"taskId"`
	Kind              string `json:"kind"`
	OldVirtualPath    string `json:"oldVirtualPath"`
	NewVirtualPath    string `json:"newVirtualPath"`
	OldLocalPath      string `json:"oldLocalPath"`
	NewLocalPath      string `json:"newLocalPath"`
	IsDirectory       bool   `json:"isDirectory"`
	UploadGeneration  uint64 `json:"uploadGeneration"`
	RetryCount        int    `json:"retryCount"`
	NextAttemptUnixNs int64  `json:"nextAttemptUnixNs"`
	LastError         string `json:"lastError,omitempty"`
	UpdatedAtUnixNs   int64  `json:"updatedAtUnixNs"`
}

// mutationEvent is one append-only JSONL line. A complete tombstone is written
// only after the remote postcondition has been verified; a crash between the
// provider success and the tombstone stays recoverable because the next run
// re-observes source/destination state.
type mutationEvent struct {
	Kind   string         `json:"kind"` // "upsert" | "complete"
	Record mutationRecord `json:"record"`
}

const (
	mutationEventUpsert   = "upsert"
	mutationEventComplete = "complete"
)
