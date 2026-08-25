// Wire models for the unified remote-task endpoint: the Task aggregate plus
// page/queue envelope parsing shared by the store and page projections.
part of 'remote_task.dart';

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

// RemoteTaskQueueCounts carries server-reported unpaged queue sizes plus
// whether the server actually sent them; presence matters because a real
// all-zero report must not be mistaken for "field omitted".
class RemoteTaskQueueCounts {
  const RemoteTaskQueueCounts({
    this.active = 0,
    this.waiting = 0,
    this.failed = 0,
    this.history = 0,
    this.total = 0,
    this.reported = false,
  });

  factory RemoteTaskQueueCounts.fromJson(Object? value) {
    if (value is! Map) return const RemoteTaskQueueCounts();
    return RemoteTaskQueueCounts(
      active: _int(value['active']),
      waiting: _int(value['waiting']),
      failed: _int(value['failed']),
      history: _int(value['history']),
      total: _int(value['total']),
      reported: true,
    );
  }

  // Server-reported unpaged queue sizes; never derived from loaded rows.
  final int active;
  final int waiting;
  final int failed;
  final int history;
  final int total;
  // True once the backend sent a queue block, even when every count is 0.
  final bool reported;
}

class RemoteTaskPage {
  const RemoteTaskPage({
    this.items = const <RemoteTask>[],
    this.total = 0,
    this.hasTotal = false,
    this.queue = const RemoteTaskQueueCounts(),
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
      total: _int(value['total']),
      hasTotal: value['total'] != null,
      queue: RemoteTaskQueueCounts.fromJson(value['queue']),
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
  // Full unpaged queue total, including history even for active-only polls,
  // so the header does not become "共 0 项 · 已加载 200".
  final int total;
  // Presence flag: a genuine zero must override any stale cached total.
  final bool hasTotal;
  final RemoteTaskQueueCounts queue;
  final String nextCursor;
  final String serverTime;
  final String freshness;
  final Map<String, bool> capabilities;
}
