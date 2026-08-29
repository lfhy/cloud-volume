import 'package:flutter/material.dart';
import 'package:remote_storage/widgets/file_manager_drag_selection.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FileManagerObjectHeader extends StatelessWidget {
  const FileManagerObjectHeader({super.key, required this.theme, required this.showSelectionControl, required this.allSelected, required this.partiallySelected, required this.onToggleSelectAll, this.showSyncStatus = false, this.compact = false});
  final ShadThemeData theme;
  final bool showSelectionControl, allSelected, partiallySelected, showSyncStatus, compact;
  final VoidCallback onToggleSelectAll;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: theme.colorScheme.mutedForeground);
    return Container(padding: const EdgeInsets.fromLTRB(12, 8, 12, 7), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.border.withValues(alpha: .7), width: .6))), child: Row(children: [
      if (showSelectionControl) ...[FileManagerBlankTapRegion(child: ListSelectionControl(selected: allSelected, partiallySelected: partiallySelected, onTap: onToggleSelectAll)), const SizedBox(width: 10)],
      const SizedBox(width: 32), const SizedBox(width: 12),
      if (compact) const Expanded(child: Text('全选')) else ...[
        Expanded(child: Text('名称', style: style)), const SizedBox(width: 12),
        SizedBox(width: FileListTile.sizeColumnWidth, child: Text('大小', textAlign: TextAlign.right, style: style)),
        if (showSyncStatus) ...[const SizedBox(width: 16), SizedBox(width: FileListTile.statusColumnWidth, child: Text('同步状态', textAlign: TextAlign.right, style: style))],
        const SizedBox(width: 16), SizedBox(width: FileListTile.modifiedColumnWidth, child: Text('修改时间', textAlign: TextAlign.right, style: style)),
      ],
    ]));
  }
}
