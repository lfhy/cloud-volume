// Queue-wide remote actions stay separate from polling and cache merge logic.
part of 'remote_task_store.dart';

extension RemoteTaskStoreActions on RemoteTaskStore {
  /// Skips the quiet period for every durable pending task in scope, then
  /// refreshes the active projection so the queue immediately reflects it.
  Future<int> triggerAllRemoteTasks({
    String profileId = '',
    String bucket = '',
  }) async {
    final api = _api;
    if (api == null) return 0;
    final generation = _bindingGeneration;
    final triggered = await api.triggerAllRemoteTasks(
      profileId: profileId,
      bucket: bucket,
    );
    if (generation != _bindingGeneration || !identical(api, _api)) return 0;
    await pollActive();
    if (generation != _bindingGeneration || !identical(api, _api)) return 0;
    return triggered;
  }
}
