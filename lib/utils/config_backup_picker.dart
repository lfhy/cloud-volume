// Builds backup-only directory-picker rows without changing provider bucket identities.

import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';

const configBackupStorageDisplayName = '备份存储';

const _singleRootBackupStorageTypes = <StorageType>{
  StorageType.webdav,
  StorageType.baiduPan,
  StorageType.ftp,
  StorageType.sftp,
};

/// Whether this provider exposes one synthetic root rather than real buckets.
bool isConfigBackupSingleRootStorage(StorageType storageType) =>
    _singleRootBackupStorageTypes.contains(storageType);

/// Returns the backup-only presentation label without changing [bucket].
String configBackupBucketDisplayName({
  required StorageType storageType,
  required String bucket,
}) => isConfigBackupSingleRootStorage(storageType)
    ? configBackupStorageDisplayName
    : bucket.trim();

/// Presentation model for choosing a standalone configuration-backup target.
class ConfigBackupPickerModel {
  const ConfigBackupPickerModel({
    required this.entries,
    required this.initialEntry,
  });

  final List<FileManagerBucketEntry> entries;

  /// Single-root providers can enter their only synthetic bucket immediately.
  final FileManagerBucketEntry? initialEntry;
}

/// Gives single-root providers a backup-specific alias while preserving their
/// original [BucketInfo.name] for bridge calls and persisted targets.
ConfigBackupPickerModel buildConfigBackupPickerModel({
  required RemoteStorageConfig config,
  required List<BucketInfo> buckets,
  required String profileName,
}) {
  final singleSyntheticBucket =
      isConfigBackupSingleRootStorage(config.storageType) &&
      buckets.length == 1;
  final sourceLabel = singleSyntheticBucket
      ? config.storageType.label
      : config.displayName.trim().isEmpty
      ? config.storageType.label
      : config.displayName;
  final entries = buckets
      .map(
        (bucket) => FileManagerBucketEntry.fromBucketInfo(
          bucket: bucket,
          profileName: profileName,
          sourceLabel: sourceLabel,
          config: config,
          view: singleSyntheticBucket
              ? BucketViewSettings(
                  displayName: configBackupBucketDisplayName(
                    storageType: config.storageType,
                    bucket: bucket.name,
                  ),
                )
              : null,
        ),
      )
      .toList(growable: false);
  return ConfigBackupPickerModel(
    entries: entries,
    initialEntry: singleSyntheticBucket ? entries.single : null,
  );
}
