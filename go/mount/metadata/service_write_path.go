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

	parent, name, err := resolveWriteParent(value)
	if err != nil {
		return 0, ContentRef{}, err
	}
	parentInode, err := s.resolvePath(ctx, parent)
	if err != nil {
		return 0, ContentRef{}, err
	}
	inode, ref, err := s.StageWriteForName(parentInode, name, 0, source, size)
	if err != nil {
		return 0, ContentRef{}, err
	}
	if _, err := s.Write(parentInode, name, ref, opts); err != nil {
		generation := ref.Generation
		_ = s.releaseContent(inode, &generation, false)
		return 0, ContentRef{}, err
	}
	return inode, ref, nil
}

// RenamePath moves one resolved inode without exposing parent inode IDs.
func (s *Service) RenamePath(ctx context.Context, source, target string, opts WriteOptions) error {
	s.pathWriteMu.Lock()
	defer s.pathWriteMu.Unlock()

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
