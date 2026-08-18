// Task indexes persist logical group membership beside the append-only journal.
package metadata

import (
	"bytes"
	"fmt"
)

func assignTaskGroup(tx boltTx, op *Op) {
	if op == nil || op.TaskGroupID != "" {
		return
	}
	if prior, ok := lastPendingTaskPeer(tx, op); ok && prior.TaskGroupID != "" {
		op.TaskGroupID = prior.TaskGroupID
		return
	}
	op.TaskGroupID = fmt.Sprintf("journal-%d", op.Seq)
}

func lastPendingTaskPeer(tx boltTx, op *Op) (Op, bool) {
	journal := tx.Bucket([]byte(bucketJournal))
	cursor := journal.Cursor()
	for key, value := cursor.Last(); key != nil; key, value = cursor.Prev() {
		var prior Op
		if decodeJSON(value, &prior) != nil || prior.InodeID != op.InodeID || prior.State != OpStatePending {
			continue
		}
		switch {
		case op.Type == OpRename && (prior.Type == OpMkdir || prior.Type == OpRename):
			return prior, true
		case op.Type == OpWrite && prior.Type == OpWrite:
			return prior, true
		}
	}
	return Op{}, false
}

func indexTaskOp(tx boltTx, op Op) error {
	if op.TaskGroupID == "" {
		return nil
	}
	groups := tx.Bucket([]byte(bucketTaskGroups))
	members := tx.Bucket([]byte(bucketTaskMembers))
	if groups.Get([]byte(op.TaskGroupID)) == nil {
		if err := groups.Put([]byte(op.TaskGroupID), encodeUint64(op.Seq)); err != nil {
			return err
		}
	}
	return members.Put(taskMemberKey(op.TaskGroupID, op.Seq), []byte{})
}

func removeTaskOpIndex(tx boltTx, op Op) error {
	if op.TaskGroupID == "" {
		return nil
	}
	members := tx.Bucket([]byte(bucketTaskMembers))
	if err := members.Delete(taskMemberKey(op.TaskGroupID, op.Seq)); err != nil {
		return err
	}
	prefix := taskMemberPrefix(op.TaskGroupID)
	cursor := members.Cursor()
	key, _ := cursor.Seek(prefix)
	if key == nil || !bytes.HasPrefix(key, prefix) {
		return tx.Bucket([]byte(bucketTaskGroups)).Delete([]byte(op.TaskGroupID))
	}
	return tx.Bucket([]byte(bucketTaskGroups)).Put([]byte(op.TaskGroupID), append([]byte(nil), key[len(prefix):]...))
}

func taskMemberPrefix(group string) []byte { return append([]byte(group), 0) }

func taskMemberKey(group string, seq uint64) []byte {
	key := taskMemberPrefix(group)
	return append(key, encodeUint64(seq)...)
}
