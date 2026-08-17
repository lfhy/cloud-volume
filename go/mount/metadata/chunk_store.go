// Content-addressed chunks hold pending file data separately from inode metadata.
package metadata

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// chunkSize is the fixed block size for pending data. The final block may be
// shorter; fixed-size chunking keeps deduplication cheap and predictable.
const chunkSize = 4 * 1024 * 1024

type chunkRecord struct {
	Nlink            int64
	Size             int64
	LastAccessUnixNs int64
}

func (s *Service) chunkStoreRoot() string {
	root := strings.TrimSpace(s.store.chunkRoot)
	if root == "" {
		// Defensive fallback for callers with a store opened before schema init.
		root = s.store.namespace.Root
	}
	return filepath.Join(root, "metadata-chunks", s.store.namespace.ID)
}

func (s *Service) chunkPath(hash string) string {
	return filepath.Join(s.chunkStoreRoot(), "chunks", hash[:2], hash)
}

func (s *Service) tmpDir() string {
	return filepath.Join(s.chunkStoreRoot(), "tmp")
}

// stagePendingContent persists all chunks before atomically recording their
// references in bbolt. A crash before bbolt commits leaves only sweepable
// orphan files; it cannot leave a ContentRef pointing at absent data.
func (s *Service) stagePendingContent(
	inode, generation uint64, source io.Reader, declaredSize int64,
) (ContentRef, error) {
	s.chunkMu.Lock()
	defer s.chunkMu.Unlock()

	hashes, sizes, written, err := s.stageChunksLocked(source)
	if err != nil {
		_ = s.syncChunkProtectionLocked()
		return ContentRef{}, err
	}
	if declaredSize >= 0 && declaredSize != written {
		_ = s.syncChunkProtectionLocked()
		return ContentRef{}, fmt.Errorf(
			"metadata: staged size mismatch: declared=%d actual=%d", declaredSize, written,
		)
	}
	ref := ContentRef{Inode: inode, Generation: generation, Chunks: hashes, Size: written}
	if err := s.replaceContentRefLocked(ref, sizes); err != nil {
		_ = s.syncChunkProtectionLocked()
		return ContentRef{}, err
	}
	return ref, nil
}

func (s *Service) stageChunksLocked(source io.Reader) ([]string, []int64, int64, error) {
	if err := os.MkdirAll(filepath.Join(s.chunkStoreRoot(), "chunks"), 0o755); err != nil {
		return nil, nil, 0, err
	}
	if err := os.MkdirAll(s.tmpDir(), 0o755); err != nil {
		return nil, nil, 0, err
	}
	// Keep every already-written prospective block in this staging pass
	// protected until the ContentRef transaction makes those links durable.
	protection, err := s.chunkProtectionSnapshot()
	if err != nil {
		return nil, nil, 0, err
	}
	buffer := make([]byte, chunkSize)
	hashes := make([]string, 0)
	sizes := make([]int64, 0)
	var total int64
	for {
		count, readErr := io.ReadFull(source, buffer)
		if count > 0 {
			block := buffer[:count]
			sum := sha256.Sum256(block)
			hash := hex.EncodeToString(sum[:])
			if err := s.protectChunkBeforeCommitLocked(protection, hash, int64(count)); err != nil {
				return nil, nil, 0, err
			}
			if err := s.writeChunkLocked(hash, block); err != nil {
				return nil, nil, 0, err
			}
			hashes = append(hashes, hash)
			sizes = append(sizes, int64(count))
			total += int64(count)
		}
		switch readErr {
		case nil:
			continue
		case io.EOF, io.ErrUnexpectedEOF:
			return hashes, sizes, total, nil
		default:
			return nil, nil, 0, readErr
		}
	}
}

func (s *Service) writeChunkLocked(hash string, block []byte) error {
	if !validChunkHash(hash) {
		return fmt.Errorf("metadata: invalid chunk hash %q", hash)
	}
	finalPath := s.chunkPath(hash)
	if info, err := os.Stat(finalPath); err == nil {
		if info.Size() == int64(len(block)) {
			matches, err := chunkFileMatches(finalPath, hash)
			if err != nil {
				return err
			}
			if matches {
				return nil
			}
		}
		if err := os.Remove(finalPath); err != nil {
			return err
		}
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(finalPath), 0o755); err != nil {
		return err
	}
	temp, err := os.CreateTemp(s.tmpDir(), "chunk-*")
	if err != nil {
		return err
	}
	tempPath := temp.Name()
	if _, err := temp.Write(block); err != nil {
		_ = temp.Close()
		_ = os.Remove(tempPath)
		return err
	}
	if err := temp.Close(); err != nil {
		_ = os.Remove(tempPath)
		return err
	}
	if err := syncFileAndParent(tempPath); err != nil {
		_ = os.Remove(tempPath)
		return err
	}
	if err := os.Rename(tempPath, finalPath); err != nil {
		_ = os.Remove(tempPath)
		return err
	}
	return syncDirectory(filepath.Dir(finalPath))
}

