package config

import (
	"encoding/json"
	"strings"
)

// RemoteStorageConfig stores account connection values persisted to TOML.
type RemoteStorageConfig struct {
	Endpoint     string `json:"endpoint" toml:"endpoint"`
	StorageType  string `json:"storageType" toml:"storage_type"`
	ProviderType string `json:"providerType" toml:"provider_type"`
	DisplayName  string `json:"displayName" toml:"display_name"`
	// ProfileID is a stable local account identity used by metadata namespaces.
	// It survives display-name and credential presentation changes.
	ProfileID                   string                        `json:"profileId" toml:"profile_id"`
	MappedBucketName            string                        `json:"mappedBucketName" toml:"mapped_bucket_name"`
	Region                      string                        `json:"region" toml:"region"`
	Bucket                      string                        `json:"bucket" toml:"bucket"`
	AccessKeyID                 string                        `json:"accessKeyId" toml:"access_key_id"`
	SecretAccessKey             string                        `json:"secretAccessKey" toml:"secret_access_key"`
	HasSecretAccessKey          bool                          `json:"hasSecretAccessKey" toml:"-"`
	WebDAVUsername              string                        `json:"webdavUsername" toml:"webdav_username"`
	WebDAVPassword              string                        `json:"webdavPassword" toml:"webdav_password"`
	HasWebDAVPassword           bool                          `json:"hasWebdavPassword" toml:"-"`
	FTPUsername                 string                        `json:"ftpUsername" toml:"ftp_username"`
	FTPPassword                 string                        `json:"ftpPassword" toml:"ftp_password"`
	HasFTPPassword              bool                          `json:"hasFtpPassword" toml:"-"`
	FTPPort                     int                           `json:"ftpPort" toml:"ftp_port"`
	FTPAnonymous                bool                          `json:"ftpAnonymous" toml:"ftp_anonymous"`
	RootPrefix                  string                        `json:"rootPrefix" toml:"root_prefix"`
	DefaultDownloadDirectory    string                        `json:"defaultDownloadDirectory" toml:"default_download_directory"`
	CacheDirectory              string                        `json:"cacheDirectory" toml:"cache_directory"`
	ResolvedCacheDirectory      string                        `json:"resolvedCacheDirectory" toml:"-"`
	HideDotFiles                bool                          `json:"hideDotFiles" toml:"hide_dot_files"`
	FileOpenMode                string                        `json:"fileOpenMode" toml:"file_open_mode"`
	TrashDirectoryName          string                        `json:"trashDirectoryName" toml:"trash_directory_name"`
	TrashRetentionDays          int                           `json:"trashRetentionDays" toml:"trash_retention_days"`
	BucketSettings              map[string]BucketSettings     `json:"bucketSettings" toml:"bucket_settings"`
	BucketViews                 map[string]BucketViewSettings `json:"bucketViews" toml:"bucket_views"`
	WritebackQuietSeconds       int                           `json:"writebackQuietSeconds" toml:"writeback_quiet_seconds"`
	MountMetadataCacheSeconds   int                           `json:"mountMetadataCacheSeconds" toml:"mount_metadata_cache_seconds"`
	MountRemotePollSeconds      int                           `json:"mountRemotePollSeconds" toml:"mount_remote_poll_seconds"`
	UsePathStyle                bool                          `json:"usePathStyle" toml:"use_path_style"`
	WindowsMountMode            string                        `json:"windowsMountMode" toml:"windows_mount_mode"`
	WindowsMountEngine          string                        `json:"windowsMountEngine" toml:"windows_mount_engine"`
	WindowsWinFspCapacityGB     int                           `json:"windowsWinFspCapacityGb" toml:"windows_winfsp_capacity_gb"`
	WindowsThisPcEntryEnabled   bool                          `json:"windowsThisPcEntryEnabled" toml:"windows_this_pc_entry_enabled"`
	WindowsWritebackConcurrency int                           `json:"windowsWritebackConcurrency" toml:"windows_writeback_concurrency"`
	CacheAutoCleanupEnabled     bool                          `json:"cacheAutoCleanupEnabled" toml:"cache_auto_cleanup_enabled"`
	CacheMaxSizeMB              int                           `json:"cacheMaxSizeMb" toml:"cache_max_size_mb"`
	CacheMaxAgeDays             int                           `json:"cacheMaxAgeDays" toml:"cache_max_age_days"`

	// JWanFSGatewayMode controls whether the FGW business APIs (bucket quota,
	// file info, file search, etc.) are enabled. "auto" probes via auth-info;
	// "jwanfs" / "generic_s3" forces the result.
	JWanFSGatewayMode string `json:"jwanfsGatewayMode" toml:"jwanfs_gateway_mode"`

	// Global proxy settings apply to all outbound HTTP/S3/WebDAV traffic.
	ProxyMode     string `json:"proxyMode" toml:"proxy_mode"`         // "system" (default), "direct", "custom"
	ProxyType     string `json:"proxyType" toml:"proxy_type"`         // "http" or "socks5"
	ProxyHost     string `json:"proxyHost" toml:"proxy_host"`         // e.g. "127.0.0.1"
	ProxyPort     string `json:"proxyPort" toml:"proxy_port"`         // e.g. "7890"
	ProxyUsername string `json:"proxyUsername" toml:"proxy_username"` // optional auth
	ProxyPassword string `json:"proxyPassword" toml:"proxy_password"` // optional auth
	// P2PEnabled controls whether this device participates in LAN peer discovery,
	// instant change notification, and content-acceleration for this account.
	P2PEnabled bool `json:"p2pEnabled" toml:"p2p_enabled"`
	// P2PChunkSizeMB is the chunk size in MB used for peer-to-peer content transfer.
	P2PChunkSizeMB int `json:"p2pChunkSizeMb" toml:"p2p_chunk_size_mb"`
	// Disabled marks an account as opted-out of the file manager: a disabled
	// account is not bucket-listed, does not connect to its backend, and does
	// not start P2P. It stays in the account list so the user can re-enable it.
	// The zero value (false) means enabled — no UnmarshalJSON shim is needed.
	Disabled bool `json:"disabled" toml:"disabled"`
}

