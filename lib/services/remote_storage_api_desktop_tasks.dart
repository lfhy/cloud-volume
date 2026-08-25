part of 'remote_storage_api_desktop.dart';

// Desktop task calls keep the FFI payload small and leave projection logic in Go.
mixin _RemoteStorageDesktopTasksApiMixin implements RemoteStorageGateway {
  Future<dynamic> runBridgeCall(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]);

  @override
  Future<RemoteTaskPage> listRemoteTasks([
    RemoteTaskFilter filter = const RemoteTaskFilter(),
  ]) async {
    final result = await runBridgeCall('list_remote_tasks', filter.toJson());
    return RemoteTaskPage.fromJson(result);
  }

  @override
  Future<RemoteTask> getRemoteTask(String taskId) async {
    final result = await runBridgeCall('get_remote_task', <String, dynamic>{
      'taskId': taskId,
    });
    return RemoteTask.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<bool> cancelRemoteTask(String taskId) async {
    final result = await runBridgeCall('cancel_remote_task', <String, dynamic>{
      'taskId': taskId,
    });
    return result is Map ? result['ok'] == true : result == true;
  }

  @override
  Future<bool> retryRemoteTask(String taskId) async {
    final result = await runBridgeCall('retry_remote_task', <String, dynamic>{
      'taskId': taskId,
    });
    return result is Map ? result['ok'] == true : result == true;
  }

  @override
  Future<bool> triggerRemoteTask(String taskId) async {
    final result = await runBridgeCall('trigger_remote_task', <String, dynamic>{
      'taskId': taskId,
    });
    return result is Map ? result['ok'] == true : result == true;
  }

  @override
  Future<int> triggerAllRemoteTasks({
    String profileId = '',
    String bucket = '',
  }) async {
    final result =
        await runBridgeCall('trigger_all_remote_tasks', <String, dynamic>{
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
    final result =
        await runBridgeCall('clear_remote_task_history', <String, dynamic>{
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
