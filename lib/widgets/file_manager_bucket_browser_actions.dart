part of 'file_manager_bucket_browser.dart';

// Bucket browser action cells keep mount/unmount controls separate from list layout code.

class _BucketMenuAction {
  const _BucketMenuAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class _BucketMountActions extends StatelessWidget {
  const _BucketMountActions({
    required this.bucket,
    required this.status,
    required this.busy,
    required this.onMountBucket,
    required this.onUnmountBucket,
    required this.onOpenMountedBucket,
    required this.onConfigureBucket,
    required this.moreMenuItems,
    this.showInlineConfigure = true,
  });

  final FileManagerBucketEntry bucket;
  final BucketMountStatus? status;
  final bool busy;
  final ValueChanged<FileManagerBucketEntry>? onMountBucket;
  final ValueChanged<FileManagerBucketEntry>? onUnmountBucket;
  final ValueChanged<FileManagerBucketEntry>? onOpenMountedBucket;
  final ValueChanged<FileManagerBucketEntry>? onConfigureBucket;
  final List<Widget> moreMenuItems;
  final bool showInlineConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final mounted = status?.mounted ?? false;
    final foreground = theme.colorScheme.primary;
    final primaryAction = mounted ? onOpenMountedBucket : onMountBucket;
    final primaryLabel = mounted ? '打开目录' : '挂载';
    final primaryIcon = mounted ? LucideIcons.folderOpen : LucideIcons.link;
    final secondaryAction = mounted
        ? onUnmountBucket
        : showInlineConfigure
        ? onConfigureBucket
        : null;
    final secondaryLabel = mounted ? '卸载' : '配置';
    final secondaryIcon = mounted ? LucideIcons.x : LucideIcons.settings2;
    final statusError = status?.lastError?.trim() ?? '';

    if (busy) {
      return SizedBox(
        height: 32,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusError.isNotEmpty) ...[
              _iconOnlySlot(
                _errorIndicator(statusError, theme.colorScheme.destructive),
              ),
              const SizedBox(width: 4),
            ],
            _iconOnlySlot(
              SizedBox(
                width: 12,
                height: 12,
                child: AppLoadingIndicator(strokeWidth: 1.5, color: foreground),
              ),
            ),
            const SizedBox(width: 4),
            _iconOnlySlot(
              _iconButton(
                tooltip: secondaryLabel,
                icon: secondaryIcon,
                color: foreground,
                onPressed: null,
              ),
            ),
            const SizedBox(width: 4),
            _BucketOverflowMenuButton(
              items: moreMenuItems,
              color: foreground,
              enabled: false,
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (statusError.isNotEmpty) ...[
            _iconOnlySlot(
              _errorIndicator(statusError, theme.colorScheme.destructive),
            ),
            const SizedBox(width: 4),
          ],
          if (primaryAction != null) ...[
            _iconOnlySlot(
              _iconButton(
                tooltip: primaryLabel,
                icon: primaryIcon,
                color: foreground,
                onPressed: () => primaryAction(bucket),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (secondaryAction != null) ...[
            _iconOnlySlot(
              _iconButton(
                tooltip: secondaryLabel,
                icon: secondaryIcon,
                color: foreground,
                onPressed: () => secondaryAction(bucket),
              ),
            ),
            const SizedBox(width: 4),
          ],
          _BucketOverflowMenuButton(
            items: moreMenuItems,
            color: foreground,
            enabled: moreMenuItems.isNotEmpty,
          ),
        ],
      ),
    );
  }

  Widget _iconOnlySlot(Widget child) {
    return SizedBox(
      width: 32,
      child: Align(alignment: Alignment.center, child: child),
    );
  }

  Widget _errorIndicator(String message, Color color) {
    return AppTooltip(
      message: message,
      child: Icon(LucideIcons.circleAlert, size: 15, color: color),
    );
  }

  Widget _iconButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return AppTooltip(
      message: tooltip,
      child: ShadIconButton.ghost(
        icon: Icon(icon, size: 14, color: color),
        width: 26,
        height: 26,
        iconSize: 14,
        onPressed: onPressed,
      ),
    );
  }
}

class _BucketOverflowMenuButton extends StatefulWidget {
  const _BucketOverflowMenuButton({
    required this.items,
    required this.color,
    required this.enabled,
    this.mobile = false,
    this.mobileActions = const <_BucketMenuAction>[],
    this.bucketLabel = '',
  });

