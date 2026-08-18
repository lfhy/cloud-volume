// Desktop bridge-backed API keeps the existing FFI workflow intact for native builds.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:remote_storage/bridge/remote_storage_bridge.dart';
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
part 'remote_storage_api_desktop_shares.dart';
part 'remote_storage_api_desktop_paging.dart';
part 'remote_storage_api_desktop_runtime.dart';
part 'remote_storage_api_desktop_storage.dart';
part 'remote_storage_api_desktop_cache.dart';
part 'remote_storage_api_desktop_tasks.dart';

dynamic _invokeBridgeCall(
  String libraryPath,
  String method,
  Map<String, dynamic> payload,
) {
  final bridge = RemoteStorageBridge.openAtPath(libraryPath);
  return bridge.call(method, payload);
}

class RemoteStorageApi
    with
        _RemoteStorageShareApiMixin,
        _RemoteStoragePagingApiMixin,
        _RemoteStorageRuntimeApiMixin,
        _RemoteStorageDesktopStorageApiMixin,
        _RemoteStorageCacheApiMixin,
        _RemoteStorageDesktopTasksApiMixin
    implements RemoteStorageGateway, ActiveMountQuery {
  RemoteStorageApi(this._bridge);

  static Future<RemoteStorageApi> bootstrap() async {
    final bridge = await RemoteStorageBridge.connect();
    return RemoteStorageApi(bridge);
  }

  final RemoteStorageBridge _bridge;

  @override
  RemoteStorageCapabilities get capabilities =>
      const RemoteStorageCapabilities.desktop();

  @override
  RemoteStorageBridge get bridgeHandle => _bridge;

  @override
  Future<dynamic> runBridgeCall(
    String method, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) {
    final libraryPath = _bridge.libraryPath;
    final isolatePayload = payload.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(payload);
    // Keep synchronous FFI work off the UI isolate so large bridge calls do not
    // stall scrolling, hover states, or route transitions.
    return Isolate.run(
      () => _invokeBridgeCall(libraryPath, method, isolatePayload),
    );
  }

  @override
  Future<void> writeAppLog(
    String message, {
    String level = 'info',
    String tag = 'flutter',
  }) async {
    await runBridgeCall('write_flutter_log', <String, dynamic>{
      'message': message,
      'level': level,
      'tag': tag,
    });
  }

  @override
  Future<void> setLogLevel(String level) async {
    await runBridgeCall('set_log_level', <String, dynamic>{'level': level});
  }

  @override
  Future<AuthSessionState> loadAuthSession() async {
    return const AuthSessionState.desktop();
  }

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<BootstrapState> loadBootstrapState() async {
    final payload =
        await runBridgeCall('load_bootstrap_state') as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<BridgeBuildInfo> getBuildInfo() async {
    final payload =
        await runBridgeCall('get_build_info') as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BridgeBuildInfo.fromJson(payload);
  }

  @override
  Future<Map<String, dynamic>?> matchPlatformAsset(
    List<Map<String, dynamic>> assets, {
    String? runtimeArchitecture,
  }) async {
    try {
      final payload =
          await runBridgeCall('match_platform_asset', {
                'assets': assets,
                'runtimeArchitecture': ?runtimeArchitecture,
              })
              as Map<String, dynamic>?;
      return payload;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SystemProxyInfo?> resolveSystemProxy() async {
    final payload =
        await runBridgeCall('resolve_system_proxy') as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final info = SystemProxyInfo.fromJson(payload);
    return info.available ? info : null;
  }

  @override
  Future<BootstrapState> saveConfig(RemoteStorageConfig config) async {
    final payload =
        await runBridgeCall('save_config', <String, dynamic>{
              'config': config.toJson(),
            })
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
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
    final result =
        await runBridgeCall('update_proxy_settings', <String, dynamic>{
          'proxyMode': proxyMode,
          'proxyType': proxyType,
          'proxyHost': proxyHost,
          'proxyPort': proxyPort,
          'proxyUsername': proxyUsername,
          'proxyPassword': proxyPassword,
        });
    return result == true;
  }

  @override
  Future<String> startBaiduPanAuthorization() async {
    final result =
        await runBridgeCall('start_baidu_pan_authorization')
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return (result['authUrl'] ?? '').toString();
  }

  @override
  Future<RemoteStorageConfig> authorizeBaiduPan(
    String displayName,
    String code,
  ) async {
    final result = await runBridgeCall('authorize_baidu_pan', <String, dynamic>{
      'displayName': displayName,
      'code': code,
    });
    return RemoteStorageConfig.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<RemoteStorageConfig> loadProfile(String name) async {
    final result = await runBridgeCall('load_profile', <String, dynamic>{
      'name': name,
    });
    return RemoteStorageConfig.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<ProfileInfo>> listProfiles() async {
    final result = await runBridgeCall('list_profiles');
    if (result is List) {
      return result
          .map((e) => ProfileInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<void> saveProfile(String name, RemoteStorageConfig config) async {
    await runBridgeCall('save_profile', <String, dynamic>{
      'name': name,
      'config': config.toJson(),
    });
  }

  @override
  Future<Map<String, dynamic>> deleteProfile(String name) async {
    final result = await runBridgeCall('delete_profile', <String, dynamic>{
      'name': name,
    });
    return (result as Map<String, dynamic>?) ?? const <String, dynamic>{};
  }

  @override
  Future<BootstrapState> resetUserConfig() async {
    final payload =
        await runBridgeCall('reset_user_config', <String, dynamic>{
              'confirm': true,
            })
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<BootstrapState> setActiveProfile(String name) async {
    final payload =
        await runBridgeCall('set_active_profile', <String, dynamic>{
              'name': name,
            })
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    return BootstrapState.fromJson(payload);
  }

  @override
  Future<void> reorderProfiles(List<String> names) async {
    await runBridgeCall('reorder_profiles', <String, dynamic>{'names': names});
  }

  @override
  Future<void> reorderBuckets(List<String> ids) async {
    await runBridgeCall('reorder_buckets', <String, dynamic>{'ids': ids});
  }

  @override
  Future<List<String>> listBucketOrder() async {
    final result = await runBridgeCall('list_bucket_order');
    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }
    return const <String>[];
  }

  @override
  Future<ConfigBackupSettings> loadConfigBackupSettings() async {
    final result = await runBridgeCall('load_config_backup_settings');
    return ConfigBackupSettings.fromJson(
      result as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  @override
  Future<ConfigBackupSettings> saveConfigBackupSettings(
    ConfigBackupSettings settings,
  ) async {
    final result = await runBridgeCall('save_config_backup_settings', {
      'settings': settings.toJson(),
    });
    return ConfigBackupSettings.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<ConfigBackupSnapshot> backupConfigNow() async {
    final result = await runBridgeCall('backup_config_now');
    return ConfigBackupSnapshot.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<List<ConfigBackupSnapshot>> listConfigBackups() async {
    final result = await runBridgeCall('list_config_backups');
    if (result is! List) return const <ConfigBackupSnapshot>[];
    return result
        .map(
          (item) => ConfigBackupSnapshot.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<BootstrapState> restoreConfigBackup(String key) async {
    final result = await runBridgeCall('restore_config_backup', {'key': key});
    return BootstrapState.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<void> deleteConfigBackup(String key) async {
    await runBridgeCall('delete_config_backup', {'key': key});
  }

  @override
  Future<List<ConfigBackupSnapshot>> listConfigBackupsWithTarget(
    ConfigBackupTarget target,
  ) async {
    final result = await runBridgeCall('list_config_backups_with_target', {
      'target': target.toJson(),
    });
    if (result is! List) return const <ConfigBackupSnapshot>[];
    return result
        .map(
          (item) => ConfigBackupSnapshot.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<BootstrapState> restoreConfigBackupWithTarget(
    ConfigBackupTarget target,
    String key, {
    String? password,
  }) async {
    final args = <String, dynamic>{'target': target.toJson(), 'key': key};
    if (password != null && password.isNotEmpty) {
      args['passwordOverride'] = password;
    }
    final result = await runBridgeCall(
      'restore_config_backup_with_target',
      args,
    );
    return BootstrapState.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<bool> verifyBackupPassword(
    ConfigBackupTarget target,
    String key, {
    String? password,
  }) async {
    final args = <String, dynamic>{'target': target.toJson(), 'key': key};
    if (password != null && password.isNotEmpty) {
      args['passwordOverride'] = password;
    }
    await runBridgeCall('verify_backup_password', args);
    return true;
  }

  @override
  List<T> parseBridgeList<T>(
    dynamic result,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (result is List) {
      return result.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  // --- Directory sync ---

  @override
  Future<List<SyncProfileRuntime>> listSyncProfiles() async {
    final result = await runBridgeCall('list_sync_profiles');
    final list = result as List<dynamic>;
    return list
        .map((e) => SyncProfileRuntime.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<String> saveSyncProfile(SyncProfile profile) async {
    final result = await runBridgeCall('save_sync_profile', <String, dynamic>{
      'profile': profile.toJson(),
    });
    return (result as Map<String, dynamic>)['id'].toString();
  }

  @override
  Future<void> deleteSyncProfile(String id) async {
    await runBridgeCall('delete_sync_profile', <String, dynamic>{'id': id});
  }

  @override
  Future<int> triggerSyncProfile(String id) async {
    final result = await runBridgeCall(
      'trigger_sync_profile',
      <String, dynamic>{'id': id},
    );
    return (result as Map<String, dynamic>)['ops'] as int;
  }

  @override
  Future<Map<String, dynamic>> getP2PStatus() async {
    final result = await runBridgeCall('get_p2p_status', {});
    if (result is Map<String, dynamic>) return result;
    return <String, dynamic>{};
  }

  @override
  Future<void> setP2PEnabled(bool enabled) async {
    await runBridgeCall('set_p2p_enabled', {'enabled': enabled});
  }
}
