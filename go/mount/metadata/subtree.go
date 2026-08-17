// Subtree cleanup removes descendants of confirmed directory deletes.
package metadata

import bolt "go.etcd.io/bbolt"

// collectSubtreeInodes returns every non-root inode whose Desired edge chains
// to the given root, excluding the root itself. Corrupt parent edges stop the
// walk and surface the error instead of silently leaking records.
func (s *Service) collectSubtreeInodes(root uint64) ([]uint64, error) {
	var descendants []uint64
	err := s.store.view(func(tx boltTxT) error {
		return tx.Bucket([]byte(bucketInodes)).ForEach(func(key, _ []byte) error {
			inode := decodeUint64(key)
			if inode == rootInode || inode == root {
				return nil
			}
			// Mark visited only after the current node is examined; seeding the
			// map with the candidate itself made the walk bail immediately and
			// silently collect no descendants at all.
			visited := map[uint64]bool{}
			current := inode
			for depth := 0; depth < 1024; depth++ {
				if current == rootInode {
					return nil
				}
				if current == root {
					descendants = append(descendants, inode)
					return nil
				}
				if visited[current] {
					return nil
				}
				visited[current] = true
				record, err := getInode(tx, current)
				if err != nil {
					return err
				}
				current = record.DesiredParentID
			}
			return nil
		})
	})
	return descendants, err
}

// purgeInodeRecords removes inode records, dirents, and pending content for a
// list of inodes whose remote deletes are no longer tracked by journal ops.
func (s *Service) purgeInodeRecords(inodes []uint64) error {
	for _, inode := range inodes {
		if err := s.deleteInodeRecord(inode); err != nil {
			return err
		}
		// Directory children tables must be dropped too or the dirents sub
		// buckets leak forever even though InodeCount stays accurate.
		if err := s.store.update(func(tx boltTxT) error {
			return tx.Bucket([]byte(bucketDirents)).DeleteBucket(encodeUint64(inode))
		}); err != nil && err != bolt.ErrBucketNotFound {
			return err
		}
	}
	return nil
}
