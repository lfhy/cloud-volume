part of 'settings_page.dart';

// Layout helpers for the settings page's left-side group rail and right-side
// content area. Extracted from settings_page.dart to keep the main file under
// the 500-line limit.

/// A labelled group of anchors shown as a section header + tile list.
class _SettingsRailGroup {
  const _SettingsRailGroup({required this.header, required this.tabs});

  final String header;
  final List<_SettingsTab> tabs;
}

/// Vertical anchor rail with section headers. Each group (常规 / 网络 / 存储 /
/// 账号 / Windows / 关于) gets a muted header label followed by anchor tiles.
extension _SettingsLayout on _SettingsPageState {
  /// Builds the ordered group list, conditionally including platform groups.
  List<_SettingsRailGroup> _railGroups() {
    return [
      _SettingsRailGroup(
        header: '常规',
        tabs: [
          _SettingsTab.update,
          _SettingsTab.appearance,
          _SettingsTab.logging,
          // 移动端专属:底部导航自定义(仅 Android)。
          if (defaultTargetPlatform == TargetPlatform.android)
            _SettingsTab.mobileNav,
        ],
      ),
      _SettingsRailGroup(
        header: '网络',
        tabs: [
          _SettingsTab.proxy,
          if (isWebPlatform) _SettingsTab.webdav,
          if (!isWebPlatform) _SettingsTab.p2p,
        ],
      ),
      _SettingsRailGroup(
        header: '存储',
        tabs: [
          if (widget.api.capabilities.supportsDownloadDirectory)
            _SettingsTab.download,
          _SettingsTab.cache,
          _SettingsTab.visibility,
          _SettingsTab.sync,
          _SettingsTab.trash,
        ],
      ),
      _SettingsRailGroup(
        header: '账号',
        tabs: [
          _SettingsTab.resetAccount,
          if (!isWebPlatform) _SettingsTab.configBackup,
          _SettingsTab.configManage,
        ],
      ),
      if (_showsWindowsTab)
        _SettingsRailGroup(
          header: 'Windows',
          tabs: [_SettingsTab.windowsWriteback, _SettingsTab.windowsMount],
        ),
      _SettingsRailGroup(header: '关于', tabs: [_SettingsTab.about]),
    ];
  }

  Widget _buildGroupRail(ShadThemeData theme) {
    final groups = _railGroups();
    final children = <Widget>[];
    for (final group in groups) {
      children.add(_railHeader(theme, group.header));
      for (final tab in group.tabs) {
        children.add(_buildGroupTile(theme, tab));
        children.add(const SizedBox(height: 2));
      }
      children.add(const SizedBox(height: 16));
    }
    // Remove trailing spacer
    if (children.isNotEmpty) children.removeLast();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _railHeader(ShadThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6, left: 14),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }

  /// A single clickable group entry in the left rail.
  ///
  /// Delegates to [_SettingsGroupTile], a StatefulWidget, so hover state is
  /// tracked and rebuilt correctly (see the class doc for why an extension
  /// cannot own hover state).
  Widget _buildGroupTile(ShadThemeData theme, _SettingsTab tab) {
    // No persistent active state: clicking a rail entry only scrolls the page,
    // so no entry is ever rendered as selected.
    return _SettingsGroupTile(
      accent: theme.colorScheme.accent,
      foreground: theme.colorScheme.foreground,
      mutedForeground: theme.colorScheme.mutedForeground,
      label: _tabLabel(tab),
      onTap: () => _scrollToAnchor(tab),
    );
  }

  /// Human-readable label for each tab.
  String _tabLabel(_SettingsTab tab) {
    return switch (tab) {
      _SettingsTab.update => '应用更新',
      _SettingsTab.mobileNav => '底部导航',
      _SettingsTab.proxy => '网络代理',
      _SettingsTab.appearance => '外观',
      _SettingsTab.logging => '日志设置',
      _SettingsTab.download => '下载设置',
      _SettingsTab.cache => '缓存设置',
      _SettingsTab.visibility => '显示设置',
      _SettingsTab.sync => '同步设置',
      _SettingsTab.trash => '回收站',
      _SettingsTab.webdav => 'WebDAV 凭据',
      _SettingsTab.p2p => '局域网同步',
      _SettingsTab.resetAccount => '账号重置',
      _SettingsTab.configBackup => '配置备份',
      _SettingsTab.configManage => '配置管理',
      _SettingsTab.windowsWriteback => '写回并发',
      _SettingsTab.windowsMount => '挂载恢复',
      _SettingsTab.about => '关于云卷',
    };
  }

