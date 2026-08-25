part of 'remote_storage_api_web.dart';

// Web task calls use the authenticated server-side active profile scope.
mixin _RemoteStorageWebTasksApiMixin implements RemoteStorageGateway {
  Future<dynamic> _invoke(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]);

  @override
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async {
    return RemoteTaskPage.fromJson(
      await _invoke('list_remote_tasks', filter.toJson()),
    );
  }

  @override
  Future<RemoteTask> getRemoteTask(String taskId) async {
    final result = await _invoke('get_remote_task', <String, dynamic>{
      'taskId': taskId,
    });
    return RemoteTask.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<bool> cancelRemoteTask(String taskId) async {
    final result = await _invoke('cancel_remote_task', <String, dynamic>{
      'taskId': taskId,
    });
    return result is Map ? result['ok'] == true : result == true;
  }

  @override
  Future<bool> retryRemoteTask(String taskId) async {
    final result = await _invoke('retry_remote_task', <String, dynamic>{
      'taskId': taskId,
    });
    return result is Map ? result['ok'] == true : result == true;
  }

  @override
  Future<bool> triggerRemoteTask(String taskId) async {
    final result = await _invoke('trigger_remote_task', <String, dynamic>{
      'taskId': taskId,
    });
    return result is Map ? result['ok'] == true : result == true;
  }

  @override
  Future<int> triggerAllRemoteTasks({
    String profileId = '',
    String bucket = '',
  }) async {
    final result = await _invoke('trigger_all_remote_tasks', <String, dynamic>{
      if (profileId.trim().isNotEmpty) 'profileId': profileId.trim(),
      if (bucket.trim().isNotEmpty) 'bucket': bucket.trim(),
    });
    return result is Map && result['triggered'] is num
        ? (result['triggered'] as num).toInt()
        : 0;
  }

  @override
  Future<int> clearRemoteTaskHistory({
    String profileId = '',
    String bucket = '',
    List<String> taskIds = const <String>[],
  }) async {
    final result = await _invoke('clear_remote_task_history', <String, dynamic>{
      if (profileId.trim().isNotEmpty) 'profileId': profileId.trim(),
      if (bucket.trim().isNotEmpty) 'bucket': bucket.trim(),
      if (taskIds.isNotEmpty) 'taskIds': taskIds,
    });
    if (result is Map && result['removed'] is num) {
      return (result['removed'] as num).toInt();
    }
    return 0;
  }
}
