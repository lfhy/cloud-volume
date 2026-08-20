// Protection manifests let cache maintenance preserve referenced chunk files
// without importing the metadata package (which would create a config cycle).
package metadata

import (
	"log"
	"os"
	"path/filepath"
	"time"
)

const chunkProtectionFile = "protection.json"

type chunkProtection struct {
	Version      int
	Conservative bool
	Chunks       map[string]int64
}

const chunkProtectionDebounce = 250 * time.Millisecond

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
	if err := s.writeChunkProtectionState(protected, false); err != nil {
		return err
	}
	s.chunkProtectionDirty = false
	s.stopChunkProtectionTimerLocked()
	return nil
}

// finishChunkProtectionWindowLocked starts the idle timer only after the
// transaction that owns this staging pass has committed. Before that point the
// conservative marker must remain durable because the newly written files
// have no bbolt links yet.
func (s *Service) finishChunkProtectionWindowLocked() {
	if s.chunkProtectionDirty {
		s.scheduleChunkProtectionFinalizeLocked()
	}
}

// syncChunkProtectionBestEffortLocked cannot change the outcome of a bbolt
// commit. Its previous manifest is a safe over-approximation after failures,
// so retrying a remotely completed journal operation would be worse than
// logging and letting a later sweep repair the cache-cleaner view.
func (s *Service) syncChunkProtectionBestEffortLocked() {
	if s.chunkProtectionDirty {
		s.scheduleChunkProtectionFinalizeLocked()
		return
	}
	protected, err := s.chunkProtectionSnapshot()
	if err != nil {
		log.Printf("[metadata/chunks] protection-snapshot namespace=%q err=%v", s.store.namespace.ID, err)
		return
	}
	if err := s.writeChunkProtectionState(protected, false); err != nil {
		log.Printf("[metadata/chunks] protection-sync namespace=%q err=%v", s.store.namespace.ID, err)
	}
}

// beginChunkProtectionLocked publishes one durable conservative marker before
// a staging pass. The marker protects the entire namespace until the quiet
// debounce closes the window, so all chunks staged by a Finder burst share one
// pair of manifest durability fences.
func (s *Service) beginChunkProtectionLocked() error {
	if s.chunkProtectionDirty {
		return nil
	}
	protected, err := s.chunkProtectionSnapshot()
	if err != nil {
		return err
	}
	if err := s.writeChunkProtectionState(protected, true); err != nil {
		return err
	}
	s.chunkProtectionDirty = true
	return nil
}

func (s *Service) scheduleChunkProtectionFinalizeLocked() {
	if s.chunkProtectionTimer != nil {
		s.chunkProtectionTimer.Stop()
	}
	s.chunkProtectionTimer = time.AfterFunc(chunkProtectionDebounce, func() {
		s.chunkMu.Lock()
		defer s.chunkMu.Unlock()
		if s.chunkProtectionClosed || !s.chunkProtectionDirty {
			return
		}
		protected, err := s.chunkProtectionSnapshot()
		if err != nil {
			log.Printf("[metadata/chunks] protection-finalize namespace=%q err=%v", s.store.namespace.ID, err)
			s.retryChunkProtectionFinalizeLocked()
			return
		}
		if err := s.writeChunkProtectionState(protected, false); err != nil {
			log.Printf("[metadata/chunks] protection-finalize namespace=%q err=%v", s.store.namespace.ID, err)
			s.retryChunkProtectionFinalizeLocked()
			return
		}
		s.chunkProtectionDirty = false
		s.chunkProtectionTimer = nil
	})
}

// retryChunkProtectionFinalizeLocked keeps the conservative marker live after
// a transient filesystem failure instead of relying on an unrelated mutation
// or restart to repair the cache-cleaner view.
func (s *Service) retryChunkProtectionFinalizeLocked() {
	if s.chunkProtectionClosed || !s.chunkProtectionDirty {
		return
	}
	s.scheduleChunkProtectionFinalizeLocked()
}

func (s *Service) stopChunkProtectionTimerLocked() {
	if s.chunkProtectionTimer != nil {
		s.chunkProtectionTimer.Stop()
		s.chunkProtectionTimer = nil
	}
}

// writeChunkProtectionState atomically publishes a protected set. A
// conservative set protects every chunk file in the namespace; exact sets are
// written only after the burst is idle or while releasing content.
func (s *Service) writeChunkProtectionState(chunks map[string]int64, conservative bool) error {
	root := s.chunkStoreRoot()
	if err := os.MkdirAll(root, 0o755); err != nil {
		return err
	}
	data, err := encodeJSON(chunkProtection{Version: 1, Conservative: conservative, Chunks: chunks})
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
	return syncDirectory(root)
}
