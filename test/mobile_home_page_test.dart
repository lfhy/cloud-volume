// MobileHomePage 契约:问候与账号概览、快捷入口四项(含设置保底入口)
// 与导航回调、最近任务空态与活动任务行渲染(本地任务仅活动态进入
// 统一任务列表,与 RemoteTaskStore 的投影语义一致)。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/sidebar_item.dart';
import 'package:remote_storage/pages/mobile_home_page.dart';
import 'package:remote_storage/state/remote_task_store.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

BootstrapState _state({int profileCount = 2}) {
  return BootstrapState(
    configPath: '/tmp/config.db',
    configured: true,
    config: RemoteStorageConfig.empty(),
    profiles: List.generate(
      profileCount,
      (i) => ProfileInfo(
        name: 'profile-$i',
        displayName: '账号 $i',
        storageType: StorageType.s3,
        providerType: StorageProviderType.s3,
        endpoint: 'https://s3.example.com',
        accessKeyId: 'key-$i',
      ),
    ),
  );
}

void main() {
  setUp(() {
    RemoteTaskStore.instance.resetForTest();
  });

  tearDown(() {
    RemoteTaskStore.instance.resetForTest();
  });

  testWidgets('home shows greeting, profile summary and quick entries',
      (tester) async {
    final visited = <SidebarItem>[];
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: MobileHomePage(state: _state(), onNavigate: visited.add),
        ),
      ),
    );

    expect(find.textContaining('欢迎回来'), findsOneWidget);
    expect(find.text('云卷 · 2 个账号'), findsOneWidget);

    // 快捷入口四项:文件管理、账号管理、回收站、系统设置。
    for (final label in ['文件管理', '账号管理', '回收站', '系统设置']) {
      expect(find.text(label), findsOneWidget);
    }
    // 空任务态。
    expect(find.text('暂无任务记录'), findsOneWidget);

    await tester.tap(find.text('系统设置'));
    expect(visited, [SidebarItem.settings]);
    await tester.tap(find.text('回收站'));
    expect(visited, [SidebarItem.settings, SidebarItem.trash]);
  });

  testWidgets('home renders recent task rows from the store', (tester) async {
    RemoteTaskStore.instance.publishLocalTask(
      const RemoteTask(
        id: 'sync:a',
        kind: RemoteTaskKind.upload,
        status: RemoteTaskStatus.running,
        bucket: 'bucket-a',
        targetPath: 'bucket-a/report.pdf',
      ),
    );
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: MobileHomePage(
            state: _state(profileCount: 0),
            onNavigate: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('执行中'), findsOneWidget);
    expect(find.text('暂无任务记录'), findsNothing);
  });
}