// replaceContentRefLocked records a new generation and balances references for
// any generation it replaces. The protection manifest is written first as a
// conservative superset, so cache cleanup cannot race the bbolt transaction.
func (s *Service) replaceContentRefLocked(ref ContentRef, sizes []int64) error {
	if len(ref.Chunks) != len(sizes) {
		return fmt.Errorf("metadata: chunk hashes and sizes differ")
	}
	protection, err := s.chunkProtectionSnapshot()
	if err != nil {
		return err
	}
	for index, hash := range ref.Chunks {
		if !validChunkHash(hash) {
			return fmt.Errorf("metadata: invalid chunk hash %q", hash)
		}
		protection[hash] = sizes[index]
	}
	if err := s.writeChunkProtection(protection); err != nil {
		return err
	}

	var remove []string
	err = s.store.update(func(tx boltTxT) error {
		refs := tx.Bucket([]byte(bucketContentRefs))
		var previous ContentRef
		if raw := refs.Get(contentRefKey(ref.Inode, ref.Generation)); raw != nil {
			if err := decodeJSON(raw, &previous); err != nil {
				return err
			}
		}
		deltas := chunkDeltas(previous.Chunks, ref.Chunks)
		knownSizes := map[string]int64{}
		for index, hash := range ref.Chunks {
			knownSizes[hash] = sizes[index]
		}
		removed, err := applyChunkDeltas(tx, deltas, knownSizes)
		if err != nil {
			return err
		}
		remove = removed
		data, err := encodeJSON(ref)
		if err != nil {
			return err
		}
		return refs.Put(contentRefKey(ref.Inode, ref.Generation), data)
	})
	if err != nil {
		return err
	}
	s.removeChunkFiles(remove)
	s.syncChunkProtectionBestEffortLocked()
	return nil
}

// releaseContent removes one or all staged generations and decrements every
// referenced chunk nlink atomically with ContentRef deletion.
func (s *Service) releaseContent(inode uint64, generation *uint64, removeInode bool) error {
	s.chunkMu.Lock()
	defer s.chunkMu.Unlock()

	var remove []string
	err := s.store.update(func(tx boltTxT) error {
		refs := tx.Bucket([]byte(bucketContentRefs))
		prefix := encodeUint64(inode)
		cursor := refs.Cursor()
		type storedRef struct {
			key []byte
			ref ContentRef
		}
		var found []storedRef
		for key, value := cursor.Seek(prefix); key != nil && bytes.HasPrefix(key, prefix); key, value = cursor.Next() {
			var ref ContentRef
			if err := decodeJSON(value, &ref); err != nil {
				return err
			}
			if generation != nil && ref.Generation != *generation {
				continue
			}
			found = append(found, storedRef{
				key: append([]byte(nil), key...),
				ref: ref,
			})
		}
		deltas := map[string]int64{}
		for _, item := range found {
			for _, hash := range item.ref.Chunks {
				deltas[hash]--
			}
		}
		removed, err := applyChunkDeltas(tx, deltas, nil)
		if err != nil {
			return err
		}
		remove = removed
		for _, item := range found {
			if err := refs.Delete(item.key); err != nil {
				return err
			}
		}
		if removeInode {
			return tx.Bucket([]byte(bucketInodes)).Delete(encodeUint64(inode))
		}
		return nil
	})
	if err != nil {
		return err
	}
	s.removeChunkFiles(remove)
	s.syncChunkProtectionBestEffortLocked()
	return nil
}

func chunkDeltas(oldHashes, newHashes []string) map[string]int64 {
	deltas := map[string]int64{}
	for _, hash := range oldHashes {
		deltas[hash]--
	}
	for _, hash := range newHashes {
		deltas[hash]++
	}
	return deltas
}

