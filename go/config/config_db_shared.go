// Process-wide ownership of config.db keeps bbolt safe across concurrent FFI calls.
package config

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	bolt "go.etcd.io/bbolt"
)

// configDBRegistry owns the one bbolt handle for the current app-data root.
// Android's fcntl locks are process-associated, so opening config.db per call
// would let concurrent Dart workers mutate independent bbolt freelists.
type configDBRegistry struct {
	mu        sync.Mutex
	changed   *sync.Cond
	db        *bolt.DB
	path      string
	leases    int
	switching bool
}

var sharedConfigDB = newConfigDBRegistry()

func newConfigDBRegistry() *configDBRegistry {
	registry := &configDBRegistry{}
	registry.changed = sync.NewCond(&registry.mu)
	return registry
}

// acquireConfigDB returns the process-wide handle plus a lease release
// function. Every caller must release after its final transaction; root
// changes wait for outstanding leases before closing the old handle.
func acquireConfigDB() (*bolt.DB, func(), error) {
	return sharedConfigDB.acquire()
}

func (registry *configDBRegistry) acquire() (*bolt.DB, func(), error) {
	for {
		registry.mu.Lock()
		for registry.switching {
			registry.changed.Wait()
		}

		path, err := configDBPath()
		if err != nil {
			registry.mu.Unlock()
			return nil, nil, err
		}
		path = filepath.Clean(path)

		if registry.db != nil && registry.path != path {
			registry.switching = true
			for registry.leases > 0 {
				registry.changed.Wait()
			}
			stale := registry.db
			registry.db = nil
			registry.path = ""
			registry.mu.Unlock()
			err := stale.Close()
			registry.mu.Lock()
			registry.switching = false
			registry.changed.Broadcast()
			registry.mu.Unlock()
			if err != nil {
				return nil, nil, fmt.Errorf("close previous config db: %w", err)
			}
			continue
		}

		if registry.db == nil {
			registry.switching = true
			registry.mu.Unlock()
			db, openErr := openConfigDBFile(path)
			registry.mu.Lock()
			if openErr == nil {
				registry.db = db
				registry.path = path
			}
			registry.switching = false
			registry.changed.Broadcast()
			if openErr != nil {
				registry.mu.Unlock()
				return nil, nil, openErr
			}
		}

		registry.leases++
		db := registry.db
		registry.mu.Unlock()

		var once sync.Once
		return db, func() {
			once.Do(registry.release)
		}, nil
	}
}

func (registry *configDBRegistry) release() {
	registry.mu.Lock()
	defer registry.mu.Unlock()
	registry.leases--
	if registry.leases < 0 {
		panic("config db lease released too many times")
	}
	if registry.leases == 0 {
		registry.changed.Broadcast()
	}
}

// switchConfigDBRoot runs [update] only after all callers have returned their
// leases and the old handle has closed. Mobile hosts call it before changing
// their private data root; tests use the nil form before changing HOME.
func switchConfigDBRoot(update func()) error {
	return sharedConfigDB.switchRootIf(nil, update)
}

// setConfigDBRoot changes a mobile host's root only when it differs from the
// current clean override. The comparison happens while root switches are
// excluded, so a reconnect to the same directory keeps active leases intact.
func setConfigDBRoot(root string) error {
	return sharedConfigDB.switchRootIf(func() bool {
		appDataRootOverride.RLock()
		defer appDataRootOverride.RUnlock()
		return appDataRootOverride.path != root
	}, func() {
		appDataRootOverride.Lock()
		appDataRootOverride.path = root
		appDataRootOverride.Unlock()
	})
}

func (registry *configDBRegistry) switchRootIf(shouldSwitch func() bool, update func()) error {
	registry.mu.Lock()
	for registry.switching {
		registry.changed.Wait()
	}
	if shouldSwitch != nil && !shouldSwitch() {
		registry.mu.Unlock()
		return nil
	}
	registry.switching = true
	for registry.leases > 0 {
		registry.changed.Wait()
	}
	stale := registry.db
	registry.db = nil
	registry.path = ""
	registry.mu.Unlock()

	var err error
	if stale != nil {
		err = stale.Close()
	}

	registry.mu.Lock()
	if update != nil {
		update()
	}
	registry.switching = false
	registry.changed.Broadcast()
	registry.mu.Unlock()
	if err != nil {
		return fmt.Errorf("close config db for root switch: %w", err)
	}
	return nil
}

// openConfigDBFile creates one handle after the registry has excluded other
// local opens. The bbolt file lock continues to protect against another
// process using the same app-data root.
func openConfigDBFile(path string) (*bolt.DB, error) {
	dbExists := pathExists(path)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, fmt.Errorf("create config dir: %w", err)
	}
	db, err := bolt.Open(path, 0o600, &bolt.Options{Timeout: 5 * time.Second})
	if err != nil {
		return nil, fmt.Errorf("open config db: %w", err)
	}
	if err := db.Update(func(tx *bolt.Tx) error {
		if _, err := tx.CreateBucketIfNotExists(profilesBucketKey); err != nil {
			return fmt.Errorf("create profiles bucket: %w", err)
		}
		if _, err := tx.CreateBucketIfNotExists(metaBucketKey); err != nil {
			return fmt.Errorf("create meta bucket: %w", err)
		}
		return nil
	}); err != nil {
		_ = db.Close()
		return nil, err
	}
	if !dbExists {
		if err := migrateTomlToBbolt(db); err != nil {
			// Log but don't fail — the user can still start fresh.
			fmt.Fprintf(os.Stderr, "[config] TOML migration warning: %v\n", err)
		}
	}
	return db, nil
}
