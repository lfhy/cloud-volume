// Unified remote-operation models shared by the task page, sidebar, and sync cards.

part 'remote_task_parsing.dart';
part 'remote_task_filter.dart';
part 'remote_task_wire.dart';

enum RemoteTaskStatus {
  waiting,
  blocked,
  running,
  verifying,
  retryWait,
  failed,
  conflict,
  done,
  cancelRequested,
  reconciling,
  canceled;

  static RemoteTaskStatus fromWire(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return switch (normalized) {
      'blocked' => RemoteTaskStatus.blocked,
      'running' => RemoteTaskStatus.running,
      'verifying' => RemoteTaskStatus.verifying,
      'retry_wait' || 'retry-wait' => RemoteTaskStatus.retryWait,
      'failed' || 'error' => RemoteTaskStatus.failed,
      'conflict' => RemoteTaskStatus.conflict,
      'done' || 'applied' || 'completed' => RemoteTaskStatus.done,
      'cancel_requested' ||
      'cancel-requested' => RemoteTaskStatus.cancelRequested,
      'reconciling' => RemoteTaskStatus.reconciling,
      'canceled' || 'cancelled' => RemoteTaskStatus.canceled,
      _ => RemoteTaskStatus.waiting,
    };
  }

  String get wireName => switch (this) {
    RemoteTaskStatus.waiting => 'waiting',
    RemoteTaskStatus.blocked => 'blocked',
    RemoteTaskStatus.running => 'running',
    RemoteTaskStatus.verifying => 'verifying',
    RemoteTaskStatus.retryWait => 'retry_wait',
    RemoteTaskStatus.failed => 'failed',
    RemoteTaskStatus.conflict => 'conflict',
    RemoteTaskStatus.done => 'done',
    RemoteTaskStatus.cancelRequested => 'cancel_requested',
    RemoteTaskStatus.reconciling => 'reconciling',
    RemoteTaskStatus.canceled => 'canceled',
  };

  bool get isActive => switch (this) {
    RemoteTaskStatus.waiting ||
    RemoteTaskStatus.blocked ||
    RemoteTaskStatus.running ||
    RemoteTaskStatus.verifying ||
    RemoteTaskStatus.retryWait ||
    RemoteTaskStatus.cancelRequested ||
    RemoteTaskStatus.reconciling => true,
    RemoteTaskStatus.failed ||
    RemoteTaskStatus.conflict ||
    RemoteTaskStatus.done ||
    RemoteTaskStatus.canceled => false,
  };
}

enum RemoteTaskSource { metadata, runtime, sync, local, appUpdate, unknown }

enum RemoteTaskKind {
  mkdir,
  write,
  upload,
  download,
  rename,
  copy,
  move,
  delete,
  appUpdate,
  unknown;

  static RemoteTaskKind fromWire(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return switch (normalized) {
      'mkdir' || 'sync_mkdir' || 'create_directory' => RemoteTaskKind.mkdir,
      'write' => RemoteTaskKind.write,
      'upload' || 'sync_upload' => RemoteTaskKind.upload,
      'download' || 'sync_download' => RemoteTaskKind.download,
      'rename' || 'sync_rename' => RemoteTaskKind.rename,
      'copy' => RemoteTaskKind.copy,
      'move' => RemoteTaskKind.move,
      'delete' || 'sync_delete' => RemoteTaskKind.delete,
      'app_update' => RemoteTaskKind.appUpdate,
      _ => RemoteTaskKind.unknown,
    };
  }

  String get wireName => switch (this) {
    RemoteTaskKind.mkdir => 'mkdir',
    RemoteTaskKind.write => 'write',
    RemoteTaskKind.upload => 'upload',
    RemoteTaskKind.download => 'download',
    RemoteTaskKind.rename => 'rename',
    RemoteTaskKind.copy => 'copy',
    RemoteTaskKind.move => 'move',
    RemoteTaskKind.delete => 'delete',
    RemoteTaskKind.appUpdate => 'app_update',
    RemoteTaskKind.unknown => 'unknown',
  };
}

enum RemoteTaskPhase {
  quietPeriod,
  dependency,
  provider,
  verification,
  cleanup,
  local,
  unknown,
}

