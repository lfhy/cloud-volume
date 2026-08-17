// Path write helpers resolve mount/UI paths into durable inode operations.
package metadata

import (
	"context"
	"fmt"
	"io"
	"path"
	"strings"
)

// CreateDirectoryPath records a local mkdir under the resolved desired parent.
func (s *Service) CreateDirectoryPath(ctx context.Context, value string, opts WriteOptions) (uint64, error) {
	s.pathWriteMu.Lock()
	defer s.pathWriteMu.Unlock()
	return s.createDirectoryPathLocked(ctx, value, opts)
}

// CreateDirectoryPathWithProjection returns the exact Desired version created
// by this mutation so a platform cache cannot apply an older page projection.
func (s *Service) CreateDirectoryPathWithProjection(
	ctx context.Context, value string, opts WriteOptions,
) (uint64, PathProjection, error) {
	s.pathWriteMu.Lock()
	defer s.pathWriteMu.Unlock()
	inode, err := s.createDirectoryPathLocked(ctx, value, opts)
	if err != nil {
		return 0, PathProjection{}, err
	}
	projection, err := s.presentPathProjection(value)
	return inode, projection, err
}

func (s *Service) createDirectoryPathLocked(ctx context.Context, value string, opts WriteOptions) (uint64, error) {
	parent, name, err := resolveWriteParent(value)
	if err != nil {
		return 0, err
	}
	parentInode, err := s.resolvePath(ctx, parent)
	if err != nil {
		return 0, err
	}
	return s.CreateDirectory(parentInode, name, opts)
}

// WritePath stages content then appends the exact-generation write operation.
func (s *Service) WritePath(
	ctx context.Context,
	value string,
	source io.Reader,
	size int64,
	opts WriteOptions,
) (uint64, ContentRef, error) {
	// Keep staging and journal append ordered with the other path-level
	// mutations. Chunk I/O stays outside bbolt transactions, but a concurrent
	// path rename/delete cannot split this write in two.
	s.pathWriteMu.Lock()
	defer s.pathWriteMu.Unlock()
	return s.writePathLocked(ctx, value, source, size, opts)
}

// WritePathWithProjection retains the post-write inode revision while the
// shared path lock is held, making a later mount write distinguishable.
func (s *Service) WritePathWithProjection(
	ctx context.Context,
	value string,
	source io.Reader,
	size int64,
	opts WriteOptions,
) (uint64, ContentRef, PathProjection, error) {
	s.pathWriteMu.Lock()
	defer s.pathWriteMu.Unlock()
	inode, ref, err := s.writePathLocked(ctx, value, source, size, opts)
	if err != nil {
		return 0, ContentRef{}, PathProjection{}, err
	}
	projection, err := s.presentPathProjection(value)
	return inode, ref, projection, err
}

func (s *Service) writePathLocked(
	ctx context.Context, value string, source io.Reader, size int64, opts WriteOptions,
) (uint64, ContentRef, error) {
	parent, name, err := resolveWriteParent(value)
	if err != nil {
		return 0, ContentRef{}, err
	}
	parentInode, err := s.resolvePath(ctx, parent)
	if err != nil {
		return 0, ContentRef{}, err
	}
	reservation, err := s.stageWriteForName(parentInode, name, 0, source, size)
	if err != nil {
		return 0, ContentRef{}, err
	}
	if _, err := s.Write(parentInode, name, reservation.ref, opts); err != nil {
		cleanupErr := s.rollbackStagedWrite(reservation)
		return 0, ContentRef{}, combineStageErrors(err, cleanupErr)
	}
	return reservation.inode, reservation.ref, nil
}

// RenamePath moves one resolved inode without exposing parent inode IDs.
func (s *Service) RenamePath(ctx context.Context, source, target string, opts WriteOptions) error {
	s.pathWriteMu.Lock()
	defer s.pathWriteMu.Unlock()
	return s.renamePathLocked(ctx, source, target, opts)
}

// RenamePathWithProjection returns the target version while source removal is
// still ordered with the rename, for conditional mount-cache projection.
func (s *Service) RenamePathWithProjection(
	ctx context.Context, source, target string, opts WriteOptions,
) (PathProjection, error) {
	s.pathWriteMu.Lock()
	defer s.pathWriteMu.Unlock()
	if err := s.renamePathLocked(ctx, source, target, opts); err != nil {
		return PathProjection{}, err
	}
	return s.presentPathProjection(target)
}

func (s *Service) renamePathLocked(ctx context.Context, source, target string, opts WriteOptions) error {
	inode, err := s.resolvePath(ctx, source)
	if err != nil {
		return err
	}
	parent, name, err := resolveWriteParent(target)
	if err != nil {
		return err
	}
	parentInode, err := s.resolvePath(ctx, parent)
	if err != nil {
		return err
	}
	return s.Rename(inode, parentInode, name, opts)
}

// DeletePath tombstones the resolved desired inode and journals its remote delete.
func (s *Service) DeletePath(ctx context.Context, value string, opts WriteOptions) error {
	s.pathWriteMu.Lock()
	defer s.pathWriteMu.Unlock()
	return s.deletePathLocked(ctx, value, opts)
}

// DeletePathWithProjection describes the now-absent path for a conditional
// mount tombstone projection after the delete journal entry commits.
func (s *Service) DeletePathWithProjection(
	ctx context.Context, value string, opts WriteOptions,
) (PathProjection, error) {
	s.pathWriteMu.Lock()
	defer s.pathWriteMu.Unlock()
	if err := s.deletePathLocked(ctx, value, opts); err != nil {
		return PathProjection{}, err
	}
	return absentPathProjection(value), nil
}

func (s *Service) deletePathLocked(ctx context.Context, value string, opts WriteOptions) error {
	inode, err := s.resolvePath(ctx, value)
	if err != nil {
		return err
	}
	return s.Delete(inode, opts)
}

func resolveWriteParent(value string) (string, string, error) {
	clean := strings.Trim(strings.TrimSpace(value), "/")
	if clean == "" {
		return "", "", fmt.Errorf("metadata: root cannot be written")
	}
	parent, name := path.Dir(clean), path.Base(clean)
	if parent == "." {
		parent = ""
	}
	if name == "" || name == "." || name == ".." {
		return "", "", fmt.Errorf("metadata: path name is required")
	}
	return parent, name, nil
}
