package config

import (
	"path"
	"strings"
)

// RemoteStorageConfig stores account connection values persisted to TOML.
type RemoteStorageConfig struct {
	Endpoint                    string                    `json:"endpoint" toml:"endpoint"`
	StorageType                 string                    `json:"storageType" toml:"storage_type"`
	ProviderType                string                    `json:"providerType" toml:"provider_type"`
	DisplayName                 string                    `json:"displayName" toml:"display_name"`
	MappedBucketName            string                    `json:"mappedBucketName" toml:"mapped_bucket_name"`
	Region                      string                    `json:"region" toml:"region"`
	Bucket                      string                    `json:"bucket" toml:"bucket"`
	AccessKeyID                 string                    `json:"accessKeyId" toml:"access_key_id"`
	SecretAccessKey             string                    `json:"secretAccessKey" toml:"secret_access_key"`
	HasSecretAccessKey          bool                      `json:"hasSecretAccessKey" toml:"-"`
	WebDAVUsername              string                    `json:"webdavUsername" toml:"webdav_username"`
	WebDAVPassword              string                    `json:"webdavPassword" toml:"webdav_password"`
	HasWebDAVPassword           bool                      `json:"hasWebdavPassword" toml:"-"`
	RootPrefix                  string                    `json:"rootPrefix" toml:"root_prefix"`
	DefaultDownloadDirectory    string                    `json:"defaultDownloadDirectory" toml:"default_download_directory"`
	CacheDirectory              string                    `json:"cacheDirectory" toml:"cache_directory"`
	ResolvedCacheDirectory      string                    `json:"resolvedCacheDirectory" toml:"-"`
	HideDotFiles                bool                      `json:"hideDotFiles" toml:"hide_dot_files"`
	FileOpenMode                string                    `json:"fileOpenMode" toml:"file_open_mode"`
	TrashDirectoryName          string                    `json:"trashDirectoryName" toml:"trash_directory_name"`
	TrashRetentionDays          int                       `json:"trashRetentionDays" toml:"trash_retention_days"`
	BucketSettings              map[string]BucketSettings `json:"bucketSettings" toml:"bucket_settings"`
	WritebackQuietSeconds       int                       `json:"writebackQuietSeconds" toml:"writeback_quiet_seconds"`
	MountMetadataCacheSeconds   int                       `json:"mountMetadataCacheSeconds" toml:"mount_metadata_cache_seconds"`
	UsePathStyle                bool                      `json:"usePathStyle" toml:"use_path_style"`
	WindowsMountMode            string                    `json:"windowsMountMode" toml:"windows_mount_mode"`
	WindowsThisPcEntryEnabled   bool                      `json:"windowsThisPcEntryEnabled" toml:"windows_this_pc_entry_enabled"`
	WindowsWritebackConcurrency int                       `json:"windowsWritebackConcurrency" toml:"windows_writeback_concurrency"`
}

type BucketSettings struct {
	ReadOnly       bool   `json:"readOnly" toml:"read_only"`
	TrashEnabled   *bool  `json:"trashEnabled,omitempty" toml:"trash_enabled,omitempty"`
	TrashDirectory string `json:"trashDirectory" toml:"trash_directory"`
}

const (
	StorageTypeS3                      = "s3"
	StorageTypeWebDAV                  = "webdav"
	StorageTypeBaiduPan                = "baidu_pan"
	WindowsMountModeCloudFilesCached   = "cloud_files_cached"
	WindowsMountModeCloudFilesDirect   = "cloud_files_direct"
	WindowsMountModeWebDAV             = "webdav"
	defaultWritebackQuietSeconds       = 10
	maxWritebackQuietSeconds           = 300
	defaultTrashRetentionDays          = 30
	defaultMountMetadataCacheSeconds   = 60
	maxMountMetadataCacheSeconds       = 3600
	defaultWindowsWritebackConcurrency = 4
	maxWindowsWritebackConcurrency     = 32
)

// BootstrapState is the typed payload returned to Flutter during startup.
type BootstrapState struct {
	ConfigPath string              `json:"configPath"`
	Configured bool                `json:"configured"`
	Config     RemoteStorageConfig `json:"config"`
	Profiles   []ProfileInfo       `json:"profiles"`
}

