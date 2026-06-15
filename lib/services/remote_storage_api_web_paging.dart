part of 'remote_storage_api_web.dart';

mixin _RemoteStorageWebPagingApiMixin implements RemoteStorageGateway {
  Future<dynamic> _invoke(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]);

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
    final result = await _invoke('list_object_page', <String, dynamic>{
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
    final result = await _invoke('list_trash_page', <String, dynamic>{
      'bucket': bucket,
      'nextToken': nextToken,
      'pageSize': pageSize,
    });
    return TrashListPage.fromJson(result as Map<String, dynamic>);
  }
}