// UnmarshalJSON preserves an explicitly saved P2P-enabled choice. LAN P2P is
// an off-by-default experimental feature, so profiles written without the
// field (including those saved before P2P shipped) stay disabled; only an
// explicit p2pEnabled:true turns it on. New JSON always writes the setting.
func (c *RemoteStorageConfig) UnmarshalJSON(data []byte) error {
	type configJSON RemoteStorageConfig
	var decoded configJSON
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	// P2PEnabled has no shim: a missing field keeps the Go zero value (false),
	// matching the off-by-default beta behavior. An explicit p2pEnabled value
	// (true or false) is honored as written by json.Unmarshal above.
	if _, present := fields["p2pChunkSizeMb"]; !present {
		if _, present = fields["p2p_chunk_size_mb"]; !present {
			decoded.P2PChunkSizeMB = defaultP2PChunkSizeMB
		}
	}
	*c = RemoteStorageConfig(decoded)
	return nil
}

type BucketSettings struct {
	ReadOnly          bool   `json:"readOnly" toml:"read_only"`
	TrashEnabled      *bool  `json:"trashEnabled,omitempty" toml:"trash_enabled,omitempty"`
	TrashDirectory    string `json:"trashDirectory" toml:"trash_directory"`
	CustomQuotaBytes  int64  `json:"customQuotaBytes,omitempty" toml:"custom_quota_bytes,omitempty"`
	WinFspVolumeLabel string `json:"winFspVolumeLabel,omitempty" toml:"winfsp_volume_label,omitempty"`
}

// BucketViewSettings maps a visible provider bucket to its local label/root.
// An empty RemoteStorageConfig.BucketViews map means dynamic visibility of all buckets.
type BucketViewSettings struct {
	DisplayName string `json:"displayName" toml:"display_name"`
	RootPrefix  string `json:"rootPrefix" toml:"root_prefix"`
}

