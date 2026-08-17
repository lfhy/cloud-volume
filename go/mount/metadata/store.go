// Store initialization owns bbolt schema creation and transaction serialization.
package metadata

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	bolt "go.etcd.io/bbolt"
)

// Store owns one bbolt database and serializes every write transaction.
type Store struct {
	namespace Namespace
	chunkRoot string
	db        *bolt.DB
	mu        sync.Mutex
}

// OpenStore opens (creating when necessary) one namespace database.
func OpenStore(namespace Namespace) (*Store, error) {
	if namespace.ID == "" || namespace.Root == "" {
		return nil, fmt.Errorf("metadata: namespace id and root are required")
	}
	if err := os.MkdirAll(namespace.Root, 0o755); err != nil {
		return nil, fmt.Errorf("metadata: create namespace dir: %w", err)
	}
	db, err := bolt.Open(namespace.Root+"/metadata.db", 0o600, &bolt.Options{Timeout: 5 * time.Second})
	if err != nil {
		return nil, fmt.Errorf("metadata: open %s: %w", namespace.Root, err)
	}
	store := &Store{namespace: namespace, db: db}
	if err := store.ensureSchema(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return store, nil
}

func (s *Store) ensureSchema() error {
	return s.db.Update(func(tx *bolt.Tx) error {
		schema, err := tx.CreateBucketIfNotExists([]byte(bucketSchema))
		if err != nil {
			return err
		}
		versionData := schema.Get([]byte("version"))
		if versionData != nil {
			if version := decodeUint64(versionData); version != SchemaVersion {
				return fmt.Errorf("metadata: unsupported schema version %d", version)
			}
			chunkRoot := string(schema.Get([]byte("chunkRoot")))
			if chunkRoot == "" {
				return fmt.Errorf("metadata: chunk root is missing")
			}
			s.chunkRoot = chunkRoot
		}
		for name := range map[string]struct{}{
			bucketInodes: {}, bucketDirents: {}, bucketJournal: {}, bucketListingState: {},
			bucketContentRefs: {}, bucketChunks: {}, bucketReadyOps: {}, bucketInodeOps: {},
		} {
			if _, err := tx.CreateBucketIfNotExists([]byte(name)); err != nil {
				return err
			}
		}
		if versionData != nil {
			return nil
		}
		chunkRoot := s.namespace.CacheRoot
		if chunkRoot == "" {
			chunkRoot = s.namespace.Root
		}
		chunkRoot = filepath.Clean(chunkRoot)
		if err := schema.Put([]byte("version"), encodeUint64(SchemaVersion)); err != nil {
			return err
		}
		if err := schema.Put([]byte("namespace"), []byte(s.namespace.ID)); err != nil {
			return err
		}
		if err := schema.Put([]byte("nextInode"), encodeUint64(rootInode)); err != nil {
			return err
		}
		if err := schema.Put([]byte("chunkRoot"), []byte(chunkRoot)); err != nil {
			return err
		}
		s.chunkRoot = chunkRoot
		return putInode(tx, Inode{
			ID: rootInode, Kind: KindDirectory, DesiredParentID: rootInode,
			RemoteParentID: rootInode, State: StateSynced, LocalRevision: 1,
		})
	})
}

// Close releases the bbolt handle.
func (s *Store) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.db.Close()
}