// DefaultConfig seeds new users with path-style access enabled for broader compatibility.
func DefaultConfig() RemoteStorageConfig {
	return RemoteStorageConfig{
		HideDotFiles:                true,
		FileOpenMode:                "double_click",
		TrashDirectoryName:          ".trash",
		TrashRetentionDays:          -1,
		BucketSettings:              map[string]BucketSettings{},
		WritebackQuietSeconds:       defaultWritebackQuietSeconds,
		MountMetadataCacheSeconds:   defaultMountMetadataCacheSeconds,
		UsePathStyle:                true,
		WindowsMountMode:            WindowsMountModeCloudFilesCached,
		WindowsThisPcEntryEnabled:   false,
		WindowsWritebackConcurrency: defaultWindowsWritebackConcurrency,
	}
}

// Normalized trims user input and keeps prefix formatting stable across reads and writes.
func (c RemoteStorageConfig) Normalized() RemoteStorageConfig {
	return RemoteStorageConfig{
		Endpoint:                    strings.TrimSpace(c.Endpoint),
		StorageType:                 normalizeStorageType(c.StorageType),
		ProviderType:                normalizeProviderType(c.ProviderType, c.Endpoint, c.StorageType),
		DisplayName:                 strings.TrimSpace(c.DisplayName),
		MappedBucketName:            normalizeMappedBucketName(c.StorageType, c.MappedBucketName, c.DisplayName),
		Region:                      strings.TrimSpace(c.Region),
		Bucket:                      strings.TrimSpace(c.Bucket),
		AccessKeyID:                 strings.TrimSpace(c.AccessKeyID),
		SecretAccessKey:             strings.TrimSpace(c.SecretAccessKey),
		HasSecretAccessKey:          strings.TrimSpace(c.SecretAccessKey) != "" || c.HasSecretAccessKey,
		WebDAVUsername:              strings.TrimSpace(c.WebDAVUsername),
		WebDAVPassword:              strings.TrimSpace(c.WebDAVPassword),
		HasWebDAVPassword:           strings.TrimSpace(c.WebDAVPassword) != "" || c.HasWebDAVPassword,
		RootPrefix:                  strings.Trim(strings.TrimSpace(c.RootPrefix), "/"),
		DefaultDownloadDirectory:    strings.TrimSpace(c.DefaultDownloadDirectory),
		CacheDirectory:              strings.TrimSpace(c.CacheDirectory),
		ResolvedCacheDirectory:      strings.TrimSpace(c.ResolvedCacheDirectory),
		HideDotFiles:                c.HideDotFiles,
		FileOpenMode:                normalizeFileOpenMode(c.FileOpenMode),
		TrashDirectoryName:          normalizeTrashDirectoryName(c.TrashDirectoryName),
		TrashRetentionDays:          normalizeTrashRetentionDays(c.TrashRetentionDays),
		BucketSettings:              normalizeBucketSettings(c.BucketSettings),
		WritebackQuietSeconds:       normalizeWritebackQuietSeconds(c.WritebackQuietSeconds),
		MountMetadataCacheSeconds:   normalizeMountMetadataCacheSeconds(c.MountMetadataCacheSeconds),
		UsePathStyle:                c.UsePathStyle,
		WindowsMountMode:            normalizeWindowsMountMode(c.WindowsMountMode),
		WindowsThisPcEntryEnabled:   c.WindowsThisPcEntryEnabled,
		WindowsWritebackConcurrency: normalizeWindowsWritebackConcurrency(c.WindowsWritebackConcurrency),
	}
}

// WithResolvedCacheDirectory fills the platform default cache path for UI/runtime use.
func (c RemoteStorageConfig) WithResolvedCacheDirectory() (RemoteStorageConfig, error) {
	normalized := c.Normalized()
	cacheDir, err := ResolveCacheDir(normalized)
	if err != nil {
		return RemoteStorageConfig{}, err
	}
	normalized.ResolvedCacheDirectory = cacheDir
	return normalized, nil
}

// IsConfigured defines the minimum first-run fields required to leave setup mode.
// Bucket and root prefix are optional — only endpoint + auth keys are required.
func (c RemoteStorageConfig) IsConfigured() bool {
	normalized := c.Normalized()
	if normalized.Endpoint == "" {
		return false
	}
	if normalized.StorageType == StorageTypeBaiduPan {
		return normalized.AccessKeyID != "" &&
			(normalized.SecretAccessKey != "" || normalized.HasSecretAccessKey)
	}
	if normalized.StorageType == StorageTypeWebDAV {
		return normalized.WebDAVUsername != "" &&
			(normalized.WebDAVPassword != "" || normalized.HasWebDAVPassword)
	}
	return normalized.AccessKeyID != "" &&
		(normalized.SecretAccessKey != "" || normalized.HasSecretAccessKey)
}

