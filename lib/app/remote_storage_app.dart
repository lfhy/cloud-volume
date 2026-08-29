// Root widget: wires ShadApp + ThemeInitializer (with persistence) + transparent chrome.

import 'package:flutter/material.dart';
import 'package:remote_storage/app/app_brand.dart';
import 'package:remote_storage/pages/app_bootstrap_page.dart';
import 'package:remote_storage/platform/platform_info.dart';
import 'package:remote_storage/services/remote_storage_api.dart';
import 'package:remote_storage/theme/app_theme.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/widgets/desktop_modal_parent_focus_relay.dart';
import 'package:remote_storage/widgets/desktop_modal_scrim.dart';
import 'package:remote_storage/widgets/desktop_window_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RemoteStorageApp extends StatelessWidget {
  const RemoteStorageApp({
    super.key,
    this.apiFactory = defaultRemoteStorageApiFactory,
  });

  final RemoteStorageApiFactory apiFactory;

  @override
  Widget build(BuildContext context) {
    return ThemeInitializer(child: _ThemeAwareShell(apiFactory: apiFactory));
  }
}

/// Inner shell that reads the current accent from ThemeController.
class _ThemeAwareShell extends StatelessWidget {
  const _ThemeAwareShell({required this.apiFactory});

  final RemoteStorageApiFactory apiFactory;

  @override
  Widget build(BuildContext context) {
    final accent = ThemeController.of(context).accent;
    final content = ShadApp(
      title: appBrandName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: buildAppTheme(accent),
      home: Stack(
        children: isDesktopPlatform
            ? <Widget>[
                AppBootstrapPage(apiFactory: apiFactory),
                const DesktopModalScrim(),
                const DesktopWindowControls(),
              ]
            : <Widget>[AppBootstrapPage(apiFactory: apiFactory)],
      ),
    );
    return isDesktopPlatform
        ? DesktopModalParentFocusRelay(child: content)
        : content;
  }
}
