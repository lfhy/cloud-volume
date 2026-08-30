// Profile and bucket display-order helpers for the account/bucket list UIs.
// Order is stored as JSON string arrays in the config.db meta bucket so list
// reordering survives restarts without changing RemoteStorageConfig.

package config

import (
	"encoding/json"
	"fmt"

	"strings"

	bolt "go.etcd.io/bbolt"
)

var (
	profileOrderKey = []byte("profile_order")
	bucketOrderKey  = []byte("bucket_order")
)

// ReorderProfiles persists the user-defined account list order.
// Unknown or empty names are ignored; missing profiles stay appendable later.
func ReorderProfiles(names []string) error {
	clean := sanitizeOrderNames(names)
	db, release, err := acquireConfigDB()
	if err != nil {
		return err
	}
	defer release()
	return db.Update(func(tx *bolt.Tx) error {
		return putOrderJSON(tx, profileOrderKey, clean)
	})
}

// ReorderBuckets persists the global bucket list order using entry ids
// (`profileName::bucketName`), matching Flutter FileManagerBucketEntry.id.
func ReorderBuckets(ids []string) error {
	clean := sanitizeOrderNames(ids)
	db, release, err := acquireConfigDB()
	if err != nil {
		return err
	}
	defer release()
	return db.Update(func(tx *bolt.Tx) error {
		return putOrderJSON(tx, bucketOrderKey, clean)
	})
}

// ListBucketOrder returns the persisted bucket entry ids in display order.
func ListBucketOrder() ([]string, error) {
	db, release, err := acquireConfigDB()
	if err != nil {
		return nil, err
	}
	defer release()
	var order []string
	err = db.View(func(tx *bolt.Tx) error {
		order = loadOrderJSON(tx, bucketOrderKey)
		return nil
	})
	if err != nil {
		return nil, err
	}
	if order == nil {
		order = []string{}
	}
	return order, nil
}

func loadProfileOrder(tx *bolt.Tx) []string {
	return loadOrderJSON(tx, profileOrderKey)
}

func loadBucketOrder(tx *bolt.Tx) []string {
	return loadOrderJSON(tx, bucketOrderKey)
}

func loadOrderJSON(tx *bolt.Tx, key []byte) []string {
	meta := tx.Bucket(metaBucketKey)
	if meta == nil {
		return nil
	}
	data := meta.Get(key)
	if len(data) == 0 {
		return nil
	}
	var order []string
	if err := json.Unmarshal(data, &order); err != nil {
		return nil
	}
	return sanitizeOrderNames(order)
}

func putOrderJSON(tx *bolt.Tx, key []byte, order []string) error {
	meta := tx.Bucket(metaBucketKey)
	if meta == nil {
		return fmt.Errorf("meta bucket missing")
	}
	if len(order) == 0 {
		return meta.Delete(key)
	}
	data, err := json.Marshal(order)
	if err != nil {
		return fmt.Errorf("encode order: %w", err)
	}
	return meta.Put(key, data)
}

func clearListOrders(tx *bolt.Tx) error {
	meta := tx.Bucket(metaBucketKey)
	if meta == nil {
		return nil
	}
	_ = meta.Delete(profileOrderKey)
	_ = meta.Delete(bucketOrderKey)
	return nil
}

// applyNamedOrder reorders items by the given name sequence. Names missing from
// order keep their relative input order and append after ordered items.
func applyNamedOrder[T any](items []T, order []string, nameOf func(T) string) []T {
	if len(items) <= 1 || len(order) == 0 {
		return items
	}
	byName := make(map[string]T, len(items))
	for _, item := range items {
		byName[nameOf(item)] = item
	}
	seen := make(map[string]bool, len(items))
	out := make([]T, 0, len(items))
	for _, name := range order {
		item, ok := byName[name]
		if !ok || seen[name] {
			continue
		}
		out = append(out, item)
		seen[name] = true
	}
	for _, item := range items {
		name := nameOf(item)
		if seen[name] {
			continue
		}
		out = append(out, item)
	}
	return out
}

// appendProfileToOrderIfNeeded adds a newly saved profile to the end of the
// custom order once the user has already customized it.
func appendProfileToOrderIfNeeded(tx *bolt.Tx, name string) error {
	cleanName := sanitizeProfileName(name)
	if cleanName == "" {
		return nil
	}
	order := loadProfileOrder(tx)
	if len(order) == 0 {
		return nil
	}
	for _, existing := range order {
		if existing == cleanName {
			return nil
		}
	}
	return putOrderJSON(tx, profileOrderKey, append(order, cleanName))
}

// removeProfileFromOrder drops a deleted profile name from the custom order.
func removeProfileFromOrder(tx *bolt.Tx, name string) error {
	cleanName := sanitizeProfileName(name)
	if cleanName == "" {
		return nil
	}
	order := loadProfileOrder(tx)
	if len(order) == 0 {
		return nil
	}
	next := order[:0]
	for _, existing := range order {
		if existing == cleanName {
			continue
		}
		next = append(next, existing)
	}
	return putOrderJSON(tx, profileOrderKey, next)
}

// removeBucketsForProfile strips bucket-order entries belonging to a profile.
func removeBucketsForProfile(tx *bolt.Tx, profileName string) error {
	cleanName := sanitizeProfileName(profileName)
	if cleanName == "" {
		return nil
	}
	order := loadBucketOrder(tx)
	if len(order) == 0 {
		return nil
	}
	prefix := cleanName + "::"
	next := order[:0]
	for _, id := range order {
		if len(id) >= len(prefix) && id[:len(prefix)] == prefix {
			continue
		}
		if id == cleanName {
			continue
		}
		next = append(next, id)
	}
	return putOrderJSON(tx, bucketOrderKey, next)
}

func sanitizeOrderNames(names []string) []string {
	if len(names) == 0 {
		return nil
	}
	seen := make(map[string]bool, len(names))
	out := make([]string, 0, len(names))
	for _, name := range names {
		clean := strings.TrimSpace(name)
		if clean == "" || seen[clean] {
			continue
		}
		seen[clean] = true
		out = append(out, clean)
	}
	if len(out) == 0 {
		return nil
	}
	return out
}
