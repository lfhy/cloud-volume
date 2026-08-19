// Supporting value objects keep the main gateway contract below the file limit.
part of 'remote_storage_gateway.dart';

/// Bridge build metadata used for update package selection.
class BridgeBuildInfo {
  const BridgeBuildInfo({
    this.buildArch = '',
    this.runtimeOS = '',
    this.runtimeArch = '',
  });

  factory BridgeBuildInfo.fromJson(Map<String, dynamic> json) {
    return BridgeBuildInfo(
      buildArch: (json['buildArch'] ?? '').toString(),
      runtimeOS: (json['runtimeOS'] ?? '').toString(),
      runtimeArch: (json['runtimeArch'] ?? '').toString(),
    );
  }

  final String buildArch;
  final String runtimeOS;
  final String runtimeArch;
}

/// [CacheStats] mirrors the Go-side cache directory summary used by Settings.
class CacheStats {
  const CacheStats({
    required this.path,
    required this.exists,
    required this.sizeBytes,
    required this.fileCount,
    this.protectedBytes = 0,
    this.protectedFiles = 0,
    required this.lastModified,
  });

  factory CacheStats.fromJson(Map<String, dynamic> json) {
    return CacheStats(
      path: (json['path'] ?? '').toString(),
      exists: json['exists'] == true,
      sizeBytes: (json['sizeBytes'] ?? 0) as int,
      fileCount: (json['fileCount'] ?? 0) as int,
      protectedBytes: (json['protectedBytes'] ?? 0) as int,
      protectedFiles: (json['protectedFiles'] ?? 0) as int,
      lastModified: (json['lastModified'] ?? '').toString(),
    );
  }

  final String path;
  final bool exists;
  final int sizeBytes;
  final int fileCount;
  final int protectedBytes;
  final int protectedFiles;
  final String lastModified;
}

/// [CleanCacheResult] reports how much the most recent cleanup pass reclaimed.
class CleanCacheResult {
  const CleanCacheResult({
    required this.beforeBytes,
    required this.afterBytes,
    required this.removed,
    required this.freedBytes,
    this.skippedProtected = 0,
  });

  factory CleanCacheResult.fromJson(Map<String, dynamic> json) {
    return CleanCacheResult(
      beforeBytes: (json['beforeBytes'] ?? 0) as int,
      afterBytes: (json['afterBytes'] ?? 0) as int,
      removed: (json['removed'] ?? 0) as int,
      freedBytes: (json['freedBytes'] ?? 0) as int,
      skippedProtected: (json['skippedProtected'] ?? 0) as int,
    );
  }

  final int beforeBytes;
  final int afterBytes;
  final int removed;
  final int freedBytes;
  final int skippedProtected;
}

class MountBucketOptions {
  const MountBucketOptions({
    this.mountPath = '',
    this.readOnly = false,
    this.driveLetter = '',
    this.windowsMountEngine,
  });

  final String mountPath;
  final bool readOnly;
  final String driveLetter;

  /// Optional Windows mount engine override chosen from the mount dialog.
  /// When null the backend uses the persisted config value. Non-null values
  /// are persisted by the caller before mounting.
  final WindowsMountEngine? windowsMountEngine;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mountPath': mountPath.trim(),
      'readOnly': readOnly,
      'driveLetter': driveLetter.trim().toUpperCase(),
    };
  }
}
