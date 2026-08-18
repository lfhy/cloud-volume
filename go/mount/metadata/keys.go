// Helpers own deterministic key/path/fingerprint/cursor encoding for the inode store.
package metadata

import (
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"path"
	"strings"

	"golang.org/x/text/unicode/norm"

	storageops "remote-storage/go/storage"
)

func encodeUint64(value uint64) []byte {
	out := make([]byte, 8)
	binary.BigEndian.PutUint64(out, value)
	return out
}

func decodeUint64(value []byte) uint64 {
	if len(value) != 8 {
		return 0
	}
	return binary.BigEndian.Uint64(value)
}

func encodeJSON(value any) ([]byte, error) {
	return json.Marshal(value)
}

func decodeJSON(data []byte, out any) error {
	if len(data) == 0 {
		return fmt.Errorf("metadata: empty record")
	}
	return json.Unmarshal(data, out)
}

// putInode stores one inode record through the generic transaction helper.
func putInode(tx boltTx, record Inode) error {
	return putInodeBoltTx(tx, record)
}

func getInode(tx boltTx, inode uint64) (Inode, error) {
	raw := tx.Bucket([]byte(bucketInodes)).Get(encodeUint64(inode))
	if raw == nil {
		return Inode{}, ErrNotFound
	}
	var record Inode
	if err := decodeJSON(raw, &record); err != nil {
		return Inode{}, err
	}
	return record, nil
}

func getDirent(tx boltTx, parent uint64, nameKey string) (Dirent, error) {
	children := tx.Bucket([]byte(bucketDirents)).Bucket(encodeUint64(parent))
	if children == nil {
		return Dirent{}, ErrNotFound
	}
	raw := children.Get([]byte(nameKey))
	if raw == nil {
		return Dirent{}, ErrNotFound
	}
	var dirent Dirent
	if err := decodeJSON(raw, &dirent); err != nil {
		return Dirent{}, err
	}
	return dirent, nil
}

func putDirent(tx boltTx, parent uint64, dirent Dirent) error {
	children, err := tx.Bucket([]byte(bucketDirents)).CreateBucketIfNotExists(encodeUint64(parent))
	if err != nil {
		return err
	}
	data, err := encodeJSON(dirent)
	if err != nil {
		return err
	}
	return children.Put([]byte(dirent.NameKey), data)
}

func deleteDirent(tx boltTx, parent uint64, nameKey string) error {
	children := tx.Bucket([]byte(bucketDirents)).Bucket(encodeUint64(parent))
	if children == nil {
		return nil
	}
	return children.Delete([]byte(nameKey))
}

func allocateInode(tx boltTx) (uint64, error) {
	schema := tx.Bucket([]byte(bucketSchema))
	raw := schema.Get([]byte("nextInode"))
	next := decodeUint64(raw) + 1
	if err := schema.Put([]byte("nextInode"), encodeUint64(next)); err != nil {
		return 0, err
	}
	return next, nil
}

func putListingState(tx boltTx, state ListingState) error {
	data, err := encodeJSON(state)
	if err != nil {
		return err
	}
	return tx.Bucket([]byte(bucketListingState)).Put(encodeUint64(state.Inode), data)
}

func getListingState(tx boltTx, inode uint64) (ListingState, error) {
	raw := tx.Bucket([]byte(bucketListingState)).Get(encodeUint64(inode))
	if raw == nil {
		return ListingState{}, ErrNotFound
	}
	var state ListingState
	if err := decodeJSON(raw, &state); err != nil {
		return ListingState{}, err
	}
	return state, nil
}

// putOp stores one journal operation and keeps its ready_ops scheduling index
// consistent with the previous state. The caller passes the prior op record so
// state/attempt transitions remove the stale scheduling key.
func putOp(tx boltTx, op Op, previous Op) error {
	data, err := encodeJSON(op)
	if err != nil {
		return err
	}
	key := encodeUint64(op.Seq)
	if err := tx.Bucket([]byte(bucketJournal)).Put(key, data); err != nil {
		return err
	}
	if err := tx.Bucket([]byte(bucketInodeOps)).Put(inodeOpKey(op.InodeID, op.Seq), []byte{}); err != nil {
		return err
	}
	if err := indexTaskOp(tx, op); err != nil {
		return err
	}
	if previous.Seq == op.Seq {
		if err := tx.Bucket([]byte(bucketReadyOps)).Delete(readyKey(previous)); err != nil {
			return err
		}
	}
	if op.State == OpStatePending || op.State == OpStateFailed {
		return tx.Bucket([]byte(bucketReadyOps)).Put(readyKey(op), []byte{})
	}
	return nil
}

