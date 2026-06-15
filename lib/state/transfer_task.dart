part of 'transfer_queue.dart';

// Transfer task models keep queue persistence and UI state compact.

/// 传输任务状态。
enum TransferStatus { pending, running, done, failed, canceled }

enum TransferKind { upload, download, copy, move, delete }

/// 单个传输任务。
class TransferTask {
  TransferTask({
    required this.id,
    required this.kind,
    required this.bucket,
    required this.key,
    required this.localPath,
    this.targetPath = '',
    this.status = TransferStatus.pending,
    this.statusDetail = '',
    this.createdAt = '',
    this.bytesCompleted = 0,
    this.totalBytes = 0,
    this.itemsCompleted = 0,
    this.totalItems = 0,
    this.currentFileKey = '',
    this.currentFileBytesCompleted = 0,
    this.currentFileTotalBytes = 0,
    this.speedBytes = 0,
    this.error,
  });

  factory TransferTask.fromJson(Map<String, dynamic> json) {
    return TransferTask(
      id: (json['id'] ?? '').toString(),
      kind: _transferKindFromName((json['kind'] ?? '').toString()),
      bucket: (json['bucket'] ?? '').toString(),
      key: (json['key'] ?? '').toString(),
      localPath: (json['localPath'] ?? '').toString(),
      targetPath: (json['targetPath'] ?? '').toString(),
      status: _transferStatusFromName((json['status'] ?? '').toString()),
      statusDetail: (json['statusDetail'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      bytesCompleted: (json['bytesCompleted'] ?? 0) as int,
      totalBytes: (json['totalBytes'] ?? 0) as int,
      itemsCompleted: (json['itemsCompleted'] ?? 0) as int,
      totalItems: (json['totalItems'] ?? 0) as int,
      currentFileKey: (json['currentFileKey'] ?? '').toString(),
      currentFileBytesCompleted:
          (json['currentFileBytesCompleted'] ?? 0) as int,
      currentFileTotalBytes: (json['currentFileTotalBytes'] ?? 0) as int,
      speedBytes: (json['speedBytes'] ?? 0).toDouble(),
      error: json['error']?.toString(),
    );
  }

  final String id;
  final TransferKind kind;
  final String bucket;
  final String key;
  String localPath;
  String targetPath;
  TransferStatus status;
  String statusDetail;
  String createdAt;
  int bytesCompleted;
  int totalBytes;
  int itemsCompleted;
  int totalItems;
  String currentFileKey;
  int currentFileBytesCompleted;
  int currentFileTotalBytes;
  double speedBytes;
  String? error;

  String get displayName {
    final raw = targetPath.isNotEmpty && (isCopy || isMove) ? targetPath : key;
    final segments = raw.split('/').where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) {
      return raw;
    }
    return segments.last;
  }

  String get typeLabel {
    if (statusDetail == 'mount_read') {
      return '挂载读取';
    }
    return switch (kind) {
      TransferKind.upload => '上传',
      TransferKind.download => '下载',
      TransferKind.copy => '复制',
      TransferKind.move => '移动',
      TransferKind.delete => '删除',
    };
  }

  String get progressTargetLabel {
    if (statusDetail == 'mount_read' && targetPath.isNotEmpty) {
      return targetPath;
    }
    return '';
  }

  bool get isUpload => kind == TransferKind.upload;
  bool get isDownload => kind == TransferKind.download;
  bool get isCopy => kind == TransferKind.copy;
  bool get isMove => kind == TransferKind.move;
  bool get isDelete => kind == TransferKind.delete;
  bool get isMountWriteback => id.startsWith('mount-writeback-');
  bool get isDirectoryChild =>
      statusDetail == 'directory_child' || id.contains(':file:');
  bool get isRunning => status == TransferStatus.running;
  bool get isPending => status == TransferStatus.pending;
  bool get isSyncWaiting => isMountWriteback && statusDetail == 'sync_wait';
  bool get isUploadWaiting => isMountWriteback && statusDetail == 'upload_wait';
  bool get canForceSyncNow =>
      isUpload && isPending && (!isMountWriteback || isSyncWaiting);
  bool get isCancelable =>
      !isDirectoryChild &&
      (status == TransferStatus.pending || status == TransferStatus.running);
  bool get isRetryableFileTransfer =>
      status == TransferStatus.failed &&
      (isUpload || isDownload) &&
      localPath.trim().isNotEmpty &&
      totalItems == 0;
  bool get isFinished =>
      status == TransferStatus.done ||
      status == TransferStatus.failed ||
      status == TransferStatus.canceled;
  double get progress =>
      totalBytes <= 0 ? 0 : (bytesCompleted / totalBytes).clamp(0, 1);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'kind': kind.name,
      'bucket': bucket,
      'key': key,
      'localPath': localPath,
      'targetPath': targetPath,
      'status': status.name,
      'statusDetail': statusDetail,
      'createdAt': createdAt,
      'bytesCompleted': bytesCompleted,
      'totalBytes': totalBytes,
      'itemsCompleted': itemsCompleted,
      'totalItems': totalItems,
      'currentFileKey': currentFileKey,
      'currentFileBytesCompleted': currentFileBytesCompleted,
      'currentFileTotalBytes': currentFileTotalBytes,
      'speedBytes': speedBytes,
      'error': error,
    };
  }
}

TransferKind _transferKindFromName(String value) {
  return switch (value) {
    'download' => TransferKind.download,
    'copy' => TransferKind.copy,
    'move' => TransferKind.move,
    'delete' => TransferKind.delete,
    _ => TransferKind.upload,
  };
}

TransferStatus _transferStatusFromName(String value) {
  return switch (value) {
    'running' => TransferStatus.running,
    'done' => TransferStatus.done,
    'failed' => TransferStatus.failed,
    'canceled' => TransferStatus.canceled,
    _ => TransferStatus.pending,
  };
}
