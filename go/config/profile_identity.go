// Profile identity keeps metadata namespaces stable across profile presentation edits.
package config

import (
	"encoding/json"

	"github.com/google/uuid"
	bolt "go.etcd.io/bbolt"
)

func ensureProfileIdentity(bucket *bolt.Bucket, name string, config *RemoteStorageConfig) {
	if config == nil || config.ProfileID != "" {
		return
	}
	if existing := bucket.Get([]byte(name)); existing != nil {
		var prior RemoteStorageConfig
		if json.Unmarshal(existing, &prior) == nil {
			config.ProfileID = prior.ProfileID
		}
	}
	if config.ProfileID == "" {
		config.ProfileID = uuid.NewString()
	}
}