const (
	StorageTypeS3                      = "s3"
	StorageTypeWebDAV                  = "webdav"
	StorageTypeBaiduPan                = "baidu_pan"
	StorageTypeFTP                     = "ftp"
	StorageTypeSFTP                    = "sftp"
	JWanFSGatewayModeAuto              = "auto"
	JWanFSGatewayModeForceOn           = "jwanfs"
	JWanFSGatewayModeForceOff          = "generic_s3"
	WindowsMountModeCloudFilesCached   = "cloud_files_cached"
	WindowsMountModeCloudFilesDirect   = "cloud_files_direct"
	WindowsMountModeWebDAV             = "webdav"
	WindowsMountEngineCloudFiles       = "cloud_files"
	WindowsMountEngineWinFsp           = "winfsp"
	defaultWindowsWinFspCapacityGB     = 1024
	maxWindowsWinFspCapacityGB         = 8 * 1024 * 1024
	defaultWritebackQuietSeconds       = 10
	maxWritebackQuietSeconds           = 300
	defaultTrashRetentionDays          = 30
	defaultMountMetadataCacheSeconds   = 60
	maxMountMetadataCacheSeconds       = 3600
	defaultMountRemotePollSeconds      = 5
	maxMountRemotePollSeconds          = 300
	defaultWindowsWritebackConcurrency = 4
	maxWindowsWritebackConcurrency     = 32
	maxCacheMaxSizeMB                  = 8 * 1024 * 1024 // 8 TiB upper bound keeps the field sane while still allowing large tiers
	maxCacheMaxAgeDays                 = 3650

	defaultP2PChunkSizeMB = 4
	maxP2PChunkSizeMB     = 64
	minP2PChunkSizeMB     = 1

	ProxyModeSystem  = "system"  // follow system environment variables (HTTP_PROXY etc.)
	ProxyModeDirect  = "direct"  // no proxy, ignore all environment variables
	ProxyModeCustom  = "custom"  // use the user-supplied proxy settings
	ProxyModeInherit = "inherit" // defer to the global / default proxy config

	ProxyTypeHTTP   = "http"
	ProxyTypeSocks5 = "socks5"
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
		BucketViews:                 map[string]BucketViewSettings{},
		WritebackQuietSeconds:       defaultWritebackQuietSeconds,
		MountMetadataCacheSeconds:   defaultMountMetadataCacheSeconds,
		MountRemotePollSeconds:      defaultMountRemotePollSeconds,
		UsePathStyle:                true,
		WindowsMountMode:            WindowsMountModeCloudFilesCached,
		WindowsMountEngine:          WindowsMountEngineCloudFiles,
		WindowsWinFspCapacityGB:     defaultWindowsWinFspCapacityGB,
		WindowsThisPcEntryEnabled:   false,
		WindowsWritebackConcurrency: defaultWindowsWritebackConcurrency,
		CacheAutoCleanupEnabled:     false,
		CacheMaxSizeMB:              0,
		CacheMaxAgeDays:             0,
		JWanFSGatewayMode:           JWanFSGatewayModeAuto,
		ProxyMode:                   ProxyModeInherit,
		ProxyType:                   ProxyTypeHTTP,
		P2PEnabled:                  false,
		P2PChunkSizeMB:              defaultP2PChunkSizeMB,
	}
}
func (c RemoteStorageConfig) Normalized() RemoteStorageConfig {
	return RemoteStorageConfig{
		Endpoint:                    strings.TrimSpace(c.Endpoint),
		StorageType:                 normalizeStorageType(c.StorageType),
		ProviderType:                normalizeProviderType(c.ProviderType, c.Endpoint, c.StorageType),
		DisplayName:                 strings.TrimSpace(c.DisplayName),
		ProfileID:                   strings.TrimSpace(c.ProfileID),
		MappedBucketName:            normalizeMappedBucketName(c.StorageType, c.MappedBucketName, c.DisplayName),
		Region:                      strings.TrimSpace(c.Region),
		Bucket:                      strings.TrimSpace(c.Bucket),
		AccessKeyID:                 strings.TrimSpace(c.AccessKeyID),
		SecretAccessKey:             strings.TrimSpace(c.SecretAccessKey),
		HasSecretAccessKey:          strings.TrimSpace(c.SecretAccessKey) != "" || c.HasSecretAccessKey,
		WebDAVUsername:              strings.TrimSpace(c.WebDAVUsername),
		WebDAVPassword:              strings.TrimSpace(c.WebDAVPassword),
		HasWebDAVPassword:           strings.TrimSpace(c.WebDAVPassword) != "" || c.HasWebDAVPassword,
		FTPUsername:                 strings.TrimSpace(c.FTPUsername),
		FTPPassword:                 strings.TrimSpace(c.FTPPassword),
		HasFTPPassword:              strings.TrimSpace(c.FTPPassword) != "" || c.HasFTPPassword,
		FTPPort:                     normalizeFTPPort(c.FTPPort),
		FTPAnonymous:                c.FTPAnonymous,
		RootPrefix:                  strings.Trim(strings.TrimSpace(c.RootPrefix), "/"),
		DefaultDownloadDirectory:    strings.TrimSpace(c.DefaultDownloadDirectory),
		CacheDirectory:              strings.TrimSpace(c.CacheDirectory),
		ResolvedCacheDirectory:      strings.TrimSpace(c.ResolvedCacheDirectory),
		HideDotFiles:                c.HideDotFiles,
		FileOpenMode:                normalizeFileOpenMode(c.FileOpenMode),
		TrashDirectoryName:          normalizeTrashDirectoryName(c.TrashDirectoryName),
		TrashRetentionDays:          normalizeTrashRetentionDays(c.TrashRetentionDays),
		BucketSettings:              normalizeBucketSettings(c.BucketSettings),
		BucketViews:                 normalizeBucketViews(c.BucketViews),
		WritebackQuietSeconds:       normalizeWritebackQuietSeconds(c.WritebackQuietSeconds),
		MountMetadataCacheSeconds:   normalizeMountMetadataCacheSeconds(c.MountMetadataCacheSeconds),
		MountRemotePollSeconds:      normalizeMountRemotePollSeconds(c.MountRemotePollSeconds),
		UsePathStyle:                c.UsePathStyle,
		WindowsMountMode:            normalizeWindowsMountMode(c.WindowsMountMode),
		WindowsMountEngine:          normalizeWindowsMountEngine(c.WindowsMountEngine),
		WindowsWinFspCapacityGB:     normalizeWindowsWinFspCapacityGB(c.WindowsWinFspCapacityGB),
		WindowsThisPcEntryEnabled:   c.WindowsThisPcEntryEnabled,
		WindowsWritebackConcurrency: normalizeWindowsWritebackConcurrency(c.WindowsWritebackConcurrency),
		CacheAutoCleanupEnabled:     c.CacheAutoCleanupEnabled,
		CacheMaxSizeMB:              normalizeCacheMaxSizeMB(c.CacheMaxSizeMB),
		CacheMaxAgeDays:             normalizeCacheMaxAgeDays(c.CacheMaxAgeDays),
		JWanFSGatewayMode:           normalizeJWanFSGatewayMode(c.JWanFSGatewayMode),
		ProxyMode:                   normalizeProxyMode(c.ProxyMode),
		ProxyType:                   normalizeProxyType(c.ProxyType),
		ProxyHost:                   strings.TrimSpace(c.ProxyHost),
		ProxyPort:                   strings.TrimSpace(c.ProxyPort),
		ProxyUsername:               strings.TrimSpace(c.ProxyUsername),
		ProxyPassword:               c.ProxyPassword,
		P2PEnabled:                  c.P2PEnabled,
		P2PChunkSizeMB:              normalizeP2PChunkSizeMB(c.P2PChunkSizeMB),
		Disabled:                    c.Disabled,
	}
}