// replaceOp loads the stored operation before applying fn and writes both the
// journal record and scheduling index in one transaction.
func replaceOp(tx boltTx, seq uint64, fn func(*Op)) error {
	current, err := getOp(tx, seq)
	if err != nil {
		return err
	}
	previous := current
	fn(&current)
	return putOp(tx, current, previous)
}

func inodeOpKey(inode, seq uint64) []byte {
	out := make([]byte, 16)
	binary.BigEndian.PutUint64(out, inode)
	binary.BigEndian.PutUint64(out[8:], seq)
	return out
}

func readyKey(op Op) []byte {
	state := byte(op.State)
	next := encodeUint64(uint64(op.NextAttemptUnixNano))
	seq := encodeUint64(op.Seq)
	out := make([]byte, 0, 1+len(next)+len(seq))
	out = append(out, state)
	out = append(out, next...)
	return append(out, seq...)
}

// MakeNameKey normalizes a display name for deterministic, case-sensitive
// ordering and conflict detection.
func MakeNameKey(name string) string {
	return string(norm.NFC.String(name))
}

// SplitPath returns cleaned path segments; empty input means the root.
func SplitPath(value string) []string {
	trimmed := strings.Trim(strings.TrimSpace(value), "/")
	if trimmed == "" || trimmed == "." {
		return nil
	}
	return strings.Split(trimmed, "/")
}

// JoinPath joins segments with slash separators.
func JoinPath(segments []string) string {
	return strings.Join(segments, "/")
}

// RemoteKey builds a provider key from a virtual path.
func RemoteKey(pathValue string) string {
	if strings.TrimSpace(pathValue) == "" {
		return ""
	}
	return path.Clean("/" + strings.TrimSpace(pathValue))[1:]
}

// Fingerprint chooses the strongest provider version signal available.
func Fingerprint(item storageops.ObjectInfo) string {
	if strings.TrimSpace(item.ETag) != "" {
		return "etag:" + strings.TrimSpace(item.ETag)
	}
	if strings.TrimSpace(item.LastModified) != "" {
		return fmt.Sprintf("mtime:%s:size:%d", strings.TrimSpace(item.LastModified), item.Size)
	}
	return fmt.Sprintf("size:%d", item.Size)
}

// EncodeCursor serializes a pagination cursor as opaque base64url JSON.
func EncodeCursor(cursor Cursor) string {
	if cursor.Version == 0 {
		cursor.Version = 1
	}
	data, _ := json.Marshal(cursor)
	return base64.RawURLEncoding.EncodeToString(data)
}

// DecodeCursor parses a pagination token.
func DecodeCursor(token string) (Cursor, error) {
	data, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(token))
	if err != nil {
		return Cursor{}, fmt.Errorf("metadata: invalid cursor: %w", err)
	}
	var cursor Cursor
	if err := json.Unmarshal(data, &cursor); err != nil {
		return Cursor{}, fmt.Errorf("metadata: invalid cursor payload: %w", err)
	}
	if cursor.Version != 1 {
		return Cursor{}, ErrStaleCursor
	}
	return cursor, nil
}

// splitListedChild accepts provider keys that are either directory-relative or
// view-relative, while rejecting deep descendants from a misbehaving listing.
// Flattening a nested key into its basename would create the child under the
// wrong inode and make a later mount read disagree with the page view.
func splitListedChild(parentPath, key string) (string, bool, error) {
	rawKey := strings.TrimSpace(key)
	isDir := strings.HasSuffix(rawKey, "/")
	trimmedKey := strings.Trim(rawKey, "/")
	if trimmedKey == "" {
		return "", false, fmt.Errorf("metadata: empty listed key")
	}
	parent := strings.Trim(strings.TrimSpace(parentPath), "/")
	relative := trimmedKey
	if parent != "" {
		switch {
		case trimmedKey == parent:
			return "", false, fmt.Errorf("metadata: listing returned its parent")
		case strings.HasPrefix(trimmedKey, parent+"/"):
			relative = strings.TrimPrefix(trimmedKey, parent+"/")
		}
	}
	if relative == "" || strings.Contains(relative, "/") {
		return "", false, fmt.Errorf("metadata: listing returned non-child key %q", key)
	}
	return relative, isDir, nil
}

func objectFromInode(record Inode, path string) Object {
	key := path
	if record.Kind == KindDirectory {
		key = path + "/"
	}
	return Object{
		Key: key, IsDir: record.Kind == KindDirectory, Size: record.Size,
		LastModified: record.MTime, ETag: record.ETag,
		Inode: fmt.Sprintf("%d", record.ID), Revision: fmt.Sprintf("%d", record.LocalRevision),
		State: record.State, ContentGeneration: record.ContentGeneration,
	}
}

func reverse(values []string) {
	for left, right := 0, len(values)-1; left < right; left, right = left+1, right-1 {
		values[left], values[right] = values[right], values[left]
	}
}
