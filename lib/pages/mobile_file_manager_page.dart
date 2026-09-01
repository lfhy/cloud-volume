// Android entry point retains its Back bridge while rendering desktop file UX.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/sync_remote_open_request.dart';
import 'package:remote_storage/pages/file_manager_page.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/state/mobile_file_manager_navigation.dart';

/// Android uses the canonical file-manager renderer with mobile navigation.
class MobileFileManagerPage extends StatelessWidget {
  const MobileFileManagerPage({
    super.key,
    required this.api,
    required this.config,
    required this.profiles,
    required this.onRefresh,
    this.homeView = FileManagerHomeView.files,
    this.pendingSyncRemoteOpen,
    this.pendingSyncRemoteOpenGeneration = 0,
    this.onPendingSyncRemoteOpenConsumed,
    this.onOpenAccountManagement,
    this.navigation,
  });

  final RemoteStorageGateway api;
  final RemoteStorageConfig config;
  final List<ProfileInfo> profiles;
  final VoidCallback onRefresh;
  final FileManagerHomeView homeView;
  final SyncRemoteOpenRequest? pendingSyncRemoteOpen;
  final int pendingSyncRemoteOpenGeneration;
  final SyncRemoteOpenConsumer? onPendingSyncRemoteOpenConsumed;
  final VoidCallback? onOpenAccountManagement;
  final MobileFileManagerNavigation? navigation;

  @override
  Widget build(BuildContext context) {
    return FileManagerWorkspace(
      api: api,
      config: config,
      profiles: profiles,
      onRefresh: onRefresh,
      homeView: homeView,
      pendingSyncRemoteOpen: pendingSyncRemoteOpen,
      pendingSyncRemoteOpenGeneration: pendingSyncRemoteOpenGeneration,
      onPendingSyncRemoteOpenConsumed: onPendingSyncRemoteOpenConsumed,
      onOpenAccountManagement: onOpenAccountManagement,
      mobileNavigation: true,
      navigation: navigation,
    );
  }
}
