// 账号管理页负责展示所有账号，并把账号新增、编辑与退出操作串起来。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/account_editor_presenter.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/utils/account_profile_name.dart';
import 'package:remote_storage/utils/bridge_error_text.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/bucket_visibility_dialog.dart';
import 'package:remote_storage/widgets/cloud_storage_account_list.dart';
import 'package:remote_storage/widgets/file_manager_action_bar.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CloudStoragePage extends StatefulWidget {
  const CloudStoragePage({
    super.key,
    required this.state,
    required this.api,
    required this.onRefresh,
  });

  final BootstrapState state;
  final RemoteStorageGateway api;
  final VoidCallback onRefresh;

  @override
  State<CloudStoragePage> createState() => _CloudStoragePageState();
}

class _CloudStoragePageState extends State<CloudStoragePage> {
  bool _isGrid = false;
  bool _busy = false;
  late List<ProfileInfo> _accounts;

  /// Per-profile connection status, populated by a background probe. Keyed by
  /// profile name. Disabled accounts are marked [AccountStatus.disabled]
  /// without probing.
  final Map<String, AccountStatus> _status = <String, AccountStatus>{};
  final Map<String, String> _statusError = <String, String>{};

  @override
  void initState() {
    super.initState();
    _accounts = List<ProfileInfo>.from(widget.state.profiles);
    _refreshStatus(force: true);
  }

  @override
  void didUpdateWidget(covariant CloudStoragePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final profilesChanged =
        !identical(oldWidget.state.profiles, widget.state.profiles) ||
        oldWidget.state.profiles != widget.state.profiles;
    if (profilesChanged) {
      _accounts = List<ProfileInfo>.from(widget.state.profiles);
      // Preserve existing ok/error statuses across a refresh triggered by a
      // single account toggle/edit so the rest of the list does not flash
      // back to "检测中". Only accounts that are new, removed, or changed
      // disable state get re-probed.
      _refreshStatus();
    }
  }

  /// Probes each enabled account's reachability concurrently by listing its
  /// buckets. This reuses the fast-fail path (3s dial timeout, no SDK retry,
  /// 20s negative cache) so one unreachable account does not slow the page, and
  /// the results seed the shared negative cache so the file manager benefits
  /// too. Disabled accounts are marked without probing.
  ///
  /// Pass [force: true] to drop every cached status and re-probe from scratch
  /// (used on first entry / when the account *set* changes). The default
  /// [force: false] keeps existing ok/error results for accounts whose name did
  /// not change, so toggling one account's disable switch does not flash the
  /// whole list back to "检测中".
  void _refreshStatus({bool force = false}) {
    final liveNames = <String>{};
    for (final account in _accounts) {
      liveNames.add(account.name);
      if (account.disabled) {
        _status[account.name] = AccountStatus.disabled;
        _statusError.remove(account.name);
        continue;
      }
      // Enabled account. Drop any stale "disabled" marker left from a prior
      // state, but preserve an existing ok/error so the row does not flash.
      final existing = _status[account.name];
      final stale =
          force || existing == null || existing == AccountStatus.disabled;
      if (stale) {
        _status[account.name] = AccountStatus.checking;
      }
    }
    // Purge statuses for accounts that no longer exist (deleted/renamed).
    _status.removeWhere((name, _) => !liveNames.contains(name));
    _statusError.removeWhere((name, _) => !liveNames.contains(name));
    final toProbe = _accounts
        .where((a) => !a.disabled && _status[a.name] == AccountStatus.checking)
        .toList();
    if (toProbe.isEmpty) return;
    for (final account in toProbe) {
      unawaited(_probeAccount(account.name));
    }
  }

