// File manager bucket entries keep the originating account attached to each bucket row.

import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';

class FileManagerBucketEntry {
  const FileManagerBucketEntry({
    required this.id,
    required this.bucket,
    required this.profileName,
    required this.sourceLabel,
    required this.config,
  });

  factory FileManagerBucketEntry.fromBucketInfo({
    required BucketInfo bucket,
    required String profileName,
    required String sourceLabel,
    required RemoteStorageConfig config,
  }) {
    return FileManagerBucketEntry(
      id: '$profileName::${bucket.name}',
      bucket: bucket,
      profileName: profileName,
      sourceLabel: sourceLabel,
      config: config,
    );
  }

  final String id;
  final BucketInfo bucket;
  final String profileName;
  final String sourceLabel;
  final RemoteStorageConfig config;
}
