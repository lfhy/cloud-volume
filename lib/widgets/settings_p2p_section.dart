// P2P 局域网同步设置区：显示开关、分块大小配置、已发现的局域网设备列表。
// 开关切换后自动保存到配置并通知 Go 侧启用/禁用 P2P。
// 设备列表通过定时轮询 bridge get_p2p_status 获取。
// 视觉规范与其他设置卡片一致：顶部说明文字 + secondary 容器，
// 不使用 textTheme.h4，避免与其他卡片的字体系统割裂。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// P2P 设置卡片：展示局域网同步开关、分块大小和已发现设备。
class SettingsP2PSection extends StatefulWidget {
  const SettingsP2PSection({
    super.key,
    required this.theme,
    required this.config,
    required this.api,
    required this.onSaveConfig,
  });

  final ShadThemeData theme;
  final RemoteStorageConfig config;
  final RemoteStorageGateway api;
  final Future<void> Function(RemoteStorageConfig) onSaveConfig;

  @override
  State<SettingsP2PSection> createState() => _SettingsP2PSectionState();
}

class _SettingsP2PSectionState extends State<SettingsP2PSection> {
  Timer? _pollTimer;
  List<_PeerInfo> _peers = [];
  String? _deviceId;
  bool _loadingPeers = false;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    if (widget.config.p2pEnabled) {
      _startPolling();
    }
  }

  @override
  void didUpdateWidget(covariant SettingsP2PSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.p2pEnabled != widget.config.p2pEnabled) {
      if (widget.config.p2pEnabled) {
        _startPolling();
      } else {
        _stopPolling();
        setState(() => _peers = []);
      }
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _stopPolling();
    _fetchStatus();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchStatus(),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetchStatus() async {
    if (_loadingPeers) return;
    setState(() => _loadingPeers = true);
    try {
      final data = await widget.api.getP2PStatus();
      if (!mounted) return;
      final peersList = data['peers'] as List? ?? [];
      setState(() {
        _deviceId = data['deviceId'] as String?;
        _peers = peersList
            .map(
              (p) => _PeerInfo(
                deviceId: p['deviceId'] as String? ?? '',
                addr: p['addr'] as String? ?? '',
                lastSeen: p['lastSeen'] as String? ?? '',
                accounts:
                    (p['accounts'] as List?)?.cast<String>() ?? const [],
              ),
            )
            .toList();
        _loadingPeers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPeers = false);
    }
  }

  Future<void> _toggleP2P(bool enabled) async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      await widget.onSaveConfig(widget.config.copyWith(p2pEnabled: enabled));
      await widget.api.setP2PEnabled(enabled);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _saveChunkSize(int mb) async {
    await widget.onSaveConfig(widget.config.copyWith(p2pChunkSizeMb: mb));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled = widget.config.p2pEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '自动发现同账号的局域网设备，加速文件刷新和读取；关闭后回退到直接访问远端。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 8),
        // 实验功能标识：P2P 默认关闭，仅在调测阶段开放给需要的用户。
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.muted,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '实验功能 · 默认关闭',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _EnableP2PBlock(
          theme: theme,
          enabled: enabled,
          toggling: _toggling,
          onChanged: _toggleP2P,
        ),
        if (enabled) ...[
          const SizedBox(height: 18),
          _SectionHeader(
            theme: theme,
            title: '传输分块大小',
            description: '较大的分块可提高吞吐量，较小则降低内存占用。',
          ),
          const SizedBox(height: 10),
          _buildChunkSizeSelect(theme),
          const SizedBox(height: 18),
          _SectionHeader(
            theme: theme,
            title: '已发现设备',
            description: '同账号的局域网设备会定时刷新；设备离线后自动消失。',
          ),
          const SizedBox(height: 10),
          _buildPeersList(theme),
        ],
      ],
    );
  }

  Widget _buildChunkSizeSelect(ShadThemeData theme) {
    final chunkSize = widget.config.effectiveP2PChunkSizeMb;
    return SizedBox(
      width: double.infinity,
      child: ShadSelect<int>(
        key: ValueKey<int>(chunkSize),
        initialValue: chunkSize,
        minWidth: 220,
        options: const [1, 2, 4, 8, 16, 32, 64].map((v) {
          return ShadOption(value: v, child: Text('$v MB'));
        }).toList(),
        selectedOptionBuilder: (context, value) => Text('$value MB'),
        onChanged: (value) {
          if (value != null) _saveChunkSize(value);
        },
      ),
    );
  }

  Widget _buildPeersList(ShadThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.monitorSmartphone,
                size: 15,
                color: theme.colorScheme.mutedForeground,
              ),
              const SizedBox(width: 6),
              Text(
                _peers.isEmpty ? '暂无已发现设备' : '共发现 ${_peers.length} 台设备',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.foreground,
                ),
              ),
              const Spacer(),
              if (_deviceId != null)
                Text(
                  '本机: $_deviceId',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_peers.isEmpty && !_loadingPeers)
            Text(
              '正在搜索局域网中的设备…',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.mutedForeground,
              ),
            )
          else if (_peers.isEmpty && _loadingPeers)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: AppLoadingIndicator(size: 15, strokeWidth: 2),
            )
          else
            ..._peers.map((p) => _PeerRow(peer: p, theme: theme)),
        ],
      ),
    );
  }
}

/// 分组标题 + 说明文字，与其他设置卡片（缓存、同步、回收站）一致。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.theme,
    required this.title,
    required this.description,
  });

  final ShadThemeData theme;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 11.5,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ],
    );
  }
}

/// secondary 容器包裹的开关行，风格对齐「同步设置 → 启用元数据缓存」。
class _EnableP2PBlock extends StatelessWidget {
  const _EnableP2PBlock({
    required this.theme,
    required this.enabled,
    required this.toggling,
    required this.onChanged,
  });

  final ShadThemeData theme;
  final bool enabled;
  final bool toggling;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '启用局域网同步',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  enabled ? '已启用，正在监听局域网设备' : '已关闭，仅通过远端同步',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          ShadSwitch(value: enabled, onChanged: toggling ? null : onChanged),
        ],
      ),
    );
  }
}

/// 内部数据模型：保存 mDNS/轮询返回的对端设备信息。
class _PeerInfo {
  final String deviceId;
  final String addr;
  final String lastSeen;
  final List<String> accounts;

  _PeerInfo({
    required this.deviceId,
    required this.addr,
    required this.lastSeen,
    this.accounts = const [],
  });
}

/// 单个已发现设备行：设备图标 + 设备 ID/地址 + 在线状态点。
class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.peer, required this.theme});

  final _PeerInfo peer;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            LucideIcons.laptop,
            size: 15,
            color: theme.colorScheme.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer.deviceId,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  peer.addr,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
                if (peer.accounts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '共享账号：${peer.accounts.join('、')}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '在线',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
