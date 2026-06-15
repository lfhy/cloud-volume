// Bootstrap/config helpers keep web responses aligned with the desktop bridge contract.
package webapi

import (
	"fmt"

	storageconfig "remote-storage/go/config"
)

func loadBootstrapState() (storageconfig.BootstrapState, error) {
	_ = storageconfig.MigrateDefault()

	profiles, _ := storageconfig.ListProfiles()
	configured := len(profiles) > 0

	var config storageconfig.RemoteStorageConfig
	var configPath string
	if configured {
		activeName := profiles[0].Name
		for _, profile := range profiles {
			if profile.Active {
				activeName = profile.Name
				break
			}
		}
		loadedConfig, err := storageconfig.LoadProfile(activeName)
		if err != nil {
			return storageconfig.BootstrapState{}, err
		}
		config = loadedConfig
		path, err := storageconfig.ProfileConfigPath(activeName)
		if err != nil {
			return storageconfig.BootstrapState{}, err
		}
		configPath = path
	} else {
		config = storageconfig.DefaultConfig()
		path, err := storageconfig.DefaultConfigPath()
		if err != nil {
			return storageconfig.BootstrapState{}, err
		}
		configPath = path
	}
	publicConfig, err := config.PublicSanitized().WithResolvedCacheDirectory()
	if err != nil {
		return storageconfig.BootstrapState{}, err
	}

	return storageconfig.BootstrapState{
		ConfigPath: configPath,
		Configured: isWebConfigured(config),
		Config:     publicConfig,
		Profiles:   profiles,
	}, nil
}

func loadCurrentConfig() (storageconfig.RemoteStorageConfig, error) {
	_ = storageconfig.MigrateDefault()
	profiles, err := storageconfig.ListProfiles()
	if err != nil {
		return storageconfig.RemoteStorageConfig{}, err
	}
	if len(profiles) == 0 {
		return storageconfig.DefaultConfig(), nil
	}
	activeName := profiles[0].Name
	for _, profile := range profiles {
		if profile.Active {
			activeName = profile.Name
			break
		}
	}
	return storageconfig.LoadProfile(activeName)
}

func requireConfiguredStorage() (storageconfig.RemoteStorageConfig, error) {
	config, err := loadCurrentConfig()
	if err != nil {
		return storageconfig.RemoteStorageConfig{}, err
	}
	if !config.IsConfigured() {
		return storageconfig.RemoteStorageConfig{}, fmt.Errorf("远程存储尚未完成初始化")
	}
	return config, nil
}

func isWebConfigured(config storageconfig.RemoteStorageConfig) bool {
	return config.IsConfigured() && config.HasWebDAVCredentials()
}
