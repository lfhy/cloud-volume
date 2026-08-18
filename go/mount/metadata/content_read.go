// Pending content readers expose immutable staged chunks to mount byte paths.
package metadata

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"time"
)

const pendingChunkTouchInterval = 5 * time.Second

// ReadPendingRange returns bytes for a pending Desired file when its content
// reference is still present. handled=false means the inode has no staged
// content (for example, a rename of an already confirmed remote file), so the
// caller may use its normal remote-source path.
func (s *Service) ReadPendingRange(
	ctx context.Context,
	inode uint64,
	offset, length int64,
) (data []byte, handled bool, err error) {
	if inode == 0 || offset < 0 || length < 0 {
		return nil, false, fmt.Errorf("metadata: invalid pending content range")
	}
	if length == 0 {
		return []byte{}, false, nil
	}
	if int64(int(length)) != length {
		return nil, false, fmt.Errorf("metadata: pending content range is too large")
	}

	s.chunkMu.Lock()
	defer s.chunkMu.Unlock()
	ref, ok, err := s.pendingContentRefLocked(inode)
	if err != nil || !ok {
		return nil, ok, err
	}
	if offset >= ref.Size {
		return []byte{}, true, nil
	}
	if remaining := ref.Size - offset; length > remaining {
		length = remaining
	}
	if int64(int(length)) != length {
		return nil, true, fmt.Errorf("metadata: pending content range is too large")
	}
	buffer := bytes.NewBuffer(make([]byte, 0, int(length)))
	if _, err := s.copyPendingRangeLocked(ctx, ref, offset, length, buffer); err != nil {
		return nil, true, err
	}
	s.touchChunksForReadLocked(ref.Chunks)
	return buffer.Bytes(), true, nil
}

// CopyPendingContent streams a pending file into dst without consulting the
// provider. handled=false has the same meaning as ReadPendingRange.
func (s *Service) CopyPendingContent(
	ctx context.Context,
	inode uint64,
	dst io.Writer,
) (handled bool, err error) {
	if inode == 0 || dst == nil {
		return false, fmt.Errorf("metadata: pending content destination is invalid")
	}
	s.chunkMu.Lock()
	defer s.chunkMu.Unlock()
	ref, ok, err := s.pendingContentRefLocked(inode)
	if err != nil || !ok {
		return ok, err
	}
	if _, err := s.copyPendingRangeLocked(ctx, ref, 0, ref.Size, dst); err != nil {
		return true, err
	}
	s.touchChunksForReadLocked(ref.Chunks)
	return true, nil
}

func (s *Service) pendingContentRefLocked(inode uint64) (ContentRef, bool, error) {
	var ref ContentRef
	err := s.store.view(func(tx boltTxT) error {
		record, err := getInode(tx, inode)
		if err != nil {
			return err
		}
		if record.State != StatePending && record.State != StateConflict {
			return nil
		}
		if record.ContentGeneration == 0 {
			return nil
		}
		raw := tx.Bucket([]byte(bucketContentRefs)).Get(contentRefKey(inode, record.ContentGeneration))
		if raw == nil {
			return nil
		}
		return decodeJSON(raw, &ref)
	})
	if errors.Is(err, ErrNotFound) {
		return ContentRef{}, false, err
	}
	if err != nil {
		return ContentRef{}, false, err
	}
	return ref, ref.Generation != 0 && ref.Inode == inode, nil
}

func (s *Service) copyPendingRangeLocked(
	ctx context.Context,
	ref ContentRef,
	offset, length int64,
	dst io.Writer,
) (int64, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if offset < 0 || length < 0 || offset > ref.Size {
		return 0, fmt.Errorf("metadata: pending content range is invalid")
	}
	if length == 0 {
		return 0, nil
	}
	end := offset + length
	if end < offset || end > ref.Size {
		end = ref.Size
	}
	var logical, copied int64
	for _, hash := range ref.Chunks {
		if err := ctx.Err(); err != nil {
			return copied, err
		}
		if !validChunkHash(hash) {
			return copied, fmt.Errorf("metadata: invalid pending chunk hash %q", hash)
		}
		file, err := os.Open(s.chunkPath(hash))
		if err != nil {
			return copied, fmt.Errorf("metadata: open pending chunk %s: %w", hash, err)
		}
		info, statErr := file.Stat()
		if statErr != nil {
			_ = file.Close()
			return copied, statErr
		}
		chunkEnd := logical + info.Size()
		from := maxInt64(offset, logical)
		to := minInt64(end, chunkEnd)
		if to > from {
			reader := io.NewSectionReader(file, from-logical, to-from)
			written, copyErr := io.Copy(dst, reader)
			copied += written
			if copyErr != nil {
				_ = file.Close()
				return copied, copyErr
			}
			if written != to-from {
				_ = file.Close()
				return copied, io.ErrUnexpectedEOF
			}
		}
		_ = file.Close()
		logical = chunkEnd
		if logical >= end {
			break
		}
	}
	if copied != end-offset {
		return copied, io.ErrUnexpectedEOF
	}
	return copied, nil
}

func (s *Service) touchChunksForReadLocked(hashes []string) {
	if len(hashes) == 0 {
		return
	}
	if s.chunkTouch == nil {
		s.chunkTouch = map[string]int64{}
	}
	now := time.Now().UnixNano()
	due := make([]string, 0, len(hashes))
	seen := make(map[string]struct{}, len(hashes))
	for _, hash := range hashes {
		if _, ok := seen[hash]; ok {
			continue
		}
		seen[hash] = struct{}{}
		if last := s.chunkTouch[hash]; last != 0 && now-last < pendingChunkTouchInterval.Nanoseconds() {
			continue
		}
		due = append(due, hash)
	}
	if len(due) == 0 {
		return
	}
	if err := s.touchChunksLocked(due); err != nil {
		return
	}
	for _, hash := range due {
		s.chunkTouch[hash] = now
	}
}

func maxInt64(left, right int64) int64 {
	if left > right {
		return left
	}
	return right
}

func minInt64(left, right int64) int64 {
	if left < right {
		return left
	}
	return right
}