func applyChunkDeltas(
	tx boltTxT, deltas map[string]int64, knownSizes map[string]int64,
) ([]string, error) {
	bucket := tx.Bucket([]byte(bucketChunks))
	now := time.Now().UnixNano()
	var remove []string
	for hash, delta := range deltas {
		if delta == 0 {
			continue
		}
		if !validChunkHash(hash) {
			return nil, fmt.Errorf("metadata: invalid chunk hash %q", hash)
		}
		var record chunkRecord
		raw := bucket.Get([]byte(hash))
		if raw == nil {
			if delta < 0 {
				return nil, fmt.Errorf("metadata: missing chunk accounting for %s", hash)
			}
			size, ok := knownSizes[hash]
			if !ok {
				return nil, fmt.Errorf("metadata: unknown chunk size for %s", hash)
			}
			record = chunkRecord{Size: size}
		} else if err := decodeJSON(raw, &record); err != nil {
			return nil, err
		}
		record.Nlink += delta
		record.LastAccessUnixNs = now
		if record.Nlink <= 0 {
			if err := bucket.Delete([]byte(hash)); err != nil {
				return nil, err
			}
			remove = append(remove, hash)
			continue
		}
		data, err := encodeJSON(record)
		if err != nil {
			return nil, err
		}
		if err := bucket.Put([]byte(hash), data); err != nil {
			return nil, err
		}
	}
	return remove, nil
}

// spliceChunks reconstructs an upload file from immutable chunks. The temp
// file is removed after the provider call and swept after interrupted runs.
func (s *Service) spliceChunks(hashes []string, label string) (string, error) {
	s.chunkMu.Lock()
	defer s.chunkMu.Unlock()

	if err := os.MkdirAll(s.tmpDir(), 0o755); err != nil {
		return "", err
	}
	file, err := os.CreateTemp(s.tmpDir(), "upload-"+safeChunkLabel(label)+"-*")
	if err != nil {
		return "", err
	}
	target := file.Name()
	for _, hash := range hashes {
		if !validChunkHash(hash) {
			_ = file.Close()
			_ = os.Remove(target)
			return "", fmt.Errorf("metadata: invalid chunk hash %q", hash)
		}
		source, err := os.Open(s.chunkPath(hash))
		if err != nil {
			_ = file.Close()
			_ = os.Remove(target)
			return "", fmt.Errorf("metadata: chunk %s missing: %w", hash, err)
		}
		_, copyErr := io.Copy(file, source)
		_ = source.Close()
		if copyErr != nil {
			_ = file.Close()
			_ = os.Remove(target)
			return "", copyErr
		}
	}
	if err := file.Close(); err != nil {
		_ = os.Remove(target)
		return "", err
	}
	if err := s.touchChunksLocked(hashes); err != nil {
		_ = os.Remove(target)
		return "", err
	}
	return target, nil
}

func (s *Service) touchChunksLocked(hashes []string) error {
	return s.store.update(func(tx boltTxT) error {
		bucket := tx.Bucket([]byte(bucketChunks))
		now := time.Now().UnixNano()
		for _, hash := range hashes {
			raw := bucket.Get([]byte(hash))
			if raw == nil {
				return fmt.Errorf("metadata: chunk %s has no accounting", hash)
			}
			var record chunkRecord
			if err := decodeJSON(raw, &record); err != nil {
				return err
			}
			record.LastAccessUnixNs = now
			data, err := encodeJSON(record)
			if err != nil {
				return err
			}
			if err := bucket.Put([]byte(hash), data); err != nil {
				return err
			}
		}
		return nil
	})
}

func (s *Service) removeChunkFiles(hashes []string) {
	for _, hash := range hashes {
		_ = os.Remove(s.chunkPath(hash))
	}
}

func (s *Service) chunkFiles() ([]string, error) {
	root := filepath.Join(s.chunkStoreRoot(), "chunks")
	var files []string
	err := filepath.Walk(root, func(path string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			if os.IsNotExist(walkErr) {
				return nil
			}
			return walkErr
		}
		if !info.IsDir() {
			files = append(files, path)
		}
		return nil
	})
	return files, err
}

// SweepChunkStore removes files absent from the bbolt chunk table, rebuilds
// the cache-cleaner manifest, and clears stale upload temporaries at startup.
func (s *Service) SweepChunkStore() error {
	s.chunkMu.Lock()
	defer s.chunkMu.Unlock()

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
	return s.writeChunkProtection(protection)
}

func validChunkHash(hash string) bool {
	if len(hash) != sha256.Size*2 {
		return false
	}
	_, err := hex.DecodeString(hash)
	return err == nil
}

func safeChunkLabel(value string) string {
	value = strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' {
			return r
		}
		return '-'
	}, value)
	if value == "" {
		return "write"
	}
	return value
}

func syncDirectory(path string) error {
	dir, err := os.Open(path)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

func chunkFileMatches(path, expected string) (bool, error) {
	file, err := os.Open(path)
	if err != nil {
		return false, err
	}
	defer file.Close()
	sum := sha256.New()
	if _, err := io.Copy(sum, file); err != nil {
		return false, err
	}
	return hex.EncodeToString(sum.Sum(nil)) == expected, nil
}
