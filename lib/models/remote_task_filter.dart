// Request filters keep list pagination separate from task model parsing.
// Request filters keep task-list query construction out of the model body.
part of 'remote_task.dart';

class RemoteTaskFilter {
  const RemoteTaskFilter({
    this.profileId = '',
    this.bucket = '',
    this.statuses = const <RemoteTaskStatus>[],
    this.includeHistory = true,
    this.cursor = '',
    this.limit = 100,
  });

  final String profileId;
  final String bucket;
  final List<RemoteTaskStatus> statuses;
  final bool includeHistory;
  final String cursor;
  final int limit;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (profileId.trim().isNotEmpty) 'profileId': profileId.trim(),
    if (bucket.trim().isNotEmpty) 'bucket': bucket.trim(),
    if (statuses.isNotEmpty)
      'statuses': statuses
          .map((status) => status.wireName)
          .toList(growable: false),
    'includeHistory': includeHistory,
    if (cursor.isNotEmpty) 'cursor': cursor,
    'limit': limit,
  };

  RemoteTaskFilter copyWith({
    String? profileId,
    String? bucket,
    List<RemoteTaskStatus>? statuses,
    bool? includeHistory,
    String? cursor,
    int? limit,
  }) {
    return RemoteTaskFilter(
      profileId: profileId ?? this.profileId,
      bucket: bucket ?? this.bucket,
      statuses: statuses ?? this.statuses,
      includeHistory: includeHistory ?? this.includeHistory,
      cursor: cursor ?? this.cursor,
      limit: limit ?? this.limit,
    );
  }
}
