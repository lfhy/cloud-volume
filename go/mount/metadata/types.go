// Types define the durable inode tree and public metadata service contracts.
package metadata

import (
	"context"
	"errors"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

// SchemaVersion gates forward compatibility. Development builds deliberately
// delete-and-rebuild instead of upgrading older layouts.
const SchemaVersion = 5

const (
	bucketSchema       = "schema"
	bucketInodes       = "inodes"
	bucketDirents      = "dirents"
	bucketJournal      = "journal"
	bucketListingState = "listing_state"
	bucketContentRefs  = "content_refs"
	bucketChunks       = "chunks"
	bucketReadyOps     = "ready_ops"
	bucketInodeOps     = "inode_ops"
	bucketTaskGroups   = "task_groups"
	bucketTaskMembers  = "task_members"

	rootInode uint64 = 1
)

// ErrNotFound, ErrStaleCursor, ErrCollision, and ErrCycle separate metadata
// failures so mount adapters and the bridge can map them to precise errors.
var (
	ErrNotFound    = errors.New("metadata: not found")
	ErrStaleCursor = errors.New("metadata: stale cursor")
	ErrCollision   = errors.New("metadata: name collision")
	ErrCycle       = errors.New("metadata: parent cycle")
	ErrReadOnly    = errors.New("metadata: bucket is read-only")
)

// Kind enumerates the entry types supported by the MVP tree.
type Kind uint8

const (
	KindFile Kind = iota
	KindDirectory
)

// State classifies one inode relative to the last confirmed remote version.
type State uint8

const (
	// StateSynced means Desired and Remote edges/metadata agree.
	StateSynced State = iota
	// StatePending means a journal operation still owns this inode.
	StatePending
	// StateConflict means remote changed under a pending local operation.
	StateConflict
	// StateTombstone means the local desired tree deleted this inode.
	StateTombstone
)

// OpType enumerates journal operations.
type OpType uint8

const (
	OpMkdir OpType = iota + 1
	OpWrite
	OpRename
	OpDelete
)

// OpState tracks the remote worker lifecycle for one journal operation.
type OpState uint8

const (
	OpStatePending OpState = iota
	OpStateRunning
	OpStateApplied
	OpStateFailed
	// Canceled is a terminal local rollback; Reconciling means provider outcome
	// is unknown after a cancellation request reached an in-flight operation.
	OpStateCanceled
	OpStateReconciling
	OpStateVerifying
	OpStateCancelRequested
)

// Inode is the durable identity record. Desired edges describe the local view;
// Remote edges describe the last provider-confirmed view.
type Inode struct {
	ID                uint64 `json:"id"`
	Kind              Kind   `json:"kind"`
	DesiredParentID   uint64 `json:"desiredParentId"`
	DesiredName       string `json:"desiredName"`
	RemoteParentID    uint64 `json:"remoteParentId"`
	RemoteName        string `json:"remoteName"`
	Size              int64  `json:"size"`
	MTime             string `json:"mtime"`
	RemoteMTime       string `json:"remoteMtime,omitempty"`
	LocalRevision     uint64 `json:"localRevision"`
	RemoteFingerprint string `json:"remoteFingerprint"`
	State             State  `json:"state"`
	ContentGeneration uint64 `json:"contentGeneration"`
	ETag              string `json:"etag"`
}

// Dirent is the value stored in a parent directory's own B+Tree.
type Dirent struct {
	ChildID     uint64 `json:"childId"`
	DisplayName string `json:"displayName"`
	NameKey     string `json:"nameKey"`
}

// Op is one durable local operation before remote confirmation.
type Op struct {
	Seq                       uint64 `json:"seq"`
	TaskGroupID               string `json:"taskGroupId,omitempty"`
	Type                      OpType `json:"type"`
	InodeID                   uint64 `json:"inodeId"`
	ContentGeneration         uint64 `json:"contentGeneration,omitempty"`
	OldParent                 uint64 `json:"oldParent"`
	NewParent                 uint64 `json:"newParent"`
	OldName                   string `json:"oldName"`
	NewName                   string `json:"newName"`
	State                     OpState
	Retry                     int
	LastError                 string
	NextAttemptUnixNano       int64  `json:"nextAttemptUnixNs"`
	ExpectedRemoteFingerprint string `json:"expectedRemoteFingerprint,omitempty"`
	HardDelete                bool   `json:"hardDelete,omitempty"`
	MoveApplied               bool   `json:"moveApplied,omitempty"`
	// MoveSource/Target and MoveParent/Name are frozen immediately before a
	// provider move. Desired edges may change again while confirmation retries.
	MoveSource                string `json:"moveSource,omitempty"`
	MoveTarget                string `json:"moveTarget,omitempty"`
	MoveParent                uint64 `json:"moveParent,omitempty"`
	MoveName                  string `json:"moveName,omitempty"`
	Origin                    string `json:"origin"`
	CreatedAtUnixNano         int64  `json:"createdAtUnixNs"`
	AppliedAtUnixNano         int64  `json:"appliedAtUnixNs,omitempty"`
	CancelRequested           bool   `json:"cancelRequested,omitempty"`
	CancelRequestedAtUnixNano int64  `json:"cancelRequestedAtUnixNs,omitempty"`
	CanceledAtUnixNano        int64  `json:"canceledAtUnixNs,omitempty"`
	ReconcileAtUnixNano       int64  `json:"reconcileAtUnixNs,omitempty"`
}

// ListingState records whether and when one directory was materialized.
type ListingState struct {
	Inode              uint64 `json:"inode"`
	Materialized       bool   `json:"materialized"`
	Revision           uint64 `json:"revision"`
	VerifiedAtUnixNano int64  `json:"verifiedAtUnixNs"`
}

// ContentRef maps one pending file generation to its ordered content-addressed
// chunks. Chunk files contain no inode or path information.
type ContentRef struct {
	Inode           uint64   `json:"inode"`
	Generation      uint64   `json:"generation"`
	Chunks          []string `json:"chunks"`
	Size            int64    `json:"size"`
	AwaitingJournal bool     `json:"awaitingJournal,omitempty"`
}

// PathProjection identifies the exact Desired-tree version a caller may
// project into a platform-local cache after durable journal admission.
type PathProjection struct {
	Path     string
	Inode    uint64
	Revision uint64
	Present  bool
}

// Object extends the shared provider object shape with local identity fields.
// Inode and Revision are strings on the wire to keep JavaScript below 53 bits.
type Object struct {
	Key               string
	IsDir             bool
	Size              int64
	LastModified      string
	ETag              string
	Inode             string
	Revision          string
	State             State
	ContentGeneration uint64
}

// Page is one deterministic slice of a materialized directory.
type Page struct {
	Items     []Object
	NextToken string
}

// Cursor is the opaque payload encoded into page tokens.
type Cursor struct {
	Version     int    `json:"v"`
	Inode       uint64 `json:"inode"`
	Revision    uint64 `json:"revision"`
	LastNameKey string `json:"lastNameKey"`
}

// Namespace identifies one account/bucket/rootPrefix metadata database.
type Namespace struct {
	ID        string
	Root      string
	CacheRoot string
	Config    storageconfig.RemoteStorageConfig
	Bucket    string
}

// Backend is the narrow provider surface required by the metadata service.
type Backend interface {
	ListObjectsPage(context.Context, string, string, string, int32) (storageops.ObjectPage, error)
	HeadObject(context.Context, string, string) (storageops.ObjectInfo, error)
	CreateDirectory(context.Context, string, string, string) error
	DeleteObject(context.Context, string, string, bool, string) error
	DeleteObjectHard(context.Context, string, string, bool, string) error
	RenameObject(context.Context, string, string, bool, string) error
	MoveObject(context.Context, string, string, string, bool, string) error
	UploadFile(context.Context, string, string, string, string) error
}
