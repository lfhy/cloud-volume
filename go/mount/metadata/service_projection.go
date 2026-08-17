// Projection helpers compare durable Desired versions without remote I/O.
package metadata

import (
	"errors"
	"strings"
)

func (s *Service) presentPathProjection(value string) (PathProjection, error) {
	clean := projectionPath(value)
	var record Inode
	err := s.store.view(func(tx boltTxT) error {
		var err error
		record, err = desiredPathRecord(tx, clean)
		return err
	})
	if err != nil {
		return PathProjection{}, err
	}
	return PathProjection{Path: clean, Inode: record.ID, Revision: record.LocalRevision, Present: true}, nil
}

func absentPathProjection(value string) PathProjection {
	return PathProjection{Path: projectionPath(value)}
}

// ProjectionCurrent reports whether a prior mutation still owns the Desired
// outcome at its path. It never materializes a provider directory.
func (s *Service) ProjectionCurrent(projection PathProjection) (bool, error) {
	clean := projectionPath(projection.Path)
	var current bool
	err := s.store.view(func(tx boltTxT) error {
		record, err := desiredPathRecord(tx, clean)
		if errors.Is(err, ErrNotFound) {
			current = !projection.Present
			return nil
		}
		if err != nil {
			return err
		}
		if !projection.Present {
			current = false
			return nil
		}
		current = record.ID == projection.Inode && record.LocalRevision == projection.Revision
		return nil
	})
	return current, err
}

func desiredPathRecord(tx boltTx, value string) (Inode, error) {
	current := rootInode
	for _, segment := range SplitPath(value) {
		dirent, err := getDirent(tx, current, MakeNameKey(segment))
		if err != nil {
			return Inode{}, err
		}
		record, err := getInode(tx, dirent.ChildID)
		if err != nil {
			return Inode{}, err
		}
		if record.State == StateTombstone {
			return Inode{}, ErrNotFound
		}
		current = record.ID
	}
	return getInode(tx, current)
}

func projectionPath(value string) string {
	return strings.Trim(strings.TrimSpace(value), "/")
}
