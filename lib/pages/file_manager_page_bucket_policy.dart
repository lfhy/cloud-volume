part of 'file_manager_page.dart';

// 文件管理页桶策略：集中处理只读、回收站开关和桶级配置保存。

extension _FileManagerPageBucketPolicy on _FileManagerPageState {
  BucketSettings? get _activeBucketSettings {
    final bucket = _activeBucket;
    if (bucket == null) {
      return null;
    }
    return _activeConfig.bucketSettingsFor(bucket);
  }

  bool _bucketTrashEnabled(FileManagerBucketEntry bucket) {
    return bucket.config.bucketTrashEnabled(bucket.bucket.name);
  }

  bool get _activeBucketReadOnly => _activeBucketSettings?.readOnly ?? false;

  bool get _activeBucketTrashEnabled =>
      _activeBucketEntry != null && _bucketTrashEnabled(_activeBucketEntry!);

  bool get _currentBucketWritable {
    return _activeBucket != null && !_showTrash && !_activeBucketReadOnly;
  }

  Future<void> _configureBucket(FileManagerBucketEntry bucket) async {
    final updated = await showBucketSettingsDialog(
      context,
      bucket: bucket.bucket.name,
      config: bucket.config,
    );
    if (updated == null) {
      return;
    }
    try {
      await widget.api.saveProfile(bucket.profileName, updated);
      if (!mounted) {
        return;
      }
      widget.onRefresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showPageError(error);
    }
  }

  String? get _currentWriteBlockedReason {
    if (_activeBucketReadOnly) {
      return '该目录无操作权限。';
    }
    final reason = _directoryAccess?.reason.trim();
    if (reason?.isNotEmpty == true) {
      return reason;
    }
    if (_activeConfig.storageType == StorageType.webdav) {
      return '该目录无操作权限。';
    }
    return null;
  }
}