// HasWebDAVCredentials reports whether web login credentials are complete.
func (c RemoteStorageConfig) HasWebDAVCredentials() bool {
	normalized := c.Normalized()
	return normalized.WebDAVUsername != "" &&
		(normalized.WebDAVPassword != "" || normalized.HasWebDAVPassword)
}

// MergeStoredSecrets keeps existing secrets when the client intentionally omits them.
func (c RemoteStorageConfig) MergeStoredSecrets(existing RemoteStorageConfig) RemoteStorageConfig {
	normalized := c.Normalized()
	current := existing.Normalized()
	if normalized.SecretAccessKey == "" &&
		normalized.HasSecretAccessKey &&
		current.SecretAccessKey != "" {
		normalized.SecretAccessKey = current.SecretAccessKey
	}
	if normalized.WebDAVPassword == "" &&
		normalized.HasWebDAVPassword &&
		current.WebDAVPassword != "" {
		normalized.WebDAVPassword = current.WebDAVPassword
	}
	normalized.HasSecretAccessKey = normalized.SecretAccessKey != "" || normalized.HasSecretAccessKey
	normalized.HasWebDAVPassword = normalized.WebDAVPassword != "" || normalized.HasWebDAVPassword
	return normalized
}

// WithDefaultWebDAVCredentials falls back to AK/SK when web credentials are omitted.
func (c RemoteStorageConfig) WithDefaultWebDAVCredentials() RemoteStorageConfig {
	normalized := c.Normalized()
	if normalized.StorageType == StorageTypeWebDAV ||
		normalized.StorageType == StorageTypeBaiduPan {
		return normalized
	}
	if normalized.WebDAVUsername == "" {
		normalized.WebDAVUsername = normalized.AccessKeyID
	}
	if normalized.WebDAVPassword == "" && normalized.SecretAccessKey != "" {
		normalized.WebDAVPassword = normalized.SecretAccessKey
	}
	normalized.HasWebDAVPassword = normalized.WebDAVPassword != "" || normalized.HasWebDAVPassword
	return normalized
}

// AccountLabel returns the user-facing account name for management views.
func (c RemoteStorageConfig) AccountLabel(fallback string) string {
	normalized := c.Normalized()
	if normalized.DisplayName != "" {
		return normalized.DisplayName
	}
	if normalized.StorageType == StorageTypeBaiduPan {
		if fallback != "" {
			return fallback
		}
		return "百度网盘"
	}
	if normalized.AccessKeyID != "" {
		return normalized.AccessKeyID
	}
	if normalized.WebDAVUsername != "" {
		return normalized.WebDAVUsername
	}
	if fallback != "" {
		return fallback
	}
	return "未命名账号"
}

// MappedBucketLabel returns the virtual bucket name used by single-root backends.
func (c RemoteStorageConfig) MappedBucketLabel() string {
	normalized := c.Normalized()
	return normalized.MappedBucketName
}

// PublicSanitized clears secrets while preserving whether stored secrets exist.
func (c RemoteStorageConfig) PublicSanitized() RemoteStorageConfig {
	normalized := c.Normalized()
	normalized.SecretAccessKey = ""
	normalized.WebDAVPassword = ""
	return normalized
}

func normalizeFileOpenMode(value string) string {
	if strings.EqualFold(strings.TrimSpace(value), "single_click") {
		return "single_click"
	}
	return "double_click"
}

func normalizeStorageType(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case StorageTypeWebDAV:
		return StorageTypeWebDAV
	case StorageTypeBaiduPan:
		return StorageTypeBaiduPan
	default:
		return StorageTypeS3
	}
}

func normalizeMappedBucketName(storageType, value, displayName string) string {
	trimmed := strings.Trim(strings.TrimSpace(value), "/")
	if trimmed != "" {
		return trimmed
	}
	fallback := strings.Trim(strings.TrimSpace(displayName), "/")
	if fallback != "" {
		return fallback
	}
	if normalizeStorageType(storageType) == StorageTypeBaiduPan {
		return "百度网盘"
	}
	return "WebDAV"
}

func normalizeProviderType(value, endpoint, storageType string) string {
	if normalizeStorageType(storageType) == StorageTypeBaiduPan {
		return StorageTypeBaiduPan
	}
	normalized := strings.ToLower(strings.TrimSpace(value))
	switch normalized {
	case "osca", "gfs", "minio", "s3", StorageTypeBaiduPan:
		return normalized
	}
	lowerEndpoint := strings.ToLower(endpoint)
	switch {
	case strings.Contains(lowerEndpoint, "fgws3") ||
		strings.Contains(lowerEndpoint, "ocloud") ||
		strings.Contains(lowerEndpoint, "osca"):
		return "osca"
	case strings.Contains(lowerEndpoint, "gfs"):
		return "gfs"
	case strings.Contains(lowerEndpoint, "minio"):
		return "minio"
	default:
		return "s3"
	}
}

