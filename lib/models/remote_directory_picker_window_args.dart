// Args for the remote-directory picker sub-window (JSON over multi-window boundary).

import 'dart:convert';

import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';

class RemoteDirectoryPickerWindowArgs {
  const RemoteDirectoryPickerWindowArgs({
    required this.requestId,
    required this.creatorWindowId,
    this.rootWindowId,
    required this.buckets,
    this.initialBucket,
    this.initialPrefix,
    this.initialProfileName,
    this.creatorFrameLeft,
    this.creatorFrameTop,
    this.creatorFrameWidth,
    this.creatorFrameHeight,
    this.anchorFrameLeft,
    this.anchorFrameTop,
    this.anchorFrameWidth,
    this.anchorFrameHeight,
  });

  static const String businessId = 'remote_directory_picker';

  final String requestId;
  final String creatorWindowId;

  /// Main (or outermost) window to keep visible when this child is focused.
  final String? rootWindowId;
  final List<FileManagerBucketEntry> buckets;
  final String? initialBucket;
  final String? initialPrefix;
  final String? initialProfileName;
  final double? creatorFrameLeft;
  final double? creatorFrameTop;
  final double? creatorFrameWidth;
  final double? creatorFrameHeight;

  /// Main window bounds at modal stack start; nested children center on this.
  final double? anchorFrameLeft;
  final double? anchorFrameTop;
  final double? anchorFrameWidth;
  final double? anchorFrameHeight;

  factory RemoteDirectoryPickerWindowArgs.fromArguments(String arguments) {
    final json = jsonDecode(arguments) as Map<String, dynamic>;
    final bucketMaps = json['buckets'] as List<dynamic>? ?? [];
    return RemoteDirectoryPickerWindowArgs(
      requestId: json['requestId'] as String? ?? '',
      creatorWindowId: json['creatorWindowId'] as String? ?? '',
      rootWindowId: json['rootWindowId'] as String?,
      buckets: bucketMaps
          .map((e) => _bucketEntryFromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      initialBucket: json['initialBucket'] as String?,
      initialPrefix: json['initialPrefix'] as String?,
      initialProfileName: json['initialProfileName'] as String?,
      creatorFrameLeft: (json['creatorFrameLeft'] as num?)?.toDouble(),
      creatorFrameTop: (json['creatorFrameTop'] as num?)?.toDouble(),
      creatorFrameWidth: (json['creatorFrameWidth'] as num?)?.toDouble(),
      creatorFrameHeight: (json['creatorFrameHeight'] as num?)?.toDouble(),
      anchorFrameLeft: (json['anchorFrameLeft'] as num?)?.toDouble(),
      anchorFrameTop: (json['anchorFrameTop'] as num?)?.toDouble(),
      anchorFrameWidth: (json['anchorFrameWidth'] as num?)?.toDouble(),
      anchorFrameHeight: (json['anchorFrameHeight'] as num?)?.toDouble(),
    );
  }

  String toArguments() {
    return jsonEncode(<String, dynamic>{
      'businessId': businessId,
      'requestId': requestId,
      'creatorWindowId': creatorWindowId,
      if (rootWindowId != null) 'rootWindowId': rootWindowId,
      'buckets': buckets.map(_bucketEntryToJson).toList(),
      if (initialBucket != null) 'initialBucket': initialBucket,
      if (initialPrefix != null) 'initialPrefix': initialPrefix,
      if (initialProfileName != null) 'initialProfileName': initialProfileName,
      if (creatorFrameLeft != null) 'creatorFrameLeft': creatorFrameLeft,
      if (creatorFrameTop != null) 'creatorFrameTop': creatorFrameTop,
      if (creatorFrameWidth != null) 'creatorFrameWidth': creatorFrameWidth,
      if (creatorFrameHeight != null) 'creatorFrameHeight': creatorFrameHeight,
      if (anchorFrameLeft != null) 'anchorFrameLeft': anchorFrameLeft,
      if (anchorFrameTop != null) 'anchorFrameTop': anchorFrameTop,
      if (anchorFrameWidth != null) 'anchorFrameWidth': anchorFrameWidth,
      if (anchorFrameHeight != null) 'anchorFrameHeight': anchorFrameHeight,
    });
  }

  static bool matches(String arguments) {
    if (arguments.trim().isEmpty) return false;
    try {
      final json = jsonDecode(arguments) as Map<String, dynamic>;
      return json['businessId'] == businessId;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> _bucketEntryToJson(FileManagerBucketEntry e) {
    return {
      'id': e.id,
      'profileName': e.profileName,
      'sourceLabel': e.sourceLabel,
      'displayName': e.displayName,
      'rootPrefix': e.rootPrefix,
      'bucketName': e.bucket.name,
      'config': e.config.toJson(),
    };
  }

  static FileManagerBucketEntry _bucketEntryFromJson(
    Map<String, dynamic> json,
  ) {
    final bucketMap = Map<String, dynamic>.from(json['bucket'] as Map? ?? {});
    if (bucketMap.isEmpty && json['bucketName'] != null) {
      bucketMap['name'] = json['bucketName'];
    }
    return FileManagerBucketEntry(
      id: json['id'] as String? ?? '',
      bucket: BucketInfo.fromJson(bucketMap),
      profileName: json['profileName'] as String? ?? '',
      sourceLabel: json['sourceLabel'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      rootPrefix: json['rootPrefix'] as String? ?? '',
      config: RemoteStorageConfig.fromJson(
        Map<String, dynamic>.from(json['config'] as Map? ?? {}),
      ),
    );
  }
}