  /// Builds all visible cards as one long scrollable page, keyed by tab so the
  /// left rail can jump to each card as an anchor.
  List<Widget> _buildAllContent(
    ShadThemeData theme,
    RemoteStorageConfig config,
  ) {
    final content = <Widget>[];
    for (final group in _railGroups()) {
      for (final tab in group.tabs) {
        content.add(
          KeyedSubtree(
            key: _sectionKeys[tab],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildContentForTab(theme, config, tab),
            ),
          ),
        );
        content.add(const SizedBox(height: 20));
      }
    }
    if (content.isNotEmpty) content.removeLast();
    return content;
  }

  List<Widget> _buildContentForTab(
    ShadThemeData theme,
    RemoteStorageConfig config,
    _SettingsTab tab,
  ) {
    switch (tab) {
      case _SettingsTab.update:
        return _buildUpdateSection(theme, config);
      case _SettingsTab.proxy:
        return _buildProxySection(theme, config);
      case _SettingsTab.appearance:
        return _buildAppearanceSection(theme);
      case _SettingsTab.mobileNav:
        return _buildMobileNavSection(theme);
      case _SettingsTab.logging:
        return _buildLogSection(theme);
      case _SettingsTab.download:
        return _buildDownloadSection(theme, config);
      case _SettingsTab.cache:
        return _buildCacheSection(theme, config);
      case _SettingsTab.visibility:
        return _buildVisibilitySection(theme, config);
      case _SettingsTab.sync:
        return _buildSyncSection(theme, config);
      case _SettingsTab.trash:
        return _buildTrashSection(theme, config);
      case _SettingsTab.webdav:
        return _buildWebdavSection(theme, config);
      case _SettingsTab.p2p:
        return _buildP2PSection(theme, config);
      case _SettingsTab.resetAccount:
        return _buildResetAccountSection(theme);
      case _SettingsTab.configBackup:
        return _buildConfigBackupSection(theme);
      case _SettingsTab.configManage:
        return _buildConfigManageSection(theme);
      case _SettingsTab.windowsWriteback:
        return _buildWindowsWritebackSection(theme, config);
      case _SettingsTab.windowsMount:
        return _buildWindowsMountSection(theme, config);
      case _SettingsTab.about:
        return _buildAboutSection(theme);
    }
  }

  void _scrollToAnchor(_SettingsTab tab) {
    final context = _sectionKeys[tab]?.currentContext;
    if (context == null) return;
    // Clicking a left rail entry only scrolls the page; no persistent active
    // highlight. Scroll position also no longer syncs rail highlight.
    Scrollable.ensureVisible(
      context,
      alignment: 0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }
}

/// Self-contained hover-aware navigation tile for the settings group rail.
///
/// Hover handling follows the project-wide pattern (see `_SidebarNavItem` in
/// desktop_sidebar.dart): a StatefulWidget holds a `_hovered` flag that is
/// toggled by [MouseRegion.onEnter] / [MouseRegion.onExit] and drives
/// background color, text color, and cursor via an [AnimatedContainer].
///
/// **Why this must be a StatefulWidget, not inline in an extension:**
/// an `extension on _SettingsPageState` can read and call methods on the
/// State, but it has *no place to store mutable fields*. Wrapping a
/// `MouseRegion(onEnter/onExit: ...)` whose callback needs to toggle a flag
/// and rebuild has nowhere to put that flag — the callbacks would either be
/// no-ops or require reaching back into the host State's private fields,
/// which is fragile. Every hover-aware clickable row in this codebase
/// (`_SidebarNavItem`, `FileListTile`, `TransferTaskRow`, …) is a dedicated
/// StatefulWidget for exactly this reason.
class _SettingsGroupTile extends StatefulWidget {
  const _SettingsGroupTile({
    required this.accent,
    required this.foreground,
    required this.mutedForeground,
    required this.label,
    required this.onTap,
  });

  final Color accent;
  final Color foreground;
  final Color mutedForeground;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SettingsGroupTile> createState() => _SettingsGroupTileState();
}

class _SettingsGroupTileState extends State<_SettingsGroupTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ac = widget.accent;

    final fg = _hovered ? ac.withValues(alpha: 0.9) : widget.mutedForeground;
    final baseBg = Colors.transparent;
    final hoverOverlay = ac.withValues(alpha: _hovered ? 0.1 : 0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // Idle cursor stays as the basic arrow so it does not get stuck on a
      // pointing hand inherited from an ancestor (project convention).
      cursor: _hovered ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: Color.alphaBlend(hoverOverlay, baseBg),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
