// Shared label helpers for configuration backup UI surfaces.
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/utils/transfer_format.dart';

String configBackupProfileLabel(ProfileInfo profile) {
  final name = profile.displayName.trim().isEmpty
      ? profile.name
      : profile.displayName.trim();
  return '$name · ${profile.storageType.label}';
}

String configBackupTargetStatusTitle({
  required ConfigBackupTarget target,
  required List<ProfileInfo> profiles,
}) {
  if (target.profileName.isNotEmpty) {
    for (final item in profiles) {
      if (item.name == target.profileName) {
        return configBackupProfileLabel(item);
      }
    }
    return '账号已失效';
  }
  final standalone = target.standalone;
  if (standalone == null || !standalone.isConfigured) {
    return '未配置独立存储';
  }
  final name = standalone.displayName.trim().isEmpty
      ? standalone.storageType.label
      : standalone.displayName.trim();
  return '独立存储 · $name';
}

String configBackupTargetStatusDetail({
  required ConfigBackupTarget target,
  required List<ProfileInfo> profiles,
}) {
  if (target.profileName.isNotEmpty) {
    ProfileInfo? profile;
    for (final item in profiles) {
      if (item.name == target.profileName) {
        profile = item;
        break;
      }
    }
    if (profile == null) {
      return '当前账号列表中找不到「${target.profileName}」，请重新选择备份来源。';
    }
    final endpoint = profile.endpoint.trim();
    return endpoint.isEmpty ? '使用已有账号作为备份目标。' : endpoint;
  }
  final standalone = target.standalone;
  if (standalone == null || !standalone.isConfigured) {
    return '独立连接不会出现在账号列表，适合只用于配置备份。';
  }
  final endpoint = standalone.endpoint.trim();
  return endpoint.isEmpty
      ? standalone.storageType.label
      : '${standalone.storageType.label} · $endpoint';
}

String configBackupPathPreview({
  required String bucket,
  required String prefix,
  String? displayBucket,
}) {
  final cleanBucket = bucket.trim();
  final cleanPrefix = prefix.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  if (cleanBucket.isEmpty) return '尚未填写存储路径';
  final label = displayBucket?.trim().isNotEmpty == true
      ? displayBucket!.trim()
      : cleanBucket;
  if (cleanPrefix.isEmpty) return label;
  return '$label / $cleanPrefix';
}

String configBackupHistoryTitle({
  required bool loading,
  required List<ConfigBackupSnapshot> snapshots,
}) {
  if (loading) return '正在读取远端备份…';
  if (snapshots.isEmpty) return '还没有远端备份';
  return '已有 ${snapshots.length} 份备份';
}

String configBackupHistoryDetail({
  required bool loading,
  required List<ConfigBackupSnapshot> snapshots,
}) {
  if (loading) return '稍候即可查看最新快照。';
  if (snapshots.isEmpty) return '点这里打开备份历史；建议先完成一次立即备份。';
  final latest = configBackupSnapshotPrimaryLabel(snapshots.first);
  final size = configBackupSnapshotSecondaryLabel(snapshots.first);
  // For the summary card, only show the time — the file name is noise here.
  return size.isEmpty ? '最近备份：$latest' : '最近备份：$latest · $size';
}

String configBackupSnapshotPrimaryLabel(ConfigBackupSnapshot snapshot) {
  final createdAt = DateTime.tryParse(snapshot.createdAt)?.toLocal();
  if (createdAt != null) {
    final y = createdAt.year.toString().padLeft(4, '0');
    final m = createdAt.month.toString().padLeft(2, '0');
    final d = createdAt.day.toString().padLeft(2, '0');
    final hh = createdAt.hour.toString().padLeft(2, '0');
    final mm = createdAt.minute.toString().padLeft(2, '0');
    final ss = createdAt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }
  if (snapshot.displayName.trim().isNotEmpty) {
    return snapshot.displayName.trim();
  }
  return snapshot.key;
}

String configBackupSnapshotSecondaryLabel(ConfigBackupSnapshot snapshot) {
  final parts = <String>[];
  if (snapshot.size > 0) {
    parts.add(formatBytes(snapshot.size));
  }
  return parts.join(' · ');
}

String configBackupFriendlyError(Object error) {
  final text = describeBridgeError(error).trim();
  const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length).trim();
    }
  }
  return text;
}