  Future<void> _probeAccount(String name) async {
    try {
      final config = await widget.api.loadProfile(name);
      // list_buckets walks the full fast-fail path (dial timeout, no retry,
      // negative cache). A short Dart timeout caps the wait for the UI.
      await widget.api
          .listBuckets(config)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw TimeoutException('连接超时'),
          );
      if (!mounted) return;
      setState(() {
        _status[name] = AccountStatus.ok;
        _statusError.remove(name);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status[name] = AccountStatus.error;
        _statusError[name] = describeBridgeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    if (isAndroid) {
      return Padding(
        padding: const EdgeInsets.only(
          top: 28,
          left: 20,
          right: 20,
          bottom: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(theme: theme, onAddAccount: _showAddAccountDialog),
            const SizedBox(height: 14),
            Expanded(
              child: CloudStorageAccountList(
                accounts: _accounts,
                isGrid: false,
                mobileLayout: true,
                busy: _busy,
                onEdit: _showEditAccountDialog,
                onDelete: _delete,
                onManageBuckets: _showBucketVisibilityDialog,
                onToggleDisabled: _toggleDisabled,
                status: _status,
                statusError: _statusError,
                onReorder: null,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(theme: theme, onAddAccount: _showAddAccountDialog),
          const SizedBox(height: 14),
          if (!isAndroid) ...[
            FileManagerActionBar(
              theme: theme,
              isGrid: _isGrid,
              searchEnabled: !_busy,
              onToggleView: () => setState(() => _isGrid = !_isGrid),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: CloudStorageAccountList(
              accounts: _accounts,
              isGrid: _isGrid,
              mobileLayout: false,
              busy: _busy,
              onEdit: _showEditAccountDialog,
              onDelete: _delete,
              onManageBuckets: _showBucketVisibilityDialog,
              onToggleDisabled: _toggleDisabled,
              status: _status,
              statusError: _statusError,
              onReorder: _isGrid ? null : _reorderAccounts,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(ProfileInfo profile) async {
    setState(() => _busy = true);
    try {
      final result =
          await widget.api.deleteProfile(profile.name) as Map<String, dynamic>?;
      if (!mounted) return;
      final cascade = (result?['cascade'] ?? '').toString();
      final message = cascade.isEmpty
          ? _profileTitle(profile)
          : '${_profileTitle(profile)} $cascade';
      showAppToast(context, title: '账号已退出', message: message);
      widget.onRefresh();
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleDisabled(ProfileInfo profile, bool disabled) async {
    setState(() => _busy = true);
    try {
      final config = await widget.api.loadProfile(profile.name);
      await widget.api.saveProfile(
        profile.name,
        config.copyWith(disabled: disabled),
      );
      if (!mounted) return;
      showAppToast(
        context,
        title: disabled ? '账号已禁用' : '账号已启用',
        message: _profileTitle(profile),
      );
      widget.onRefresh();
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reorderAccounts(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _accounts.length) {
      return;
    }
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 || targetIndex >= _accounts.length) {
      return;
    }
    final previous = List<ProfileInfo>.from(_accounts);
    final accounts = List<ProfileInfo>.from(_accounts);
    final moved = accounts.removeAt(oldIndex);
    accounts.insert(targetIndex, moved);
    final names = accounts
        .map((profile) => profile.name)
        .toList(growable: false);
    setState(() => _accounts = accounts);
    try {
      // Order is already persisted; avoid bootstrap/onRefresh which used to
      // flash the whole app shell while FutureBuilder reloaded.
      await widget.api.reorderProfiles(names);
    } catch (error) {
      if (!mounted) return;
      setState(() => _accounts = previous);
      showAppErrorToast(context, message: error.toString());
    }
  }

  Future<void> _showAddAccountDialog() async {
    await showAccountEditor(
      context: context,
      api: widget.api,
      onSaved: widget.onRefresh,
      onSave: _saveNewAccount,
      onStartBaiduPanAuthorization: _startBaiduPanAuthorization,
      onAuthorizeBaiduPan: _authorizeBaiduPan,
    );
  }

  Future<void> _showEditAccountDialog(ProfileInfo profile) async {
    setState(() => _busy = true);
    try {
      final config = await widget.api.loadProfile(profile.name);
      if (!mounted) return;
      setState(() => _busy = false);
      await showAccountEditor(
        context: context,
        api: widget.api,
        initialConfig: config,
        profileName: profile.name,
        editing: true,
        onSaved: widget.onRefresh,
        onSave: (cfg) => _saveEditedAccount(profile, cfg),
        onStartBaiduPanAuthorization: _startBaiduPanAuthorization,
        onAuthorizeBaiduPan: _authorizeBaiduPan,
      );
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _showBucketVisibilityDialog(ProfileInfo profile) async {
    setState(() => _busy = true);
    try {
      final config = await widget.api.loadProfile(profile.name);
      if (!mounted) return;
      setState(() => _busy = false);
      await showBucketVisibilityDialog(
        context: context,
        api: widget.api,
        config: config,
        profileName: profile.name,
        onSave: (views) => _saveBucketViews(profile, views),
      );
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<bool> _saveBucketViews(
    ProfileInfo profile,
    Map<String, BucketViewSettings> views,
  ) async {
    setState(() => _busy = true);
    try {
      final config = await widget.api.loadProfile(profile.name);
      final updated = config.copyWith(bucketViews: views);
      await widget.api.saveProfile(profile.name, updated);
      if (!mounted) return false;
      widget.onRefresh();
      return true;
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
      return false;
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<bool> _saveNewAccount(RemoteStorageConfig config) async {
    if (!config.isConfigured) {
      showAppErrorToast(
        context,
        message: config.storageType == StorageType.baiduPan
            ? '请先完成百度网盘 OAuth 授权。'
            : config.storageType == StorageType.webdav
            ? '请填写 WebDAV 地址、用户名和密码。'
            : config.storageType == StorageType.ftp ||
                  config.storageType == StorageType.sftp
            ? '请填写 FTP/SFTP 地址、用户名和密码。'
            : '请填写 Endpoint、Access Key 和 Secret Key。',
      );
      return false;
    }
    setState(() => _busy = true);
    try {
      await widget.api.saveProfile(
        generateAccountProfileName(config.displayName, config.storageType),
        config,
      );
      if (!mounted) return false;
      showAppToast(context, title: '账号已保存', message: config.displayName);
      widget.onRefresh();
      return true;
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _saveEditedAccount(
    ProfileInfo profile,
    RemoteStorageConfig config,
  ) async {
    if (!config.isConfigured) {
      showAppErrorToast(context, message: '请补全账号连接信息。');
      return false;
    }
    setState(() => _busy = true);
    try {
      await widget.api.saveProfile(profile.name, config);
      if (!mounted) return false;
      showAppToast(context, title: '账号已更新', message: config.displayName);
      widget.onRefresh();
      return true;
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _startBaiduPanAuthorization() async {
    setState(() => _busy = true);
    try {
      return await widget.api.startBaiduPanAuthorization();
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<RemoteStorageConfig> _authorizeBaiduPan(
    String displayName,
    String code,
  ) async {
    setState(() => _busy = true);
    try {
      return await widget.api.authorizeBaiduPan(displayName, code);
    } catch (error) {
      if (mounted) showAppErrorToast(context, message: error.toString());
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _profileTitle(ProfileInfo profile) {
    return profile.displayName.isEmpty ? profile.name : profile.displayName;
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.theme, required this.onAddAccount});

  final ShadThemeData theme;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '账号管理',
            style: theme.textTheme.h3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ShadButton(onPressed: onAddAccount, child: const Text('新增账号')),
      ],
    );
  }
}
