// Web HTTP API keeps browser clients on server-side storage credentials.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

part 'remote_storage_api_web_objects.dart';
part 'remote_storage_api_web_paging.dart';

class RemoteStorageRequestException implements Exception {
  const RemoteStorageRequestException(this.message);

  final String message;

  @override
  String toString() => 'RemoteStorageBridgeException: $message';
}

class RemoteStorageApi
    with _RemoteStorageWebObjectApiMixin, _RemoteStorageWebPagingApiMixin
    implements RemoteStorageGateway {
  RemoteStorageApi({http.Client? client}) : _client = client ?? http.Client();

  static Future<RemoteStorageApi> bootstrap() async {
    return RemoteStorageApi();
  }

  final http.Client _client;

  @override
  RemoteStorageCapabilities get capabilities =>
      const RemoteStorageCapabilities.web();

  Uri _apiUri(String path, [Map<String, String>? queryParameters]) {
    return Uri.base.resolveUri(
      Uri(
        path: path,
        queryParameters: queryParameters?.isEmpty == true
            ? null
            : queryParameters,
      ),
    );
  }

  @override
  Future<dynamic> _invoke(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    final response = await _client.post(
      _apiUri('/api/invoke/$method'),
      headers: const <String, String>{'content-type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _decodeResponse(response);
  }

  dynamic _decodeResponse(http.Response response) {
    final payload = _tryDecodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RemoteStorageRequestException(_responseError(payload, response));
    }
    if (payload is Map<String, dynamic> && payload['ok'] == true) {
      return payload['result'];
    }
    return payload;
  }

  Object? _tryDecodeJson(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return jsonDecode(trimmed);
  }

  String _responseError(Object? payload, http.Response response) {
    if (payload is Map<String, dynamic>) {
      final error = payload['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message']?.toString().trim() ?? '';
        if (message.isNotEmpty) {
          return message;
        }
      }
      final message = payload['message']?.toString().trim() ?? '';
      if (message.isNotEmpty) {
        return message;
      }
    }
    return 'HTTP ${response.statusCode}';
  }

  @override
  List<T> _parseList<T>(
    dynamic result,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (result is! List) {
      return <T>[];
    }
    return result
        .map((item) => fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<AuthSessionState> loadAuthSession() async {
    final response = await _client.get(_apiUri('/api/auth/session'));
    if (response.statusCode == 401) {
      return const AuthSessionState(authenticated: false, loginRequired: true);
    }
    final payload =
        _decodeResponse(response) as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return AuthSessionState.fromJson(payload);
  }

  @override
  Future<void> login(String username, String password) async {
    final response = await _client.post(
      _apiUri('/api/auth/login'),
      headers: const <String, String>{'content-type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'username': username,
        'password': password,
      }),
    );
    _decodeResponse(response);
  }

  @override
  Future<void> logout() async {
    final response = await _client.post(_apiUri('/api/auth/logout'));
    _decodeResponse(response);
  }

  @override
  Future<BootstrapState> loadBootstrapState() async {
    final payload =
        await _invoke('load_bootstrap_state') as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async {
    final payload =
        await _invoke('save_config', <String, dynamic>{
              'config': config.toJson(),
            })
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<String> startBaiduPanAuthorization() {
    throw UnsupportedError('Web 端暂不支持桌面百度网盘 OAuth 授权');
  }

  @override
  Future<RemoteStorageConfig> authorizeBaiduPan(
    String displayName,
    String code,
  ) {
    throw UnsupportedError('Web 端暂不支持桌面百度网盘 OAuth 授权');
  }

  @override
  Future<RemoteStorageConfig> loadProfile(String name) async {
    final result = await _invoke('load_profile', <String, dynamic>{
      'name': name,
    });
    return RemoteStorageConfig.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<ProfileInfo>> listProfiles() async {
    final result = await _invoke('list_profiles');
    return _parseList(result, (m) => ProfileInfo.fromJson(m));
  }

  @override
  Future<void> saveProfile(String name, RemoteStorageConfig config) async {
    await _invoke('save_profile', <String, dynamic>{
      'name': name,
      'config': config.toJson(),
    });
  }

  @override
  Future<void> deleteProfile(String name) async {
    await _invoke('delete_profile', <String, dynamic>{'name': name});
  }

  @override
  Future<BootstrapState> setActiveProfile(String name) async {
    final payload =
        await _invoke('set_active_profile', <String, dynamic>{'name': name})
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<List<BucketInfo>> listBuckets(RemoteStorageConfig config) async {
    final result = await _invoke('list_buckets');
    return _parseList(result, (m) => BucketInfo.fromJson(m));
  }

  @override
  Future<void> uploadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) {
    throw UnsupportedError('Web 端上传使用浏览器内存文件，不走本地路径');
  }

  @override
  Future<void> uploadDirectory(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
    String localPath,
    String taskId,
  ) {
    throw UnsupportedError('Web 端暂不支持本地目录上传');
  }

  @override
  Future<void> uploadBytes(
    RemoteStorageConfig config,
    String bucket,
    String key,
    Uint8List bytes,
    String taskId, {
    String fileName = '',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _apiUri('/api/upload', {'bucket': bucket, 'key': key, 'taskId': taskId}),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName.isEmpty ? key.split('/').last : fileName,
      ),
    );
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _decodeResponse(response);
  }

  @override
  Future<void> downloadFile(
    RemoteStorageConfig config,
    String bucket,
    String key,
    String localPath,
    String taskId,
  ) {
    throw UnsupportedError('Web 端下载使用浏览器地址，不写入本地路径');
  }

  @override
  Uri? objectDownloadUri(String bucket, String key, {bool inline = false}) {
    return _apiUri('/api/download', <String, String>{
      'bucket': bucket,
      'key': key,
      if (inline) 'inline': '1',
    });
  }

  @override
  Uri? webDavUri(String bucket) {
    return _apiUri('/webdav/$bucket/');
  }

  @override
  Future<void> cancelTransfer(String taskId) async {
    await _invoke('cancel_transfer', <String, dynamic>{'taskId': taskId});
  }

  @override
  Future<bool> triggerTransfer(String taskId) async {
    final result = await _invoke('trigger_transfer', <String, dynamic>{
      'taskId': taskId,
    });
    if (result is Map<String, dynamic>) {
      return result['ok'] == true;
    }
    return result == true;
  }

  @override
  Future<List<TransferSnapshot>> listTransferJobs() async {
    final result = await _invoke('list_transfer_jobs');
    return _parseList(result, (m) => TransferSnapshot.fromJson(m));
  }

  @override
  Future<BucketMountStatus> mountBucket(
    RemoteStorageConfig config,
    String bucket,
    MountBucketOptions options,
  ) async {
    final result = await _invoke('mount_bucket', <String, dynamic>{
      'bucket': bucket,
      'options': options.toJson(),
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> cleanupMounts() async {
    await _invoke('cleanup_mounts');
  }

  @override
  Future<int> cleanupStaleWindowsProcesses() async {
    final result = await _invoke('cleanup_stale_windows_processes');
    if (result is Map<String, dynamic>) {
      return (result['count'] ?? 0) as int;
    }
    if (result is num) {
      return result.toInt();
    }
    return 0;
  }

  @override
  Future<BucketMountStatus> unmountBucket(String bucket) async {
    final result = await _invoke('unmount_bucket', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<BucketMountStatus> getBucketMountStatus(String bucket) async {
    final result = await _invoke('get_bucket_mount_status', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<BucketMountStatus> openBucketMount(String bucket) async {
    final result = await _invoke('open_bucket_mount', <String, dynamic>{
      'bucket': bucket,
    });
    return BucketMountStatus.fromJson(result as Map<String, dynamic>);
  }
}
