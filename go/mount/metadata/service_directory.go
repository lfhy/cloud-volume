// Directory helpers expose complete path-level metadata reads to mount adapters.
package metadata

import (
	"context"
	"fmt"

	bolt "go.etcd.io/bbolt"
)

// ListDirectory returns the full desired-tree view for one directory path.
// Mount adapters use this instead of carrying the root inode or page cursors.
func (s *Service) ListDirectory(ctx context.Context, path string) ([]Object, error) {
	inode, err := s.resolvePath(ctx, path)
	if err != nil {
		return nil, err
	}
	if err := s.ensureMaterialized(ctx, inode, 0); err != nil {
		return nil, err
	}
	return s.listDirectoryInode(ctx, inode)
}

// RefreshDirectory re-materializes one directory before returning its complete
// desired-tree view. It is used by mount's bounded remote-poll fallback.
func (s *Service) RefreshDirectory(ctx context.Context, path string) ([]Object, error) {
	inode, err := s.resolvePath(ctx, path)
	if err != nil {
		return nil, err
	}
	// Polling is an explicit remote refresh only for directories that already
	// have a confirmed provider edge. A local-only mkdir has no remote path yet.
	localOnly, err := s.isLocalOnlyDirectory(inode)
	if err != nil {
		return nil, err
	}
	if !localOnly {
		if err := s.MaterializeDirectory(ctx, inode); err != nil {
			return nil, err
		}
	}
	return s.listDirectoryInode(ctx, inode)
}

func (s *Service) listDirectoryInode(ctx context.Context, inode uint64) ([]Object, error) {
	if err := contextError(ctx); err != nil {
		return nil, err
	}
	items := make([]Object, 0)
	err := s.store.view(func(tx *bolt.Tx) error {
		parent, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		if parent.Kind != KindDirectory {
			return fmt.Errorf("metadata: inode %d is not a directory", inode)
		}
		children := tx.Bucket([]byte(bucketDirents)).Bucket(encodeUint64(inode))
		if children == nil {
			return nil
		}
		return children.ForEach(func(_, value []byte) error {
			if err := contextError(ctx); err != nil {
				return err
			}
			var dirent Dirent
			if err := decodeJSON(value, &dirent); err != nil {
				return nil
			}
			record, err := getInode(tx, dirent.ChildID)
			if err != nil || record.State == StateTombstone {
				return nil
			}
			pathValue, err := s.pathLocked(tx, record.ID)
			if err != nil {
				return nil
			}
			items = append(items, objectFromInode(record, pathValue))
			return nil
		})
	})
	if items == nil {
		items = []Object{}
	}
	return items, err
}

func contextError(ctx context.Context) error {
	if ctx == nil {
		return nil
	}
	return ctx.Err()
}
