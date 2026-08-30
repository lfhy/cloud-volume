// ignore_for_file: library_private_types_in_public_api
part of 'cloud_storage_account_dialog.dart';

// ---------------------------------------------------------------------------
// Step 1 — Protocol picker: large selectable cards for S3 / WebDAV / Baidu Pan
// ---------------------------------------------------------------------------

/// 步骤 1「选择接入协议」的卡片列表。每个协议显示图标 + 名称 + 简短说明。
Widget stepProtocolPicker({
  required ShadThemeData theme,
  required _CloudStorageAccountDialogState self,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final type in StorageType.values) ...[
        StorageProtocolCard(
          type: type,
          selected: self._storageType == type,
          onTap: () => self.markDirty(() => self._storageType = type),
        ),
        if (type != StorageType.values.last) const SizedBox(height: 10),
      ],
    ],
  );
}

/// 协议选择卡片：hover 高亮、选中时 primary 边框 + 淡色底。
class StorageProtocolCard extends StatefulWidget {
  const StorageProtocolCard({
    super.key,
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final StorageType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<StorageProtocolCard> createState() => _StorageProtocolCardState();
}

class _StorageProtocolCardState extends State<StorageProtocolCard> {
  // Hover must live on this State (not an inline builder). See AGENTS.md
  // "Hover-aware clickable rows" binding rule.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final interaction = ListInteractionColors.fromTheme(theme);
    // Fixed border width avoids layout jump under content-fit measurement.
    const borderWidth = 1.0;
    // Hover is a neutral wash only — same family as file-list rows.
    // Do NOT switch to primary border / secondary blue fill / blue icon on
    // hover; that reads as a different component style, not a hover state.
    final borderColor = widget.selected
        ? theme.colorScheme.primary
        : theme.colorScheme.border;
    final bg = interaction.rowBackground(
      selected: widget.selected,
      hovered: _hovered,
      pressed: false,
    );
    final iconColor = widget.selected
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Row(
            children: [
              Icon(_iconFor(widget.type), size: 22, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.type.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _descriptionFor(widget.type),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              // Reserve checkmark width so select does not reflow card height.
              SizedBox(
                width: 18,
                child: widget.selected
                    ? Icon(
                        LucideIcons.check,
                        size: 18,
                        color: theme.colorScheme.primary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(StorageType type) {
    return switch (type) {
      StorageType.s3 => LucideIcons.database,
      StorageType.webdav => LucideIcons.folderOpen,
      StorageType.baiduPan => LucideIcons.cloud,
      StorageType.ftp => LucideIcons.server,
      StorageType.sftp => LucideIcons.shield,
    };
  }

  static String _descriptionFor(StorageType type) {
    return switch (type) {
      StorageType.s3 => 'Amazon S3、MinIO 及兼容的对象存储服务',
      StorageType.webdav => '通过 WebDAV 协议挂载的远端文件服务',
      StorageType.baiduPan => '使用百度网盘 OAuth 授权接入个人网盘',
      StorageType.ftp => '连接经典 FTP 服务器进行文件传输',
      StorageType.sftp => '通过 SSH 隧道安全传输文件',
    };
  }
}

// ---------------------------------------------------------------------------
// Step 2 — Connection fields: name + protocol-specific details + proxy
// ---------------------------------------------------------------------------

/// 步骤 2「配置连接信息」：只保留主连接字段；路径风格 / 代理放进二级「高级设置」弹窗。
/// simpleMode 跳过名称和映射桶名称，只保留连接凭证 + endpoint。
Widget stepConnectionFields({
  required ShadThemeData theme,
  required _CloudStorageAccountDialogState self,
}) {
  final isWebDav = self._storageType == StorageType.webdav;
  final isBaiduPan = self._storageType == StorageType.baiduPan;
  final isFTP =
      self._storageType == StorageType.ftp ||
      self._storageType == StorageType.sftp;
  final simple = self.widget.simpleMode;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Name + mapped-bucket fields are hidden in simple (backup-only) mode.
      if (!simple) ...[
        CloudStorageLabeledField(
          label: '名称',
          child: ShadInput(
            controller: self._nameController,
            placeholder: Text(
              isBaiduPan
                  ? '例如：我的百度网盘'
                  : isWebDav
                  ? '例如：IHEP WebDAV'
                  : isFTP
                  ? '例如：我的 FTP 服务器'
                  : '例如：对象存储账号',
            ),
            onChanged: (_) => self._syncMappedBucketName(),
          ),
        ),
        if (isWebDav || isFTP) ...[
          const SizedBox(height: 14),
          CloudStorageLabeledField(
            label: '映射桶名称',
            child: ShadInput(
              controller: self._mappedBucketNameController,
              placeholder: const Text('默认使用名称'),
              onChanged: (_) => self._mappedBucketNameEdited = true,
            ),
          ),
        ],
        const SizedBox(height: 14),
      ],
      if (isBaiduPan) ..._baiduPanFields(self),
      if (!isBaiduPan && !isWebDav && !isFTP) ..._s3Fields(self),
      if (!isBaiduPan && isWebDav) ..._webdavFields(self),
      if (!isBaiduPan && isFTP) ..._ftpFields(self),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () => _openAccountAdvancedSettings(self),
          child: const Text('高级设置…'),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        isBaiduPan || isWebDav || isFTP
            ? '代理等可选项在高级设置中配置。'
            : '路径风格访问、代理等可选项在高级设置中配置。',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    ],
  );
}

Future<void> _openAccountAdvancedSettings(
  _CloudStorageAccountDialogState self,
) async {
  final isS3 = self._storageType == StorageType.s3;
  var usePathStyle = self._usePathStyle;
  var proxyMode = self._proxyMode;
  var proxyType = self._proxyType;

  await showAppModal<void>(
    context: self.context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AppShadDialog(
            title: const Text('高级设置'),
            description: Text(isS3 ? '路径风格访问与此账号的代理策略。' : '此账号的代理策略。'),
            constraints: const BoxConstraints(maxWidth: 480),
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isS3) ...[
                    _S3AdvancedOptions(
                      usePathStyle: usePathStyle,
                      onPathStyleChanged: (value) =>
                          setDialogState(() => usePathStyle = value),
                    ),
                    const SizedBox(height: 16),
                  ],
                  AccountProxySection(
                    initialMode: proxyMode,
                    initialType: proxyType,
                    hostController: self._proxyHostController,
                    portController: self._proxyPortController,
                    usernameController: self._proxyUsernameController,
                    passwordController: self._proxyPasswordController,
                    onModeChanged: (value) {
                      proxyMode = value;
                      setDialogState(() {});
                    },
                    onTypeChanged: (value) {
                      proxyType = value;
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ShadButton.outline(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('取消'),
                      ),
                      ShadButton(
                        onPressed: () {
                          self.markDirty(() {
                            self._usePathStyle = usePathStyle;
                            self._proxyMode = proxyMode;
                            self._proxyType = proxyType;
                          });
                          Navigator.of(dialogContext).pop();
                        },
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Two equal columns with a fixed gutter for wider account forms.
Widget _twoColumnRow({required Widget left, required Widget right}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 480) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 14), right],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 14),
          Expanded(child: right),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// S3 advanced options (path-style toggle)
// ---------------------------------------------------------------------------

class _S3AdvancedOptions extends StatelessWidget {
  const _S3AdvancedOptions({
    required this.usePathStyle,
    required this.onPathStyleChanged,
  });

  final bool usePathStyle;
  final ValueChanged<bool> onPathStyleChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ShadSwitch(
        value: usePathStyle,
        onChanged: onPathStyleChanged,
        label: Text(
          '使用路径风格访问',
          style: theme.textTheme.small.copyWith(
            color: theme.colorScheme.foreground,
            fontWeight: FontWeight.w500,
          ),
        ),
        sublabel: Text(
          '推荐用于 MinIO、私有 S3 和多数兼容对象存储。',
          style: TextStyle(
            color: theme.colorScheme.mutedForeground,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
