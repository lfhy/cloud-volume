// Unified remote-task page. Physical transfer producers remain execution
// details; this page renders only the durable RemoteTask projection.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:remote_storage/widgets/app_toast.dart';
import 'package:remote_storage/widgets/list_selection_controls.dart';
import 'package:remote_storage/widgets/remote_task_widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

part 'transfers_page_remote.dart';

class TransfersPage extends StatefulWidget {
  const TransfersPage({
    super.key,
    required this.api,
    required this.config,
    this.active = false,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final bool active;

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedTaskIds = <String>{};
  String _searchText = '';
  _RemoteTaskStatusFilter _remoteStatusFilter = _RemoteTaskStatusFilter.all;
  _RemoteTaskKindFilter _remoteKindFilter = _RemoteTaskKindFilter.all;
  bool _runningBatchAction = false;

  @override
  void initState() {
    super.initState();
    RemoteTaskStore.instance.bindApi(widget.api);
    RemoteTaskStore.instance.addListener(_syncSelectionWithTasks);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    RemoteTaskStore.instance.removeListener(_syncSelectionWithTasks);
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TransfersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      RemoteTaskStore.instance.bindApi(widget.api);
    }
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (next != _searchText && mounted) {
      setState(() => _searchText = next);
    }
  }

  void _syncSelectionWithTasks() {
    final ids = RemoteTaskStore.instance.tasks.map((task) => task.id).toSet();
    final before = _selectedTaskIds.length;
    _selectedTaskIds.removeWhere((id) => !ids.contains(id));
    if (before != _selectedTaskIds.length && mounted) {
      setState(() {});
    }
  }

  void _toggleTaskSelection(String id) {
    setState(() {
      if (!_selectedTaskIds.remove(id)) {
        _selectedTaskIds.add(id);
      }
    });
  }

  // Extensions use this narrow wrapper instead of reaching into State APIs.
  void _remoteSetState(VoidCallback callback) {
    if (mounted) setState(callback);
  }

  Widget _buildEmptyState(ShadThemeData theme, String title, String message) {
    return Center(
      child: ShadCard(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.arrowLeftRight,
              size: 28,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 36, right: 36, bottom: 20),
      child: AnimatedBuilder(
        animation: RemoteTaskStore.instance,
        builder: (context, _) =>
            _buildRemoteQueueBody(theme, RemoteTaskStore.instance),
      ),
    );
  }
}
