// ignore_for_file: library_private_types_in_public_api
// Step 3 of the new-account wizard: per-bucket visibility + presentation.
// Uses a hand-rolled check box (Container + Lucide check) instead of
// Material's Checkbox, because this step renders inside a ShadDialog whose
// subtree has no Material ancestor — Material Checkbox would throw
// "No Material widget found" here. The look matches StorageProtocolCard.
//
// This file is `part of` the account dialog so stepBucketVisibility and the
// _BucketVisibilityRow can access the dialog's private state. The public
// `BucketSelectionCheckbox` widget is also imported by the standalone
// bucket-visibility dialog (bucket_visibility_dialog.dart) so both entry
// points share the exact same checkbox styling.
part of 'cloud_storage_account_dialog.dart';

// Step 3 keeps the allowlist and per-bucket presentation choices together.
Widget stepBucketVisibility({
  required ShadThemeData theme,
  required _CloudStorageAccountDialogState self,
}) {
  if (self._loadingBuckets) {
    return const Center(child: AppLoadingIndicator());
  }
  final all = self._availableBuckets;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '桶列表显示设置',
        style: theme.textTheme.h4.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        '不选择任何桶表示动态显示全部桶，之后新增的桶也会自动出现。选择后将只显示选中的桶。',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
      const SizedBox(height: 14),
      if (all.isEmpty)
        Text('当前账号没有可用桶。', style: theme.textTheme.small)
      else
        for (final bucket in all) ...[
          _BucketVisibilityRow(bucket: bucket, self: self),
          if (bucket != all.last) const SizedBox(height: 8),
        ],
    ],
  );
}

class _BucketVisibilityRow extends StatefulWidget {
  const _BucketVisibilityRow({required this.bucket, required this.self});

  final BucketInfo bucket;
  final _CloudStorageAccountDialogState self;

  @override
  State<_BucketVisibilityRow> createState() => _BucketVisibilityRowState();
}

class _BucketVisibilityRowState extends State<_BucketVisibilityRow> {
  late final TextEditingController _displayController;
  late final TextEditingController _prefixController;

  bool get selected => widget.self._bucketViews.containsKey(widget.bucket.name);

  @override
  void initState() {
    super.initState();
    final view = widget.self._bucketViews[widget.bucket.name];
    _displayController = TextEditingController(text: view?.displayName ?? '');
    _prefixController = TextEditingController(text: view?.rootPrefix ?? '');
  }

  @override
  void didUpdateWidget(covariant _BucketVisibilityRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the local editors in sync when the parent supplies a fresh view
    // mapping (e.g. after re-entering step 3 with a previously saved draft).
    if (oldWidget.bucket.name != widget.bucket.name) {
      final view = widget.self._bucketViews[widget.bucket.name];
      _displayController.text = view?.displayName ?? '';
      _prefixController.text = view?.rootPrefix ?? '';
    }
  }

  @override
  void dispose() {
    _displayController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  void _sync() {
    if (!selected) return;
    widget.self.markDirty(() {
      widget.self._bucketViews[widget.bucket.name] = BucketViewSettings(
        displayName: _displayController.text,
        rootPrefix: _prefixController.text,
      );
    });
  }

  Future<void> _chooseDirectory() async {
    // Build a draft without the bucket-view map so the picker browses the
    // account's real root (honouring any account-level RootPrefix) rather than
    // a synthetic view-prefixed tree.
    final draft = widget.self._draftConfig();
    final config = draft.copyWith(
      bucketViews: const <String, BucketViewSettings>{},
      rootPrefix: draft.rootPrefix,
    );
    final entry = FileManagerBucketEntry.fromBucketInfo(
      bucket: widget.bucket,
      profileName: 'new-account',
      sourceLabel: config.displayName,
      config: config,
    );
    final selected = await showRemoteDirectoryPicker(
      context: context,
      api: widget.self.widget.api,
      buckets: <FileManagerBucketEntry>[entry],
      initial: RemoteDirectoryResult(
        bucket: widget.bucket.name,
        prefix: _prefixController.text,
        profileName: entry.profileName,
        config: config,
      ),
    );
    if (selected == null || !mounted) return;
    _prefixController.text = selected.prefix;
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BucketSelectionCheckbox(
                value: selected,
                onChanged: (value) {
                  widget.self.markDirty(() {
                    if (value) {
                      widget.self._bucketViews[widget.bucket.name] =
                          const BucketViewSettings();
                    } else {
                      widget.self._bucketViews.remove(widget.bucket.name);
                    }
                  });
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.bucket.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (selected) ...[
            const SizedBox(height: 6),
            CloudStorageLabeledField(
              label: '显示名称（可选）',
              child: ShadInput(
                controller: _displayController,
                placeholder: Text(widget.bucket.name),
                onChanged: (_) => _sync(),
              ),
            ),
            const SizedBox(height: 8),
            CloudStorageLabeledField(
              label: '子目录（可选）',
              child: Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: _prefixController,
                      placeholder: const Text('桶根目录'),
                      onChanged: (_) => _sync(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton.outline(
                    onPressed: _chooseDirectory,
                    child: const Row(
                      children: [
                        Icon(LucideIcons.folderOpen, size: 16),
                        SizedBox(width: 4),
                        Text('选择'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A hand-rolled check box used on the bucket-visibility step and the
/// standalone bucket-visibility dialog.
///
/// Material's [Checkbox] requires a `Material` ancestor to render ink
/// splashes, but both surfaces render inside a [ShadDialog] whose subtree has
/// none, so it throws "No Material widget found". This widget renders the same
/// 18×18 rounded square + Lucide check using plain [Container] / [DecoratedBox]
/// and stays consistent with [StorageProtocolCard]'s selected chrome.
class BucketSelectionCheckbox extends StatefulWidget {
  const BucketSelectionCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<BucketSelectionCheckbox> createState() =>
      _BucketSelectionCheckboxState();
}

class _BucketSelectionCheckboxState extends State<BucketSelectionCheckbox> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    const size = 18.0;
    final fill = widget.value
        ? theme.colorScheme.primary
        : (_hovered
            ? theme.colorScheme.mutedForeground.withValues(alpha: 0.15)
            : Colors.transparent);
    final border = widget.value
        ? theme.colorScheme.primary
        : theme.colorScheme.border;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(!widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border, width: 1.5),
          ),
          child: widget.value
              ? Icon(
                  LucideIcons.check,
                  size: 14,
                  color: theme.colorScheme.primaryForeground,
                )
              : null,
        ),
      ),
    );
  }
}
