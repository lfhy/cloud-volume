// Shared list interaction colors keep object rows, grids, and task rows visually consistent.

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Neutral hover/press colors for dense file-manager style surfaces.
class ListInteractionColors {
  const ListInteractionColors({
    required this.hover,
    required this.pressed,
    required this.selected,
    required this.selectedPressed,
    required this.gridSelected,
  });

  final Color hover;
  final Color pressed;
  final Color selected;
  final Color selectedPressed;
  final Color gridSelected;

  factory ListInteractionColors.fromTheme(ShadThemeData theme) {
    final neutral = theme.colorScheme.mutedForeground;
    final primary = theme.colorScheme.primary;
    return ListInteractionColors(
      hover: neutral.withValues(alpha: 0.08),
      pressed: neutral.withValues(alpha: 0.13),
      selected: primary.withValues(alpha: 0.12),
      selectedPressed: primary.withValues(alpha: 0.2),
      gridSelected: primary.withValues(alpha: 0.15),
    );
  }

  Color rowBackground({
    required bool selected,
    required bool hovered,
    required bool pressed,
  }) {
    if (selected) {
      return pressed ? selectedPressed : this.selected;
    }
    if (pressed) return this.pressed;
    if (hovered) return hover;
    return Colors.transparent;
  }

  Color gridBackground({required bool selected, required bool hovered}) {
    if (selected) return gridSelected;
    if (hovered) return hover;
    return Colors.transparent;
  }
}
