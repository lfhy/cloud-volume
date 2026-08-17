// Remote storage config models keep backend JSON shape away from page widgets.
import 'bucket_settings.dart';
import 'bucket_view_settings.dart';
import 'remote_storage_config_enums.dart';

export 'bucket_settings.dart';
export 'bucket_view_settings.dart';
export 'remote_storage_config_enums.dart';

part 'remote_storage_config_copy.dart';

bool? _boolFromDynamic(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return null;
}

int? _intFromDynamic(Object? value) {
  if (value is int) return value;
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

class RemoteStorageConfig {
  const RemoteStorageConfig({
    required this.endpoint,
    required this.storageType,
    required this.providerType,
    required this.displayName,
    this.profileId = '',
    required this.mappedBucketName,
    required this.region,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.hasSecretAccessKey,
    required this.webdavUsername,
    required this.webdavPassword,
    required this.hasWebdavPassword,
    required this.ftpUsername,
    required this.ftpPassword,
    required this.hasFtpPassword,
    this.ftpPort = 0,
    this.ftpAnonymous = false,
    required this.rootPrefix,
    required this.defaultDownloadDirectory,
    required this.cacheDirectory,
    required this.resolvedCacheDirectory,
    required this.hideDotFiles,
    required this.fileOpenMode,
    required this.trashDirectoryName,
    required this.trashRetentionDays,
    required this.bucketSettings,
    required this.bucketViews,
    required this.writebackQuietSeconds,
    required this.mountMetadataCacheSeconds,
    this.mountRemotePollSeconds = 5,
    required this.usePathStyle,
    required this.windowsMountMode,
    this.windowsMountEngine = WindowsMountEngine.cloudFiles,
    this.windowsWinFspCapacityGb = 1024,
    required this.windowsThisPcEntryEnabled,
    required this.windowsWritebackConcurrency,
    required this.cacheAutoCleanupEnabled,
    required this.cacheMaxSizeMb,
    required this.cacheMaxAgeDays,
    required this.jwanfsGatewayMode,
    required this.proxyMode,
    required this.proxyType,
    required this.proxyHost,
    required this.proxyPort,
    required this.proxyUsername,
    required this.proxyPassword,
    this.p2pEnabled = false,
    this.p2pChunkSizeMb = 4,
    this.disabled = false,
  });

  factory RemoteStorageConfig.empty() {
    return const RemoteStorageConfig(
      endpoint: '',
      storageType: StorageType.s3,
      providerType: StorageProviderType.s3,
      displayName: '',
      profileId: '',
      mappedBucketName: '',
      region: '',
      bucket: '',
      accessKeyId: '',
      secretAccessKey: '',
      hasSecretAccessKey: false,
      webdavUsername: '',
      webdavPassword: '',
      hasWebdavPassword: false,
      ftpUsername: '',
      ftpPassword: '',
      hasFtpPassword: false,
      ftpPort: 0,
      ftpAnonymous: false,
      rootPrefix: '',
      defaultDownloadDirectory: '',
      cacheDirectory: '',
      resolvedCacheDirectory: '',
      hideDotFiles: true,
      fileOpenMode: FileOpenMode.singleClick,
      trashDirectoryName: '.trash',
      trashRetentionDays: -1,
      bucketSettings: <String, BucketSettings>{},
      bucketViews: <String, BucketViewSettings>{},
      writebackQuietSeconds: 10,
      mountMetadataCacheSeconds: 60,
      mountRemotePollSeconds: 5,
      usePathStyle: true,
      windowsMountMode: WindowsMountMode.cloudFilesCached,
      windowsMountEngine: WindowsMountEngine.cloudFiles,
      windowsWinFspCapacityGb: 1024,
      windowsThisPcEntryEnabled: false,
      windowsWritebackConcurrency: 4,
      cacheAutoCleanupEnabled: false,
      cacheMaxSizeMb: 0,
      cacheMaxAgeDays: 0,
      jwanfsGatewayMode: JWanFSGatewayMode.auto,
      proxyMode: 'inherit',
      proxyType: 'http',
      proxyHost: '',
      proxyPort: '',
      proxyUsername: '',
      proxyPassword: '',
      p2pEnabled: false,
      p2pChunkSizeMb: 4,
      disabled: false,
    );
  }

  factory RemoteStorageConfig.fromJson(Map<String, dynamic> json) {
    final secretAccessKey =
        (json['secretAccessKey'] ?? json['secret_access_key'] ?? '').toString();
    final webdavPassword =
        (json['webdavPassword'] ?? json['webdav_password'] ?? '').toString();
    final ftpPassword = (json['ftpPassword'] ?? json['ftp_password'] ?? '')
        .toString();
    final trashRetentionDays =
        _intFromDynamic(
          json['trashRetentionDays'] ?? json['trash_retention_days'],
        ) ??
        30;
    final mountMetadataCacheSeconds =
        _intFromDynamic(
          json['mountMetadataCacheSeconds'] ??
              json['mount_metadata_cache_seconds'],
        ) ??
        60;
    final mountRemotePollSeconds =
        _intFromDynamic(
          json['mountRemotePollSeconds'] ?? json['mount_remote_poll_seconds'],
        ) ??
        5;
    return RemoteStorageConfig(
      endpoint: (json['endpoint'] ?? '').toString(),
      storageType: StorageType.fromStorage(
        json['storageType'] ?? json['storage_type'],
      ),
      providerType: StorageProviderType.fromStorage(
        json['providerType'] ?? json['provider_type'],
      ),
      displayName: (json['displayName'] ?? json['display_name'] ?? '')
          .toString(),
      profileId: (json['profileId'] ?? json['profile_id'] ?? '').toString(),
      mappedBucketName:
          (json['mappedBucketName'] ?? json['mapped_bucket_name'] ?? '')
              .toString(),
      region: (json['region'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      accessKeyId: (json['accessKeyId'] ?? json['access_key_id'] ?? '')
          .toString(),
      secretAccessKey: secretAccessKey,
      hasSecretAccessKey:
          _boolFromDynamic(
            json['hasSecretAccessKey'] ?? json['has_secret_access_key'],
          ) ??
          secretAccessKey.trim().isNotEmpty,
      webdavUsername: (json['webdavUsername'] ?? json['webdav_username'] ?? '')
          .toString(),
      webdavPassword: webdavPassword,
      hasWebdavPassword:
          _boolFromDynamic(
            json['hasWebdavPassword'] ?? json['has_webdav_password'],
          ) ??
          webdavPassword.isNotEmpty,
      ftpUsername: (json['ftpUsername'] ?? json['ftp_username'] ?? '')
          .toString(),
      ftpPassword: ftpPassword,
      hasFtpPassword:
          _boolFromDynamic(
            json['hasFtpPassword'] ?? json['has_ftp_password'],
          ) ??
          ftpPassword.isNotEmpty,
      ftpPort: _intFromDynamic(json['ftpPort'] ?? json['ftp_port']) ?? 0,
      ftpAnonymous:
          _boolFromDynamic(json['ftpAnonymous'] ?? json['ftp_anonymous']) ??
          false,
      rootPrefix: (json['rootPrefix'] ?? json['root_prefix'] ?? '').toString(),
      defaultDownloadDirectory:
          (json['defaultDownloadDirectory'] ??
                  json['default_download_directory'] ??
                  '')
              .toString(),
      cacheDirectory: (json['cacheDirectory'] ?? json['cache_directory'] ?? '')
          .toString(),
      resolvedCacheDirectory:
          (json['resolvedCacheDirectory'] ??
                  json['resolved_cache_directory'] ??
                  json['cacheDirectory'] ??
                  json['cache_directory'] ??
                  '')
              .toString(),
      hideDotFiles:
          _boolFromDynamic(json['hideDotFiles'] ?? json['hide_dot_files']) ??
          true,
      fileOpenMode: FileOpenMode.fromStorage(
        json['fileOpenMode'] ?? json['file_open_mode'],
      ),
      trashDirectoryName:
          (json['trashDirectoryName'] ??
                  json['trash_directory_name'] ??
                  '.trash')
              .toString(),
      trashRetentionDays: trashRetentionDays == 0 ? 30 : trashRetentionDays,
      bucketSettings: bucketSettingsMapFromJson(
        json['bucketSettings'] ?? json['bucket_settings'],
      ),
      bucketViews: bucketViewsMapFromJson(
        json['bucketViews'] ?? json['bucket_views'],
      ),
      writebackQuietSeconds:
          _intFromDynamic(
            json['writebackQuietSeconds'] ?? json['writeback_quiet_seconds'],
          ) ??
          10,
      mountMetadataCacheSeconds: mountMetadataCacheSeconds == 0
          ? 60
          : mountMetadataCacheSeconds,
      mountRemotePollSeconds: mountRemotePollSeconds <= 0
          ? 5
          : mountRemotePollSeconds,
      usePathStyle:
          _boolFromDynamic(json['usePathStyle'] ?? json['use_path_style']) ??
          true,
      windowsMountMode: WindowsMountMode.fromStorage(
        json['windowsMountMode'] ?? json['windows_mount_mode'],
      ),
      windowsMountEngine: WindowsMountEngine.fromStorage(
        json['windowsMountEngine'] ?? json['windows_mount_engine'],
      ),
      windowsWinFspCapacityGb:
          _intFromDynamic(
            json['windowsWinFspCapacityGb'] ??
                json['windows_winfsp_capacity_gb'],
          ) ??
          1024,
      windowsThisPcEntryEnabled:
          _boolFromDynamic(
            json['windowsThisPcEntryEnabled'] ??
                json['windows_this_pc_entry_enabled'],
          ) ??
          true,
      windowsWritebackConcurrency:
          _intFromDynamic(
            json['windowsWritebackConcurrency'] ??
                json['windows_writeback_concurrency'],
          ) ??
          4,
      cacheAutoCleanupEnabled:
          _boolFromDynamic(
            json['cacheAutoCleanupEnabled'] ??
                json['cache_auto_cleanup_enabled'],
          ) ??
          false,
      cacheMaxSizeMb:
          _intFromDynamic(
            json['cacheMaxSizeMb'] ?? json['cache_max_size_mb'],
          ) ??
          0,
      cacheMaxAgeDays:
          _intFromDynamic(
            json['cacheMaxAgeDays'] ?? json['cache_max_age_days'],
          ) ??
          0,
      jwanfsGatewayMode: JWanFSGatewayMode.fromStorage(
        json['jwanfsGatewayMode'] ?? json['jwanfs_gateway_mode'],
      ),
      proxyMode: (json['proxyMode'] ?? json['proxy_mode'] ?? 'inherit')
          .toString(),
      proxyType: (json['proxyType'] ?? json['proxy_type'] ?? 'http').toString(),
      proxyHost: (json['proxyHost'] ?? json['proxy_host'] ?? '').toString(),
      proxyPort: (json['proxyPort'] ?? json['proxy_port'] ?? '').toString(),
      proxyUsername: (json['proxyUsername'] ?? json['proxy_username'] ?? '')
          .toString(),
      proxyPassword: (json['proxyPassword'] ?? json['proxy_password'] ?? '')
          .toString(),
      p2pEnabled:
          _boolFromDynamic(json['p2pEnabled'] ?? json['p2p_enabled']) ?? false,
      p2pChunkSizeMb:
          _intFromDynamic(
            json['p2pChunkSizeMb'] ?? json['p2p_chunk_size_mb'],
          ) ??
          4,
      disabled: _boolFromDynamic(json['disabled']) ?? false,
    );
  }

  final String endpoint;
  final StorageType storageType;
  final StorageProviderType providerType;
  final String displayName;
  final String profileId;
  final String mappedBucketName;
  final String region;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
  final bool hasSecretAccessKey;
  final String webdavUsername;
  final String webdavPassword;
  final bool hasWebdavPassword;
  final String ftpUsername;
  final String ftpPassword;
  final bool hasFtpPassword;
  final int ftpPort;
  final bool ftpAnonymous;
  final String rootPrefix;
  final String defaultDownloadDirectory;
  final String cacheDirectory;
  final String resolvedCacheDirectory;
  final bool hideDotFiles;
  final FileOpenMode fileOpenMode;
  final String trashDirectoryName;
  final int trashRetentionDays;
  final Map<String, BucketSettings> bucketSettings;
  final Map<String, BucketViewSettings> bucketViews;
  final int writebackQuietSeconds;
  final int mountMetadataCacheSeconds;
  final int mountRemotePollSeconds;
  final bool usePathStyle;
  final WindowsMountMode windowsMountMode;
  final WindowsMountEngine windowsMountEngine;
  final int windowsWinFspCapacityGb;
  final bool windowsThisPcEntryEnabled;
  final int windowsWritebackConcurrency;
  final bool cacheAutoCleanupEnabled;
  final int cacheMaxSizeMb;
  final int cacheMaxAgeDays;
  final JWanFSGatewayMode jwanfsGatewayMode;
  final String proxyMode;
  final String proxyType;
  final String proxyHost;
  final String proxyPort;
  final String proxyUsername;
  final String proxyPassword;

  final bool p2pEnabled;
  final int p2pChunkSizeMb;
  final bool disabled;

  // Bucket and rootPrefix are optional; only endpoint + auth are required.
  bool get isConfigured {
    if (storageType == StorageType.baiduPan) {
      return endpoint.trim().isNotEmpty &&
          accessKeyId.trim().isNotEmpty &&
          (secretAccessKey.trim().isNotEmpty || hasSecretAccessKey);
    }
    if (storageType == StorageType.webdav) {
      return endpoint.trim().isNotEmpty &&
          webdavUsername.trim().isNotEmpty &&
          (webdavPassword.isNotEmpty || hasWebdavPassword);
    }
    if (storageType == StorageType.ftp || storageType == StorageType.sftp) {
      if (ftpAnonymous) return endpoint.trim().isNotEmpty;
      return endpoint.trim().isNotEmpty &&
          ftpUsername.trim().isNotEmpty &&
          (ftpPassword.isNotEmpty || hasFtpPassword);
    }
    return endpoint.trim().isNotEmpty &&
        accessKeyId.trim().isNotEmpty &&
        (secretAccessKey.trim().isNotEmpty || hasSecretAccessKey);
  }

  bool get hasWebDavCredentials {
    return webdavUsername.trim().isNotEmpty &&
        (webdavPassword.isNotEmpty || hasWebdavPassword);
  }

  bool get trashAutoCleanupEnabled => trashRetentionDays > 0;

  int get effectiveTrashRetentionDays =>
      trashRetentionDays > 0 ? trashRetentionDays : 30;

  bool get mountMetadataCacheEnabled => mountMetadataCacheSeconds > 0;

  int get effectiveMountMetadataCacheSeconds =>
      mountMetadataCacheSeconds > 0 ? mountMetadataCacheSeconds : 60;

  int get effectiveMountRemotePollSeconds =>
      mountRemotePollSeconds > 0 ? mountRemotePollSeconds : 5;

  int get effectiveP2PChunkSizeMb => p2pChunkSizeMb > 0 ? p2pChunkSizeMb : 4;

  bool get supportsMounts => true;

  bool get supportsShareLinks => storageType == StorageType.s3;

  BucketSettings bucketSettingsFor(String bucket) {
    final bucketName = bucket.trim();
    final defaultTrashEnabled = storageType == StorageType.s3;
    final resolved = bucketSettings[bucketName];
    return BucketSettings(
      readOnly: resolved?.readOnly ?? false,
      trashEnabled: resolved?.trashEnabled ?? defaultTrashEnabled,
      trashDirectory: resolved == null || resolved.trashDirectory.trim().isEmpty
          ? normalizeTrashDirectoryValue(trashDirectoryName)
          : normalizeTrashDirectoryValue(resolved.trashDirectory),
      customQuotaBytes: resolved?.customQuotaBytes ?? 0,
      winFspVolumeLabel: resolved?.winFspVolumeLabel ?? '',
    );
  }

  bool bucketTrashEnabled(String bucket) =>
      bucketSettingsFor(bucket).isTrashEnabled;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'endpoint': endpoint.trim(),
      'storageType': storageType.storageValue,
      'providerType': providerType.storageValue,
      'displayName': displayName.trim(),
      if (profileId.trim().isNotEmpty) 'profileId': profileId.trim(),
      'mappedBucketName': mappedBucketName.trim(),
      'region': region.trim(),
      'bucket': bucket.trim(),
      'accessKeyId': accessKeyId.trim(),
      'secretAccessKey': secretAccessKey.trim(),
      'hasSecretAccessKey': hasSecretAccessKey || secretAccessKey.isNotEmpty,
      'webdavUsername': webdavUsername.trim(),
      'webdavPassword': webdavPassword,
      'hasWebdavPassword': hasWebdavPassword || webdavPassword.isNotEmpty,
      'ftpUsername': ftpUsername.trim(),
      'ftpPassword': ftpPassword,
      'hasFtpPassword': hasFtpPassword || ftpPassword.isNotEmpty,
      'ftpPort': ftpPort,
      'ftpAnonymous': ftpAnonymous,
      'rootPrefix': rootPrefix.trim(),
      'defaultDownloadDirectory': defaultDownloadDirectory.trim(),
      'cacheDirectory': cacheDirectory.trim(),
      'hideDotFiles': hideDotFiles,
      'fileOpenMode': fileOpenMode.storageValue,
      'trashDirectoryName': trashDirectoryName.trim(),
      'trashRetentionDays': trashRetentionDays,
      'bucketSettings': bucketSettings.map(
        (key, value) => MapEntry(key.trim(), value.toJson()),
      ),
      'bucketViews': bucketViews.map(
        (key, value) => MapEntry(key.trim(), value.toJson()),
      ),
      'writebackQuietSeconds': writebackQuietSeconds,
      'mountMetadataCacheSeconds': mountMetadataCacheSeconds,
      'mountRemotePollSeconds': mountRemotePollSeconds,
      'usePathStyle': usePathStyle,
      'windowsMountMode': windowsMountMode.storageValue,
      'windowsMountEngine': windowsMountEngine.storageValue,
      'windowsWinFspCapacityGb': windowsWinFspCapacityGb,
      'windowsThisPcEntryEnabled': windowsThisPcEntryEnabled,
      'windowsWritebackConcurrency': windowsWritebackConcurrency,
      'cacheAutoCleanupEnabled': cacheAutoCleanupEnabled,
      'cacheMaxSizeMb': cacheMaxSizeMb,
      'cacheMaxAgeDays': cacheMaxAgeDays,
      'jwanfsGatewayMode': jwanfsGatewayMode.storageValue,
      'proxyMode': proxyMode,
      'proxyType': proxyType,
      'proxyHost': proxyHost,
      'proxyPort': proxyPort,
      'proxyUsername': proxyUsername,
      'proxyPassword': proxyPassword,
      'p2pEnabled': p2pEnabled,
      'p2pChunkSizeMb': p2pChunkSizeMb,
      if (disabled) 'disabled': disabled,
    };
  }
}
