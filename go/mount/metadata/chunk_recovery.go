// Startup recovery discards staged data that never acquired a journal owner.
package metadata

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"

	bolt "go.etcd.io/bbolt"
)

// discardUnownedContentLocked runs before a startup chunk sweep. A staged ref
// without a write/rename journal op has no durable mutation intent after a
// crash, so keeping it would create a phantom inode and block reset forever.
func (s *Service) discardUnownedContentLocked() error {
	var remove []string
	err := s.store.update(func(tx boltTxT) error {
		journal := tx.Bucket([]byte(bucketJournal))
		owned := map[string]bool{}
		hasOp := map[uint64]bool{}
		if err := journal.ForEach(func(_, value []byte) error {
			var op Op
			if err := decodeJSON(value, &op); err != nil {
				return err
			}
			hasOp[op.InodeID] = true
			if op.ContentGeneration != 0 {
				owned[string(contentRefKey(op.InodeID, op.ContentGeneration))] = true
			}
			return nil
		}); err != nil {
			return err
		}
		refs := tx.Bucket([]byte(bucketContentRefs))
		cursor := refs.Cursor()
		type orphanRef struct {
			key []byte
			ref ContentRef
		}
		orphans := make([]orphanRef, 0)
		for key, value := cursor.First(); key != nil; key, value = cursor.Next() {
			if owned[string(key)] {
				continue
			}
			var ref ContentRef
			if err := decodeJSON(value, &ref); err != nil {
				return err
			}
			if ref.AwaitingJournal {
				orphans = append(orphans, orphanRef{key: append([]byte(nil), key...), ref: ref})
			}
		}
		deltas := map[string]int64{}
		for _, orphan := range orphans {
			for _, hash := range orphan.ref.Chunks {
				deltas[hash]--
			}
		}
		removed, err := applyChunkDeltas(tx, deltas, nil)
		if err != nil {
			return err
		}
		remove = removed
		for _, orphan := range orphans {
			if err := refs.Delete(orphan.key); err != nil {
				return err
			}
		}
		return discardUnownedPendingInodes(tx, hasOp, refs)
	})
	if err != nil {
		return err
	}
	s.removeChunkFiles(remove)
	return nil
}

// SweepChunkStore removes files absent from the bbolt chunk table, rebuilds
// the cache-cleaner manifest, and clears stale upload temporaries at startup.
func (s *Service) SweepChunkStore() error {
	s.chunkMu.Lock()
	defer s.chunkMu.Unlock()

	if err := s.discardUnownedContentLocked(); err != nil {
		return err
	}
	protection, err := s.chunkProtectionSnapshot()
	if err != nil {
		return err
	}
	files, err := s.chunkFiles()
	if err != nil {
		return err
	}
	for _, path := range files {
		if _, ok := protection[filepath.Base(path)]; !ok {
			_ = os.Remove(path)
		}
	}
	entries, err := os.ReadDir(s.tmpDir())
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, entry := range entries {
		_ = os.RemoveAll(filepath.Join(s.tmpDir(), entry.Name()))
	}
	s.chunkProtectionDirty = false
	s.stopChunkProtectionTimerLocked()
	return s.writeChunkProtectionState(protection, false)
}

func discardUnownedPendingInodes(tx boltTxT, hasOp map[uint64]bool, refs *bolt.Bucket) error {
	inodes := tx.Bucket([]byte(bucketInodes))
	var remove []Inode
	if err := inodes.ForEach(func(_, value []byte) error {
		var record Inode
		if err := decodeJSON(value, &record); err != nil {
			return err
		}
		if record.ID == rootInode || hasOp[record.ID] || record.Kind != KindFile || record.State != StatePending || record.RemoteParentID != 0 {
			return nil
		}
		prefix := encodeUint64(record.ID)
		if key, _ := refs.Cursor().Seek(prefix); key != nil && bytes.HasPrefix(key, prefix) {
			return nil
		}
		remove = append(remove, record)
		return nil
	}); err != nil {
		return err
	}
	for _, record := range remove {
		if err := deleteDirent(tx, record.DesiredParentID, MakeNameKey(record.DesiredName)); err != nil {
			return err
		}
		parent, err := getInode(tx, record.DesiredParentID)
		if err != nil {
			return fmt.Errorf("metadata: recover pending inode %d parent: %w", record.ID, err)
		}
		parent.LocalRevision++
		if err := putInode(tx, parent); err != nil {
			return err
		}
		if err := inodes.Delete(encodeUint64(record.ID)); err != nil {
			return err
		}
	}
	return nil
}
