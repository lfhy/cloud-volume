package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	toml "github.com/pelletier/go-toml/v2"
)

// Store owns config file IO so the bridge stays focused on transport concerns.
type Store struct {
	configPath string
}

// NewStore creates a testable config store for an explicit file path.
func NewStore(configPath string) Store {
	return Store{configPath: configPath}
}

// NewDefaultStore targets the platform default config.toml for normal app usage.
func NewDefaultStore() (Store, error) {
	configPath, err := DefaultConfigPath()
	if err != nil {
		return Store{}, err
	}
	return NewStore(configPath), nil
}

// LoadBootstrapState returns the startup payload the Flutter shell needs.
func (s Store) LoadBootstrapState() (BootstrapState, error) {
	config, err := s.Load()
	if err != nil {
		return BootstrapState{}, err
	}
	publicConfig, err := config.WithResolvedCacheDirectory()
	if err != nil {
		return BootstrapState{}, err
	}
	return BootstrapState{
		ConfigPath: s.configPath,
		Configured: config.IsConfigured(),
		Config:     publicConfig,
	}, nil
}

// Load reads TOML when present and otherwise returns an empty default config.
func (s Store) Load() (RemoteStorageConfig, error) {
	if err := s.validate(); err != nil {
		return DefaultConfig(), err
	}

	config := DefaultConfig()
	data, err := os.ReadFile(s.configPath)
	if errors.Is(err, os.ErrNotExist) {
		return config, nil
	}
	if err != nil {
		return config, fmt.Errorf("read config file: %w", err)
	}
	if strings.TrimSpace(string(data)) == "" {
		return config, nil
	}
	if err := toml.Unmarshal(data, &config); err != nil {
		return config, fmt.Errorf("parse config file: %w", err)
	}
	return config.Normalized(), nil
}

// Save persists a normalized configuration and rejects incomplete first-run submissions.
func (s Store) Save(config RemoteStorageConfig) error {
	if err := s.validate(); err != nil {
		return err
	}

	existing, err := s.Load()
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	normalized := config.MergeStoredSecrets(existing).WithDefaultWebDAVCredentials()
	if !normalized.IsConfigured() {
		if normalized.StorageType == StorageTypeBaiduPan {
			return errors.New("请先完成百度网盘授权登录")
		}
		if normalized.StorageType == StorageTypeWebDAV {
			return errors.New("WebDAV 地址、用户名和密码为必填项")
		}
		return errors.New("端点地址、访问密钥 ID 和访问密钥为必填项")
	}
	if err := os.MkdirAll(filepath.Dir(s.configPath), 0o700); err != nil {
		return fmt.Errorf("create config directory: %w", err)
	}

	body, err := toml.Marshal(normalized)
	if err != nil {
		return fmt.Errorf("encode config file: %w", err)
	}

	payload := append([]byte("# Remote Storage configuration.\n"), body...)
	if err := os.WriteFile(s.configPath, payload, 0o600); err != nil {
		return fmt.Errorf("write config file: %w", err)
	}
	return nil
}

func (s Store) validate() error {
	if strings.TrimSpace(s.configPath) == "" {
		return errors.New("config path is empty")
	}
	return nil
}
