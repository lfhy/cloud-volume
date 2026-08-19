// Update status UI tests keep irreversible installer actions unambiguous.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/widgets/update_status_row.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'does not render cancellation after install becomes irreversible',
    (tester) async {
      await tester.pumpWidget(
        ShadApp(
          home: Builder(
            builder: (context) => Material(
              child: UpdateStatusRow(
                theme: ShadTheme.of(context),
                title: '正在安装新版本...',
                subtitle: '下载完成，正在安装...',
                highlighted: true,
                errorText: null,
                checking: false,
                openingDownloadPage: false,
                installing: true,
                installProgress: 1,
                canInstallInApp: true,
                canCancelInstall: false,
                onCheckForUpdates: () {},
                onOpenDownloadPage: () {},
                onInstall: () {},
                onCancelInstall: null,
              ),
            ),
          ),
        ),
      );

      expect(find.text('取消更新'), findsNothing);
      expect(find.text('一键更新'), findsNothing);
      expect(find.text('GitHub 下载'), findsOneWidget);
    },
  );
}
