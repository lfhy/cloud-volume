package config

import (
	"encoding/json"
	"fmt"

	bolt "go.etcd.io/bbolt"
)

// Global proxy persistence lives in the meta bucket, separate from account
// profiles, so per-account settings can inherit it without duplicating values.
var globalProxyKey = []byte("global_proxy")

// ProxySettings is the persisted global proxy subset of RemoteStorageConfig.
type ProxySettings struct {
	ProxyMode     string `json:"proxyMode"`
	ProxyType     string `json:"proxyType"`
	ProxyHost     string `json:"proxyHost"`
	ProxyPort     string `json:"proxyPort"`
	ProxyUsername string `json:"proxyUsername"`
	ProxyPassword string `json:"proxyPassword"`
}

// LoadGlobalProxy reads the global proxy settings. If none have been saved,
// system proxy is used to preserve the historical default behaviour.
func LoadGlobalProxy() (RemoteStorageConfig, error) {
	result := DefaultConfig()
	result.ProxyMode = ProxyModeSystem
	db, release, err := acquireConfigDB()
	if err != nil {
		return result, err
	}
	defer release()

	err = db.View(func(tx *bolt.Tx) error {
		data := tx.Bucket(metaBucketKey).Get(globalProxyKey)
		if len(data) == 0 {
			return nil
		}
		var settings ProxySettings
		if err := json.Unmarshal(data, &settings); err != nil {
			return fmt.Errorf("decode global proxy: %w", err)
		}
		result.ProxyMode = normalizeGlobalProxyMode(settings.ProxyMode)
		result.ProxyType = normalizeProxyType(settings.ProxyType)
		result.ProxyHost = settings.ProxyHost
		result.ProxyPort = settings.ProxyPort
		result.ProxyUsername = settings.ProxyUsername
		result.ProxyPassword = settings.ProxyPassword
		return nil
	})
	return result, err
}

// SaveGlobalProxy stores the global proxy settings in the config DB meta bucket.
func SaveGlobalProxy(cfg RemoteStorageConfig) error {
	settings := ProxySettings{
		ProxyMode:     normalizeGlobalProxyMode(cfg.ProxyMode),
		ProxyType:     normalizeProxyType(cfg.ProxyType),
		ProxyHost:     cfg.ProxyHost,
		ProxyPort:     cfg.ProxyPort,
		ProxyUsername: cfg.ProxyUsername,
		ProxyPassword: cfg.ProxyPassword,
	}
	data, err := json.Marshal(settings)
	if err != nil {
		return fmt.Errorf("encode global proxy: %w", err)
	}
	db, release, err := acquireConfigDB()
	if err != nil {
		return err
	}
	defer release()
	return db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(metaBucketKey).Put(globalProxyKey, data)
	})
}

func normalizeGlobalProxyMode(mode string) string {
	normalized := normalizeProxyMode(mode)
	if normalized == ProxyModeInherit {
		return ProxyModeSystem
	}
	return normalized
}
