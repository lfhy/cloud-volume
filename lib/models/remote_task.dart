// Unified remote-operation models shared by the task page, sidebar, and sync cards.

part 'remote_task_parsing.dart';
part 'remote_task_filter.dart';

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

class RemoteTask {
  const RemoteTask({
    required this.id,
    required this.kind,
    required this.status,
    this.source = RemoteTaskSource.unknown,
    this.namespaceId = '',
    this.profileId = '',
    this.profileName = '',
    this.bucket = '',
    this.sourcePath = '',
    this.targetPath = '',
    this.localPath = '',
    this.displayPath = '',
    this.phase = RemoteTaskPhase.unknown,
    this.phaseDetail = '',
    this.blockedReason = '',
    this.error = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.finishedAt = '',
    this.retryCount = 0,
    this.nextRetryAt = '',
    this.cancelable = false,
    this.retryable = false,
    this.triggerable = false,
    this.progress = const RemoteTaskProgress(),
    this.phases = const <RemoteTaskPhaseRecord>[],
    this.events = const <RemoteTaskEvent>[],
    this.dependencies = const <String>[],
    this.physicalTaskIds = const <String>[],
    this.rawEventCount = 0,
    this.optimisticCancel = false,
    this.remoteOutcome = '',
  });

  factory RemoteTask.fromJson(Map<String, dynamic> json) {
    final source = (json['source'] ?? '').toString().trim().toLowerCase();
    return RemoteTask(
      id: (json['id'] ?? '').toString(),
      kind: RemoteTaskKind.fromWire(json['kind'] ?? json['type']),
      status: RemoteTaskStatus.fromWire(json['status']),
      source: switch (source) {
        'metadata' || 'journal' => RemoteTaskSource.metadata,
        'runtime' || 'transfer' => RemoteTaskSource.runtime,
        'sync' => RemoteTaskSource.sync,
        'local' => RemoteTaskSource.local,
        'app_update' || 'appupdate' => RemoteTaskSource.appUpdate,
        _ => RemoteTaskSource.unknown,
      },
      namespaceId: (json['namespaceId'] ?? '').toString(),
      profileId: (json['profileId'] ?? '').toString(),
      profileName: (json['profileName'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      sourcePath: (json['sourcePath'] ?? json['key'] ?? '').toString(),
      targetPath: (json['targetPath'] ?? '').toString(),
      localPath: (json['localPath'] ?? '').toString(),
      displayPath: (json['displayPath'] ?? '').toString(),
      phase: _phaseFromWire(json['phase']),
      phaseDetail:
          (json['phaseDetail'] ?? json['statusDetail'] ?? json['phase'] ?? '')
              .toString(),
      blockedReason: (json['blockedReason'] ?? '').toString(),
      error: (json['error'] ?? json['lastError'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
      finishedAt: (json['finishedAt'] ?? '').toString(),
      retryCount: _int(json['retryCount'] ?? json['retry']),
      nextRetryAt: (json['nextRetryAt'] ?? '').toString(),
      cancelable: json['cancelable'] == true,
      retryable: json['retryable'] == true,
      triggerable: json['triggerable'] == true,
      progress: RemoteTaskProgress.fromJson(json['progress']),
      phases: _records(
        json['phases'],
      ).map(RemoteTaskPhaseRecord.fromJson).toList(growable: false),
      events: _records(
        json['events'],
      ).map(RemoteTaskEvent.fromJson).toList(growable: false),
      dependencies: _strings(json['dependencies']),
      physicalTaskIds: _strings(json['physicalTaskIds']),
      rawEventCount: _int(json['rawEventCount']),
      optimisticCancel: json['optimisticCancel'] == true,
      remoteOutcome: (json['remoteOutcome'] ?? '').toString(),
    );
  }

  final String id;
  final RemoteTaskKind kind;
  final RemoteTaskStatus status;
  final RemoteTaskSource source;
  final String namespaceId;
  final String profileId;
  final String profileName;
  final String bucket;
  final String sourcePath;
  final String targetPath;
  final String localPath;
  final String displayPath;
  final RemoteTaskPhase phase;
  final String phaseDetail;
  final String blockedReason;
  final String error;
  final String createdAt;
  final String updatedAt;
  final String finishedAt;
  final int retryCount;
  final String nextRetryAt;
  final bool cancelable;
  final bool retryable;
  final bool triggerable;
  final RemoteTaskProgress progress;
  final List<RemoteTaskPhaseRecord> phases;
  final List<RemoteTaskEvent> events;
  final List<String> dependencies;
  final List<String> physicalTaskIds;
  final int rawEventCount;
  final bool optimisticCancel;
  final String remoteOutcome;

  String get name {
    final value = displayPath.isNotEmpty
        ? displayPath
        : targetPath.isNotEmpty
        ? targetPath
        : sourcePath;
    final parts = value.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? value : parts.last;
  }

  RemoteTask copyWith({
    RemoteTaskStatus? status,
    bool? optimisticCancel,
    String? updatedAt,
  }) {
    return RemoteTask(
      id: id,
      kind: kind,
      status: status ?? this.status,
      source: source,
      namespaceId: namespaceId,
      profileId: profileId,
      profileName: profileName,
      bucket: bucket,
      sourcePath: sourcePath,
      targetPath: targetPath,
      localPath: localPath,
      displayPath: displayPath,
      phase: phase,
      phaseDetail: phaseDetail,
      blockedReason: blockedReason,
      error: error,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      finishedAt: finishedAt,
      retryCount: retryCount,
      nextRetryAt: nextRetryAt,
      cancelable: cancelable,
      retryable: retryable,
      triggerable: triggerable,
      progress: progress,
      phases: phases,
      events: events,
      dependencies: dependencies,
      physicalTaskIds: physicalTaskIds,
      rawEventCount: rawEventCount,
      optimisticCancel: optimisticCancel ?? this.optimisticCancel,
      remoteOutcome: remoteOutcome,
    );
  }
}

class RemoteTaskPage {
  const RemoteTaskPage({
    this.items = const <RemoteTask>[],
    this.nextCursor = '',
    this.serverTime = '',
    this.freshness = '',
    this.capabilities = const <String, bool>{},
  });

  factory RemoteTaskPage.fromJson(Object? value) {
    if (value is List) {
      return RemoteTaskPage(
        items: value
            .whereType<Map>()
            .map((item) => RemoteTask.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
      );
    }
    if (value is! Map) return const RemoteTaskPage();
    final raw = value['items'] ?? value['tasks'] ?? const <Object>[];
    return RemoteTaskPage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (item) =>
                      RemoteTask.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const <RemoteTask>[],
      nextCursor: (value['nextCursor'] ?? '').toString(),
      serverTime: (value['serverTime'] ?? '').toString(),
      freshness: (value['freshness'] ?? '').toString(),
      capabilities: value['capabilities'] is Map
          ? (value['capabilities'] as Map).map(
              (key, item) => MapEntry(key.toString(), item == true),
            )
          : const <String, bool>{},
    );
  }

  final List<RemoteTask> items;
  final String nextCursor;
  final String serverTime;
  final String freshness;
  final Map<String, bool> capabilities;
}