class RemoteTaskProgress {
  const RemoteTaskProgress({
    this.bytesCompleted = 0,
    this.totalBytes = 0,
    this.itemsCompleted = 0,
    this.totalItems = 0,
    this.speedBytes = 0,
    this.currentKey = '',
    this.currentFileBytesCompleted = 0,
    this.currentFileTotalBytes = 0,
    this.currentRange = '',
    this.currentPart = 0,
    this.totalParts = 0,
  });

  factory RemoteTaskProgress.fromJson(Object? value) {
    if (value is! Map) return const RemoteTaskProgress();
    return RemoteTaskProgress(
      bytesCompleted: _int(value['bytesCompleted']),
      totalBytes: _int(value['totalBytes']),
      itemsCompleted: _int(value['itemsCompleted']),
      totalItems: _int(value['totalItems']),
      speedBytes: _double(value['speedBytes']),
      currentKey: (value['currentKey'] ?? value['currentFileKey'] ?? '')
          .toString(),
      currentFileBytesCompleted: _int(value['currentFileBytesCompleted']),
      currentFileTotalBytes: _int(value['currentFileTotalBytes']),
      currentRange: (value['currentRange'] ?? '').toString(),
      currentPart: _int(value['currentPart']),
      totalParts: _int(value['totalParts']),
    );
  }

  final int bytesCompleted;
  final int totalBytes;
  final int itemsCompleted;
  final int totalItems;
  final double speedBytes;
  final String currentKey;
  final int currentFileBytesCompleted;
  final int currentFileTotalBytes;
  final String currentRange;
  final int currentPart;
  final int totalParts;

  double get fraction {
    if (totalBytes > 0) return (bytesCompleted / totalBytes).clamp(0, 1);
    if (totalItems > 0) return (itemsCompleted / totalItems).clamp(0, 1);
    return 0;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'bytesCompleted': bytesCompleted,
    'totalBytes': totalBytes,
    'itemsCompleted': itemsCompleted,
    'totalItems': totalItems,
    'speedBytes': speedBytes,
    'currentKey': currentKey,
    'currentFileBytesCompleted': currentFileBytesCompleted,
    'currentFileTotalBytes': currentFileTotalBytes,
    'currentRange': currentRange,
    'currentPart': currentPart,
    'totalParts': totalParts,
  };
}

class RemoteTaskPhaseRecord {
  const RemoteTaskPhaseRecord({
    required this.name,
    this.status = '',
    this.detail = '',
    this.startedAt = '',
    this.finishedAt = '',
    this.progress = const RemoteTaskProgress(),
  });

  factory RemoteTaskPhaseRecord.fromJson(Object? value) {
    if (value is! Map) {
      return const RemoteTaskPhaseRecord(name: 'unknown');
    }
    return RemoteTaskPhaseRecord(
      name: (value['name'] ?? value['phase'] ?? 'unknown').toString(),
      status: (value['status'] ?? '').toString(),
      detail: (value['detail'] ?? '').toString(),
      startedAt: (value['startedAt'] ?? '').toString(),
      finishedAt: (value['finishedAt'] ?? '').toString(),
      progress: RemoteTaskProgress.fromJson(value['progress']),
    );
  }

  final String name;
  final String status;
  final String detail;
  final String startedAt;
  final String finishedAt;
  final RemoteTaskProgress progress;
}

class RemoteTaskEvent {
  const RemoteTaskEvent({
    required this.sequence,
    this.kind = '',
    this.state = '',
    this.sourcePath = '',
    this.targetPath = '',
    this.detail = '',
    this.folded = false,
    this.createdAt = '',
  });

  factory RemoteTaskEvent.fromJson(Object? value) {
    if (value is! Map) return const RemoteTaskEvent(sequence: 0);
    return RemoteTaskEvent(
      sequence: _int(value['sequence'] ?? value['seq']),
      kind: (value['kind'] ?? value['type'] ?? '').toString(),
      state: (value['state'] ?? '').toString(),
      sourcePath: (value['sourcePath'] ?? value['oldPath'] ?? '').toString(),
      targetPath: (value['targetPath'] ?? value['newPath'] ?? '').toString(),
      detail: (value['detail'] ?? value['lastError'] ?? '').toString(),
      folded: value['folded'] == true,
      createdAt: (value['createdAt'] ?? '').toString(),
    );
  }

  final int sequence;
  final String kind;
  final String state;
  final String sourcePath;
  final String targetPath;
  final String detail;
  final bool folded;
  final String createdAt;
}
