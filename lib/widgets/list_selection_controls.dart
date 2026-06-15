// Shared list selection controls keep file-manager and transfer multi-select visuals aligned.
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ListSelectionControl extends StatelessWidget {
  const ListSelectionControl({
    super.key,
    required this.selected,
    required this.onTap,
    this.partiallySelected = false,
    this.enabled = true,
  });

  final bool selected;
  final bool partiallySelected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final accent = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;
    final active = selected || partiallySelected;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: active ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? accent
                : theme.colorScheme.border.withValues(alpha: 0.9),
            width: 1.2,
          ),
        ),
        child: selected
            ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
            : partiallySelected
            ? const Icon(LucideIcons.minus, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}
