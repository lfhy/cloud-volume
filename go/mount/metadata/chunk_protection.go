// Protection manifests let cache maintenance preserve referenced chunk files
// without importing the metadata package (which would create a config cycle).
package metadata

import (
	"os"
	"path/filepath"
)

const chunkProtectionFile = "protection.json"

type chunkProtection struct {
	Version int
	Chunks  map[string]int64
}

func (s *Service) chunkProtectionPath() string {
	return filepath.Join(s.chunkStoreRoot(), chunkProtectionFile)
}

func (s *Service) chunkProtectionSnapshot() (map[string]int64, error) {
	protected := map[string]int64{}
	err := s.store.view(func(tx boltTxT) error {
		return tx.Bucket([]byte(bucketChunks)).ForEach(func(key, value []byte) error {
			var record chunkRecord
			if err := decodeJSON(value, &record); err != nil {
				return err
			}
			if record.Nlink > 0 {
				protected[string(key)] = record.Size
			}
			return nil
		})
	})
	return protected, err
}

func (s *Service) syncChunkProtectionLocked() error {
	protected, err := s.chunkProtectionSnapshot()
	if err != nil {
		return err
	}
	return s.writeChunkProtection(protected)
}

// protectChunkBeforeCommitLocked publishes a prospective chunk before moving
// the file into its hash path. The manifest can be a harmless superset after a
// failed write, but it never exposes a live staged block to cache eviction.
func (s *Service) protectChunkBeforeCommitLocked(hash string, size int64) error {
	protected, err := s.chunkProtectionSnapshot()
	if err != nil {
		return err
	}
	protected[hash] = size
	return s.writeChunkProtection(protected)
}

// writeChunkProtection atomically publishes a conservative protected set.
// Writers publish before adding bbolt references; release publishes after
// dropping them. A crash can therefore overprotect stale data, never evict a
// live pending block.
func (s *Service) writeChunkProtection(chunks map[string]int64) error {
	root := s.chunkStoreRoot()
	if err := os.MkdirAll(root, 0o755); err != nil {
		return err
	}
	data, err := encodeJSON(chunkProtection{Version: 1, Chunks: chunks})
	if err != nil {
		return err
	}
	temp, err := os.CreateTemp(root, ".protection-*")
	if err != nil {
		return err
	}
	tempPath := temp.Name()
	if _, err := temp.Write(data); err != nil {
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
	if err := os.Rename(tempPath, s.chunkProtectionPath()); err != nil {
		_ = os.Remove(tempPath)
		return err
	}
	return syncDirectory(root)
}
