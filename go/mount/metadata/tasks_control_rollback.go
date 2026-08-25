// Pending-task rollback restores the Desired tree and releases protected content.
package metadata

import (
	"strings"

	bolt "go.etcd.io/bbolt"
)

func (s *Service) rollbackPendingTask(tx boltTxT, ops []Op) ([]string, error) {
	if len(ops) == 0 {
		return nil, ErrNotFound
	}
	inode := ops[0].InodeID
	for _, op := range ops {
		if op.InodeID != inode {
			return nil, ErrTaskNotCancelable
		}
	}
	record, err := getInode(tx, inode)
	if err != nil {
		return nil, ErrTaskNotCancelable
	}
	if err := ensureCancellationIsolated(tx, inode, record.Kind, ops); err != nil {
		return nil, err
	}
	newLocal := record.RemoteParentID == 0 && record.RemoteName == ""
	if newLocal {
		if err := removeCurrentDirent(tx, record); err != nil {
			return nil, err
		}
		removed, err := releaseContentRefsForCancel(tx, inode, nil)
		if err != nil {
			return nil, err
		}
		if err := tx.Bucket([]byte(bucketListingState)).Delete(encodeUint64(inode)); err != nil {
			return nil, err
		}
		if err := tx.Bucket([]byte(bucketDirents)).DeleteBucket(encodeUint64(inode)); err != nil && err != bolt.ErrBucketNotFound {
			return nil, err
		}
		if err := tx.Bucket([]byte(bucketInodes)).Delete(encodeUint64(inode)); err != nil {
			return nil, err
		}
		return removed, nil
	}

	var removed []string
	canceledWrite := false
	for _, op := range ops {
		if op.Type != OpWrite {
			continue
		}
		canceledWrite = true
		generation := op.ContentGeneration
		items, err := releaseContentRefsForCancel(tx, inode, &generation)
		if err != nil {
			return nil, err
		}
		removed = append(removed, items...)
	}
	for _, op := range ops {
		if op.Type == OpRename {
			if err := restoreRemoteDirent(tx, &record); err != nil {
				return nil, err
			}
			break
		}
	}
	if record.State == StateTombstone {
		if err := restoreDeletedDirent(tx, record); err != nil {
			return nil, err
		}
	}
	if canceledWrite && strings.TrimSpace(record.RemoteMTime) != "" {
		record.MTime = record.RemoteMTime
	}
	record.State = StateSynced
	record.LocalRevision++
	if err := putInode(tx, record); err != nil {
		return nil, err
	}
	return removed, nil
}

func ensureCancellationIsolated(tx boltTxT, inode uint64, kind Kind, selected []Op) error {
	chosen := make(map[uint64]bool, len(selected))
	for _, op := range selected {
		chosen[op.Seq] = true
	}
	return tx.Bucket([]byte(bucketJournal)).ForEach(func(_, value []byte) error {
		var op Op
		if err := decodeJSON(value, &op); err != nil {
			return err
		}
		if chosen[op.Seq] || !unsettledOp(op.State) {
			return nil
		}
		if op.InodeID == inode || op.NewParent == inode || op.OldParent == inode {
			return ErrTaskNotCancelable
		}
		if kind == KindDirectory && inodeIsInSubtree(tx, op.InodeID, inode) {
			return ErrTaskNotCancelable
		}
		return nil
	})
}

func unsettledOp(state OpState) bool { return opStateUnsettled(state) }

func inodeIsInSubtree(tx boltTxT, inode, root uint64) bool {
	for depth := 0; inode != 0 && depth < 1024; depth++ {
		if inode == root {
			return true
		}
		record, err := getInode(tx, inode)
		if err != nil {
			return false
		}
		if inode == rootInode {
			return false
		}
		inode = record.DesiredParentID
	}
	return false
}

func removeCurrentDirent(tx boltTxT, record Inode) error {
	if err := deleteDirent(tx, record.DesiredParentID, MakeNameKey(record.DesiredName)); err != nil {
		return err
	}
	return bumpInodeRevision(tx, record.DesiredParentID)
}

func restoreRemoteDirent(tx boltTxT, record *Inode) error {
	if record.RemoteParentID == 0 || strings.TrimSpace(record.RemoteName) == "" {
		return ErrTaskNotCancelable
	}
	if err := removeCurrentDirent(tx, *record); err != nil {
		return err
	}
	if existing, err := getDirent(tx, record.RemoteParentID, MakeNameKey(record.RemoteName)); err == nil && existing.ChildID != record.ID {
		return ErrTaskNotCancelable
	} else if err != nil && err != ErrNotFound {
		return err
	}
	if err := putDirent(tx, record.RemoteParentID, Dirent{ChildID: record.ID, DisplayName: record.RemoteName, NameKey: MakeNameKey(record.RemoteName)}); err != nil {
		return err
	}
	if err := bumpInodeRevision(tx, record.RemoteParentID); err != nil {
		return err
	}
	record.DesiredParentID, record.DesiredName = record.RemoteParentID, record.RemoteName
	return nil
}

func restoreDeletedDirent(tx boltTxT, record Inode) error {
	if existing, err := getDirent(tx, record.DesiredParentID, MakeNameKey(record.DesiredName)); err == nil && existing.ChildID != record.ID {
		return ErrTaskNotCancelable
	} else if err != nil && err != ErrNotFound {
		return err
	}
	if err := putDirent(tx, record.DesiredParentID, Dirent{ChildID: record.ID, DisplayName: record.DesiredName, NameKey: MakeNameKey(record.DesiredName)}); err != nil {
		return err
	}
	return bumpInodeRevision(tx, record.DesiredParentID)
}

func bumpInodeRevision(tx boltTxT, inode uint64) error {
	record, err := getInode(tx, inode)
	if err != nil {
		return err
	}
	record.LocalRevision++
	return putInode(tx, record)
}
