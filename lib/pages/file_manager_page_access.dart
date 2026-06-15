// ignore_for_file: invalid_use_of_protected_member

// 文件管理页目录权限：按当前 WebDAV 目录刷新可写状态并控制写入口。

part of 'file_manager_page.dart';

extension _FileManagerPageAccess on _FileManagerPageState {
  bool get _currentDirectoryWritable {
    if (!_currentBucketWritable) return false;
    if (_activeConfig.storageType != StorageType.webdav) return true;
    if (_checkingDirectoryAccess) return false;
    final access = _directoryAccess;
    if (access == null) return false;
    return !access.known || access.writable;
  }

  Future<void> _refreshDirectoryAccess(
    FileManagerBucketEntry bucket,
    String prefix,
  ) async {
    try {
      final access = await widget.api.directoryAccess(
        bucket.config,
        bucket.bucket.name,
        prefix,
      );
      if (!mounted || _activeBucketId != bucket.id || _prefix != prefix) return;
      setState(() {
        _directoryAccess = access;
        _checkingDirectoryAccess = false;
      });
    } catch (error) {
      if (!mounted || _activeBucketId != bucket.id || _prefix != prefix) return;
      setState(() {
        _directoryAccess = const DirectoryAccess(writable: true, known: false);
        _checkingDirectoryAccess = false;
      });
    }
  }

  bool _ensureCurrentDirectoryWritable() {
    if (_currentDirectoryWritable) return true;
    _showPageMessage(
      title: '上传失败',
      message: _currentWriteBlockedReason ?? '该目录无操作权限。',
    );
    return false;
  }
}