// normalizeFTPPort returns 0 (meaning "use default 21/22") for invalid or unset values.
func normalizeFTPPort(port int) int {
	if port < 0 || port > 65535 {
		return 0
	}
	return port
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
	case StorageTypeFTP:
		return StorageTypeFTP
	case StorageTypeSFTP:
		return StorageTypeSFTP
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
	if normalizeStorageType(storageType) == StorageTypeFTP {
		return "FTP"
	}
	if normalizeStorageType(storageType) == StorageTypeSFTP {
		return "SFTP"
	}
	return "WebDAV"
}

func normalizeProviderType(value, endpoint, storageType string) string {
	if normalizeStorageType(storageType) == StorageTypeBaiduPan {
		return StorageTypeBaiduPan
	}
	if normalizeStorageType(storageType) == StorageTypeFTP {
		return StorageTypeFTP
	}
	if normalizeStorageType(storageType) == StorageTypeSFTP {
		return StorageTypeSFTP
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

func normalizeMountRemotePollSeconds(value int) int {
	switch {
	case value <= 0:
		return defaultMountRemotePollSeconds
	case value > maxMountRemotePollSeconds:
		return maxMountRemotePollSeconds
	default:
		return value
	}
}

// normalizeP2PChunkSizeMB clamps the chunk size to a safe range. Values outside
// [1, 64] are replaced by the default (4 MB), which is a good balance between
// throughput and memory on typical gigabit LANs.
func normalizeP2PChunkSizeMB(value int) int {
	switch {
	case value < minP2PChunkSizeMB || value > maxP2PChunkSizeMB:
		return defaultP2PChunkSizeMB
	default:
		return value
	}
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

func normalizeWindowsMountEngine(value string) string {
	if strings.EqualFold(strings.TrimSpace(value), WindowsMountEngineWinFsp) {
		return WindowsMountEngineWinFsp
	}
	return WindowsMountEngineCloudFiles
}

func normalizeWindowsWinFspCapacityGB(value int) int {
	switch {
	case value <= 0:
		return defaultWindowsWinFspCapacityGB
	case value > maxWindowsWinFspCapacityGB:
		return maxWindowsWinFspCapacityGB
	default:
		return value
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

// normalizeCacheMaxSizeMB clamps the configured cache size cap. 0 means unlimited.
func normalizeCacheMaxSizeMB(value int) int {
	switch {
	case value < 0:
		return 0
	case value > maxCacheMaxSizeMB:
		return maxCacheMaxSizeMB
	default:
		return value
	}
}

// normalizeCacheMaxAgeDays clamps the configured cache retention window. 0 means unlimited.
func normalizeCacheMaxAgeDays(value int) int {
	switch {
	case value < 0:
		return 0
	case value > maxCacheMaxAgeDays:
		return maxCacheMaxAgeDays
	default:
		return value
	}
}

// normalizeProxyMode validates the proxy mode field, defaulting to system.
func normalizeProxyMode(mode string) string {
	switch strings.TrimSpace(mode) {
	case ProxyModeSystem, ProxyModeDirect, ProxyModeCustom, ProxyModeInherit:
		return strings.TrimSpace(mode)
	default:
		return ProxyModeSystem
	}
}

func normalizeProxyType(t string) string {
	switch strings.TrimSpace(t) {
	case ProxyTypeHTTP, ProxyTypeSocks5:
		return strings.TrimSpace(t)
	default:
		return ProxyTypeHTTP
	}
}

// normalizeJWanFSGatewayMode validates the JWanFS detection mode, defaulting
// to "auto" for unrecognized values (including empty).
func normalizeJWanFSGatewayMode(mode string) string {
	switch strings.TrimSpace(mode) {
	case JWanFSGatewayModeAuto, JWanFSGatewayModeForceOn, JWanFSGatewayModeForceOff:
		return strings.TrimSpace(mode)
	default:
		return JWanFSGatewayModeAuto
	}
}
