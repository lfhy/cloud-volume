// 挂载缓存清理结果，由 Go 桥接返回。
class MountCacheCleanupResult {
  const MountCacheCleanupResult({
    required this.removedCount,
    required this.freedBytes,
  });

  factory MountCacheCleanupResult.fromJson(Map<String, dynamic> json) {
    return MountCacheCleanupResult(
      removedCount: (json['removedCount'] as int?) ?? 0,
      freedBytes: (json['freedBytes'] as int?) ?? 0,
    );
  }

  final int removedCount;
  final int freedBytes;

  String get formattedSize {
    if (freedBytes < 1024) return '$freedBytes B';
    if (freedBytes < 1024 * 1024) {
      return '${(freedBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (freedBytes < 1024 * 1024 * 1024) {
      return '${(freedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(freedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
