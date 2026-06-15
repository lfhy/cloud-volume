part of 'remote_storage_api_desktop.dart';

// Paged bridge calls keep large directory and trash views incremental.
mixin _RemoteStoragePagingApiMixin implements RemoteStorageGateway {
  RemoteStorageBridge get bridgeHandle;
  Future<dynamic> runBridgeCall(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]);
  List<T> parseBridgeList<T>(
    dynamic result,
    T Function(Map<String, dynamic>) fromJson,
  );

  @override
  Future<List<ObjectInfo>> listObjects(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async {
    final items = <ObjectInfo>[];
    var nextToken = '';
    do {
      final page = await listObjectPage(config, bucket, prefix, nextToken, 500);
      items.addAll(page.items);
      nextToken = page.nextToken;
    } while (nextToken.isNotEmpty);
    return items;
  }

  @override
  Future<ObjectListPage> listObjectPage(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String nextToken,
    int pageSize,
  ) async {
    final result = await runBridgeCall('list_object_page', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'prefix': prefix,
      'nextToken': nextToken,
      'pageSize': pageSize,
    });
    return ObjectListPage.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<TrashItem>> listTrash(
    RemoteStorageConfig config,
    String bucket,
  ) async {
    final items = <TrashItem>[];
    var nextToken = '';
    do {
      final page = await listTrashPage(config, bucket, nextToken, 500);
      items.addAll(page.items);
      nextToken = page.nextToken;
    } while (nextToken.isNotEmpty);
    return items;
  }

  @override
  Future<TrashListPage> listTrashPage(
    RemoteStorageConfig config,
    String bucket,
    String nextToken,
    int pageSize,
  ) async {
    final result = await runBridgeCall('list_trash_page', <String, dynamic>{
      'config': config.toJson(),
      'bucket': bucket,
      'nextToken': nextToken,
      'pageSize': pageSize,
    });
    return TrashListPage.fromJson(result as Map<String, dynamic>);
  }
}