  final List<Widget> items;
  final Color color;
  final bool enabled;
  final bool mobile;
  final List<_BucketMenuAction> mobileActions;
  final String bucketLabel;

  @override
  State<_BucketOverflowMenuButton> createState() =>
      _BucketOverflowMenuButtonState();
}

class _BucketOverflowMenuButtonState extends State<_BucketOverflowMenuButton> {
  final GlobalKey _buttonKey = GlobalKey();
  late final ShadContextMenuController _controller;
  Offset? _menuAnchorOffset;

  @override
  void initState() {
    super.initState();
    _controller = ShadContextMenuController();
    _controller.addListener(_syncActiveController);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncActiveController);
    DesktopContextMenuRegistry.deactivate(_bucketContextMenuGroup, _controller);
    _controller.dispose();
    super.dispose();
  }

  void _syncActiveController() {
    if (_controller.isOpen) {
      DesktopContextMenuRegistry.activate(_bucketContextMenuGroup, _controller);
      return;
    }
    DesktopContextMenuRegistry.deactivate(_bucketContextMenuGroup, _controller);
  }

  /// 再次点击「更多」图标时收起菜单（与行点击 dismiss 行为一致）。
  void _toggleMenu() {
    if (!widget.enabled || widget.items.isEmpty) {
      return;
    }
    if (_controller.isOpen) {
      _controller.hide();
      return;
    }
    final buttonContext = _buttonKey.currentContext;
    if (!mounted || buttonContext == null) {
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    setState(() {
      _menuAnchorOffset = topLeft + Offset(0, box.size.height + 4);
    });
    _controller.show();
  }

  Future<void> _showMobileMenu() async {
    if (!widget.enabled || widget.mobileActions.isEmpty) return;
    await showAppModal<void>(
      context: context,
      builder: (dialogContext) => AppShadDialog(
        title: Text(widget.bucketLabel),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final action in widget.mobileActions) ...[
              ShadButton.ghost(
                width: double.infinity,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  action.onPressed();
                },
                child: SizedBox(
                  width: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(action.icon, size: 17),
                      ),
                      Text(action.label),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobile) {
      // Touch tooltips toggle Shad's hover state on tap, which can outlive
      // the bottom sheet. The sheet already names every action; keep only an
      // accessibility label around the 48dp button.
      return Semantics(
        label: '更多操作',
        child: ShadIconButton.ghost(
          icon: Icon(
            LucideIcons.ellipsisVertical,
            size: 18,
            color: widget.color,
          ),
          width: 48,
          height: 48,
          iconSize: 18,
          onPressed: widget.enabled ? _showMobileMenu : null,
        ),
      );
    }
    return ShadContextMenu(
      anchor: _menuAnchorOffset == null
          ? null
          : ShadGlobalAnchor(_menuAnchorOffset!),
      controller: _controller,
      constraints: const BoxConstraints(minWidth: 164),
      effects: const [],
      popoverReverseDuration: Duration.zero,
      items: widget.items,
      child: KeyedSubtree(
        key: _buttonKey,
        child: ShadIconButton.ghost(
          icon: Icon(
            LucideIcons.ellipsisVertical,
            size: 13,
            color: widget.color,
          ),
          width: 26,
          height: 26,
          iconSize: 13,
          onPressed: widget.enabled ? _toggleMenu : null,
        ),
      ),
    );
  }
}
