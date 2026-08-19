// Protection manifests let cache maintenance preserve referenced chunk files
// without importing the metadata package (which would create a config cycle).
package metadata

import (
	"log"
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

// syncChunkProtectionBestEffortLocked cannot change the outcome of a bbolt
// commit. Its previous manifest is a safe over-approximation after failures,
// so retrying a remotely completed journal operation would be worse than
// logging and letting a later sweep repair the cache-cleaner view.
func (s *Service) syncChunkProtectionBestEffortLocked() {
	if err := s.syncChunkProtectionLocked(); err != nil {
		log.Printf("[metadata/chunks] protection-sync namespace=%q err=%v", s.store.namespace.ID, err)
	}
}

// protectChunkBeforeCommitLocked publishes a prospective chunk before moving
// the file into its hash path. protection belongs to the whole staging pass,
// so earlier uncommitted blocks remain protected when later blocks are added.
func (s *Service) protectChunkBeforeCommitLocked(protection map[string]int64, hash string, size int64) error {
	protection[hash] = size
	return s.writeChunkProtection(protection)
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
	if err := temp.Sync(); err != nil {
		_ = temp.Close()
		_ = os.Remove(tempPath)
		return err
	}
	if err := temp.Close(); err != nil {
		_ = os.Remove(tempPath)
		return err
	}
	if err := os.Rename(tempPath, s.chunkProtectionPath()); err != nil {
		_ = os.Remove(tempPath)
		return err
	}
	// Temp and final live in root, so this one parent sync persists the rename.
	return syncDirectory(root)
}