func normalizeTrashRetentionDays(value int) int {
	switch {
	case value < 0:
		return -1
	case value == 0:
		return defaultTrashRetentionDays
	default:
		return value
	}
}

func normalizeWritebackQuietSeconds(value int) int {
	switch {
	case value <= 0:
		return defaultWritebackQuietSeconds
	case value > maxWritebackQuietSeconds:
		return maxWritebackQuietSeconds
	default:
		return value
	}
}

func normalizeMountMetadataCacheSeconds(value int) int {
	switch {
	case value < 0:
		return -1
	case value == 0:
		return defaultMountMetadataCacheSeconds
	case value > maxMountMetadataCacheSeconds:
		return maxMountMetadataCacheSeconds
	default:
		return value
	}
}

func normalizeTrashDirectoryName(value string) string {
	trimmed := strings.Trim(strings.TrimSpace(value), "/")
	if trimmed == "" {
		return ".trash"
	}
	cleaned := strings.TrimPrefix(path.Clean("/"+trimmed), "/")
	if cleaned == "" || cleaned == "." {
		return ".trash"
	}
	if !strings.Contains(cleaned, "/") && !strings.HasPrefix(cleaned, ".") {
		return "." + cleaned
	}
	return cleaned
}

func normalizeBucketSettings(settings map[string]BucketSettings) map[string]BucketSettings {
	result := map[string]BucketSettings{}
	for bucket, setting := range settings {
		cleanBucket := strings.TrimSpace(bucket)
		if cleanBucket == "" {
			continue
		}
		if strings.TrimSpace(setting.TrashDirectory) != "" {
			setting.TrashDirectory = normalizeTrashDirectoryName(setting.TrashDirectory)
		}
		result[cleanBucket] = setting
	}
	return result
}

func (c RemoteStorageConfig) BucketSettingsFor(bucket string) BucketSettings {
	normalized := c.Normalized()
	setting := BucketSettings{
		TrashDirectory: normalized.TrashDirectoryName,
	}
	if normalized.StorageType == StorageTypeS3 {
		enabled := true
		setting.TrashEnabled = &enabled
	} else {
		enabled := false
		setting.TrashEnabled = &enabled
	}
	if override, ok := normalized.BucketSettings[strings.TrimSpace(bucket)]; ok {
		if override.TrashEnabled != nil {
			setting.TrashEnabled = override.TrashEnabled
		}
		if strings.TrimSpace(override.TrashDirectory) != "" {
			setting.TrashDirectory = normalizeTrashDirectoryName(override.TrashDirectory)
		}
		setting.ReadOnly = override.ReadOnly
	}
	return setting
}

func (c RemoteStorageConfig) WithBucketSettingsApplied(bucket string) RemoteStorageConfig {
	normalized := c.Normalized()
	normalized.TrashDirectoryName = normalized.BucketSettingsFor(bucket).TrashDirectory
	return normalized
}

func (s BucketSettings) IsTrashEnabled() bool {
	return s.TrashEnabled != nil && *s.TrashEnabled
}

func normalizeWindowsMountMode(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case WindowsMountModeCloudFilesDirect:
		return WindowsMountModeCloudFilesDirect
	case WindowsMountModeWebDAV:
		return WindowsMountModeWebDAV
	default:
		return WindowsMountModeCloudFilesCached
	}
}

func normalizeWindowsWritebackConcurrency(value int) int {
	switch {
	case value <= 0:
		return defaultWindowsWritebackConcurrency
	case value > maxWindowsWritebackConcurrency:
		return maxWindowsWritebackConcurrency
	default:
		return value
	}
}

// TrashDirectoryAliases returns all reserved bucket-trash roots that should be hidden and protected.
func TrashDirectoryAliases(value string) []string {
	primary := normalizeTrashDirectoryName(value)
	aliases := []string{primary}
	parent := path.Dir(primary)
	base := path.Base(primary)
	aliasBase := ""
	switch base {
	case ".trash":
		aliasBase = ".Trash"
	case ".Trash":
		aliasBase = ".trash"
	}
	if aliasBase != "" {
		alias := aliasBase
		if parent != "." && parent != "" {
			alias = path.Join(parent, aliasBase)
		}
		aliases = append(aliases, alias)
	}
	return aliases
}
