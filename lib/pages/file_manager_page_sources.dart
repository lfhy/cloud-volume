part of 'file_manager_page.dart';

// 文件管理页来源聚合：把多个账号的 bucket 列表合并成统一首页。

extension _FileManagerPageSources on _FileManagerPageState {
  Future<List<FileManagerBucketEntry>> _loadBucketEntries() async {
    final sources = await _loadBucketSources();
    final entries = <FileManagerBucketEntry>[];
    for (final source in sources) {
      final buckets = await widget.api.listBuckets(source.config);
      for (final bucket in buckets) {
        entries.add(
          FileManagerBucketEntry.fromBucketInfo(
            bucket: bucket,
            profileName: source.profileName,
            sourceLabel: source.sourceLabel,
            config: source.config,
          ),
        );
      }
    }
    entries.sort((left, right) {
      final sourceCompare = left.sourceLabel.compareTo(right.sourceLabel);
      if (sourceCompare != 0) {
        return sourceCompare;
      }
      return left.bucket.name.compareTo(right.bucket.name);
    });
    return entries;
  }

  Future<List<_BucketSourceConfig>> _loadBucketSources() async {
    if (widget.profiles.isEmpty) {
      return <_BucketSourceConfig>[
        _BucketSourceConfig(
          profileName: 'default',
          sourceLabel: _sourceLabelForConfig(widget.config),
          config: widget.config,
        ),
      ];
    }
    return Future.wait(
      widget.profiles.map((profile) async {
        final config = await widget.api.loadProfile(profile.name);
        return _BucketSourceConfig(
          profileName: profile.name,
          sourceLabel: _sourceLabelForConfig(config),
          config: config,
        );
      }),
    );
  }

  String _sourceLabelForConfig(RemoteStorageConfig config) {
    final name = config.displayName.trim().isNotEmpty
        ? config.displayName.trim()
        : config.storageType == StorageType.baiduPan
        ? '百度网盘'
        : config.storageType == StorageType.webdav
        ? config.webdavUsername.trim()
        : config.accessKeyId.trim();
    final label = name.isEmpty ? '账号' : name;
    return '$label · ${config.storageType.label}';
  }
}

class _BucketSourceConfig {
  const _BucketSourceConfig({
    required this.profileName,
    required this.sourceLabel,
    required this.config,
  });

  final String profileName;
  final String sourceLabel;
  final RemoteStorageConfig config;
}
