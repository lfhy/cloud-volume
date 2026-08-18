// Web HTTP API keeps browser clients on server-side storage credentials.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:remote_storage/models/auth_session_state.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/bucket_mount_status.dart';
import 'package:remote_storage/models/cached_file_record.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/paged_listings.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/models/share_record.dart';
import 'package:remote_storage/models/system_proxy_info.dart';
import 'package:remote_storage/models/sync_profile.dart';
import 'package:remote_storage/models/trash_item.dart';
import 'package:remote_storage/models/transfer_job.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';

part 'remote_storage_api_web_objects.dart';
part 'remote_storage_api_web_paging.dart';
part 'remote_storage_api_web_transfers.dart';
part 'remote_storage_api_web_tasks.dart';

class RemoteStorageRequestException implements Exception {
  const RemoteStorageRequestException(this.message);

  final String message;

  @override
  String toString() => 'RemoteStorageBridgeException: $message';
}

class RemoteStorageApi
    with
        _RemoteStorageWebObjectApiMixin,
        _RemoteStorageWebPagingApiMixin,
        _RemoteStorageWebTransferApiMixin,
        _RemoteStorageWebTasksApiMixin
    implements RemoteStorageGateway {
  RemoteStorageApi({http.Client? client}) : _client = client ?? http.Client();

  static Future<RemoteStorageApi> bootstrap() async {
    return RemoteStorageApi();
  }

  @override
  final http.Client _client;

  @override
  RemoteStorageCapabilities get capabilities =>
      const RemoteStorageCapabilities.web();

  @override
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

  @override
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
  Future<void> writeAppLog(
    String message, {
    String level = 'info',
    String tag = 'flutter',
  }) async {}

  @override
  Future<void> setLogLevel(String level) async {}

  @override
  Future<String> installApp({
    required String assetUrl,
    required String assetName,
    required int assetSize,
    required String assetDigest,
    required String installerType,
    required String mirrorPrefix,
    required RemoteStorageConfig config,
    required String proxyMode,
    required String proxyType,
    required String proxyHost,
    required String proxyPort,
    required String proxyUsername,
    required String proxyPassword,
  }) async {
    throw UnsupportedError('Web 端不支持应用内自动更新，请前往 GitHub 下载。');
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
  Future<BridgeBuildInfo> getBuildInfo() async {
    return const BridgeBuildInfo();
  }

  @override
  Future<SystemProxyInfo?> resolveSystemProxy() async {
    // Browsers own proxy resolution; the host system proxy is not exposed to
    // web origins.
    return null;
  }

  @override
  Future<Map<String, dynamic>?> matchPlatformAsset(
    List<Map<String, dynamic>> assets, {
    String? runtimeArchitecture,
  }) async {
    // Web builds cannot install native packages; no asset matching needed.
    return null;
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
  Future<void> validateAccountCredentials(RemoteStorageConfig config) async {
    await _invoke('validate_account_credentials', <String, dynamic>{
      'config': config.toJson(),
    });
  }

  @override
  Future<bool> updateProxySettings({
    required String proxyMode,
    required String proxyType,
    required String proxyHost,
    required String proxyPort,
    required String proxyUsername,
    required String proxyPassword,
  }) async {
    // Web builds run server-side; proxy is handled by the browser.
    return true;
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
  Future<Map<String, dynamic>> deleteProfile(String name) async {
    await _invoke('delete_profile', <String, dynamic>{'name': name});
    return const <String, dynamic>{};
  }

  @override
  Future<BootstrapState> resetUserConfig() async {
    final payload =
        await _invoke('reset_user_config', <String, dynamic>{'confirm': true})
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
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
  Future<void> reorderProfiles(List<String> names) async {
    await _invoke('reorder_profiles', <String, dynamic>{'names': names});
  }

  @override
  Future<void> reorderBuckets(List<String> ids) async {
    await _invoke('reorder_buckets', <String, dynamic>{'ids': ids});
  }

  @override
  Future<List<String>> listBucketOrder() async {
    final result = await _invoke('list_bucket_order');
    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }
    return const <String>[];
  }

  @override
  Future<ConfigBackupSettings> loadConfigBackupSettings() =>
      throw UnsupportedError('Web 端暂不支持本地配置备份');

  @override
  Future<ConfigBackupSettings> saveConfigBackupSettings(
    ConfigBackupSettings settings,
  ) => throw UnsupportedError('Web 端暂不支持本地配置备份');

  @override
  Future<ConfigBackupSnapshot> backupConfigNow() =>
      throw UnsupportedError('Web 端暂不支持本地配置备份');

  @override
  Future<List<ConfigBackupSnapshot>> listConfigBackups() =>
      throw UnsupportedError('Web 端暂不支持本地配置备份');

  @override
  Future<BootstrapState> restoreConfigBackup(String key) =>
      throw UnsupportedError('Web 端暂不支持本地配置备份');

  @override
  Future<void> deleteConfigBackup(String key) =>
      throw UnsupportedError('Web 端暂不支持本地配置备份');

  @override
  Future<List<ConfigBackupSnapshot>> listConfigBackupsWithTarget(
    ConfigBackupTarget target,
  ) => throw UnsupportedError('Web 端暂不支持本地配置备份');

  @override
  Future<BootstrapState> restoreConfigBackupWithTarget(
    ConfigBackupTarget target,
    String key, {
    String? password,
  }) => throw UnsupportedError('Web 端暂不支持本地配置备份');

  @override
  Future<bool> verifyBackupPassword(
    ConfigBackupTarget target,
    String key, {
    String? password,
  }) => throw UnsupportedError('Web 端暂不支持本地配置备份');

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
  Future<CacheStats> getCacheStats(RemoteStorageConfig config) async {
    final result = await _invoke('get_cache_stats');
    return CacheStats.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> openCacheDirectory(RemoteStorageConfig config) {
    // Browsers cannot reveal a local directory; the settings UI hides this
    // action on web via capabilities.
    throw UnsupportedError('Web 端暂不支持打开本地缓存目录');
  }

  @override
  Future<CleanCacheResult> cleanCache(
    RemoteStorageConfig config, {
    required bool clearAll,
  }) async {
    final result = await _invoke('clean_cache', <String, dynamic>{
      'clearAll': clearAll,
    });
    return CleanCacheResult.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<CachedFileRecord?> findCacheIndexRecord({
    required String bucket,
    required String objectKey,
  }) async {
    return null;
  }

  @override
  Future<void> upsertCacheIndexRecord(CachedFileRecord record) async {}

  @override
  Future<void> removeCacheIndexRecord({
    required String bucket,
    required String objectKey,
  }) async {}

  @override
  Future<List<CachedFileRecord>> removeCacheIndexPrefix({
    required String bucket,
    required String objectKeyPrefix,
  }) async {
    return <CachedFileRecord>[];
  }

  @override
  Future<BucketMountStatus> unmountBucket(
    String bucket, {
    bool removeLocalCache = false,
  }) async {
    final result = await _invoke('unmount_bucket', <String, dynamic>{
      'bucket': bucket,
      'removeLocalCache': removeLocalCache,
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

  // Web 端目录同步依赖本地文件系统，暂不支持。

  @override
  Future<List<SyncProfileRuntime>> listSyncProfiles() async {
    throw UnsupportedError('Web 端暂不支持目录同步');
  }

  @override
  Future<String> saveSyncProfile(SyncProfile profile) async {
    throw UnsupportedError('Web 端暂不支持目录同步');
  }

  @override
  Future<void> deleteSyncProfile(String id) async {
    throw UnsupportedError('Web 端暂不支持目录同步');
  }

  @override
  Future<int> triggerSyncProfile(String id) async {
    throw UnsupportedError('Web 端暂不支持目录同步');
  }

  @override
  Future<Map<String, dynamic>> getP2PStatus() async =>
      throw UnsupportedError('Web 端不支持 P2P');

  @override
  Future<void> setP2PEnabled(bool enabled) async =>
      throw UnsupportedError('Web 端不支持 P2P');
}
