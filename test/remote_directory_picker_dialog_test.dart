// Regression coverage for backup restore directory selection on phone-sized dialogs.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/pages/config_setup_page.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';
import 'package:remote_storage/widgets/settings_config_backup_labels.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test('backup error labels remove bridge implementation details', () {
    expect(
      configBackupFriendlyError(
        'RemoteStorageBridgeException: file does not exist',
      ),
      '文件已被删除或不存在，请刷新目录后重试。',
    );
  });

  testWidgets(
    'blank initial bucket stays on bucket list and phone actions regroup',
    (tester) async {
      final api = _PickerGateway();
      await tester.pumpWidget(
        _pickerHarness(
          api: api,
          contentWidth: 363.4,
          initial: _initial(bucket: '', prefix: 'cloud-volume-config-backups'),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.listCalls, isEmpty);
      expect(find.text('cloud-volume-config-backups'), findsNothing);
      expect(
        tester.getCenter(find.text('取消')).dx,
        greaterThan(
          tester.getCenter(find.byKey(const ValueKey('picker-frame'))).dx,
        ),
      );

      await tester.tap(find.text('root'));
      await tester.pumpAndSettle();

      expect(api.listCalls, [(bucket: 'root', prefix: '')]);
      expect(tester.takeException(), isNull);
      _expectActionsInside(tester, find.byKey(const ValueKey('picker-frame')));
      expect(
        tester.getTopLeft(find.text('桶列表')).dy,
        lessThan(tester.getTopLeft(find.text('取消')).dy),
      );
    },
  );

  testWidgets('phone actions remain visible at 1.5x text scale', (
    tester,
  ) async {
    final api = _PickerGateway();
    await tester.pumpWidget(
      _pickerHarness(
        api: api,
        contentWidth: 363.4,
        textScale: 1.5,
        initial: _initial(bucket: 'root', prefix: ''),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectActionsInside(tester, find.byKey(const ValueKey('picker-frame')));
  });

  testWidgets('wide picker keeps both action groups on one row', (
    tester,
  ) async {
    final api = _PickerGateway();
    await tester.pumpWidget(
      _pickerHarness(
        api: api,
        contentWidth: 600,
        initial: _initial(bucket: 'root', prefix: ''),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getCenter(find.text('桶列表')).dy,
      closeTo(tester.getCenter(find.text('取消')).dy, 0.5),
    );
  });

  testWidgets('successful breadcrumb retry clears a missing-directory error', (
    tester,
  ) async {
    final api = _PickerGateway(
      errorsByPrefix: {'missing/': Exception('file does not exist')},
      objectsByPrefix: const {
        '': [ObjectInfo(key: 'folder/', size: 0, isDir: true)],
      },
    );
    await tester.pumpWidget(
      _pickerHarness(
        api: api,
        contentWidth: 600,
        initial: _initial(bucket: 'root', prefix: 'missing/'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('文件已被删除或不存在'), findsOneWidget);
    await tester.tap(find.text('root'));
    await tester.pumpAndSettle();

    expect(find.textContaining('文件已被删除或不存在'), findsNothing);
    expect(find.text('folder'), findsOneWidget);
    expect(api.listCalls.last, (bucket: 'root', prefix: ''));
  });

  testWidgets('late directory failure cannot overwrite newer navigation', (
    tester,
  ) async {
    final delayedMissing = Completer<List<ObjectInfo>>();
    final api = _PickerGateway(
      futuresByPrefix: {'missing/': delayedMissing.future},
      objectsByPrefix: const {
        '': [ObjectInfo(key: 'folder/', size: 0, isDir: true)],
      },
    );
    await tester.pumpWidget(
      _pickerHarness(
        api: api,
        contentWidth: 600,
        initial: _initial(bucket: 'root', prefix: 'missing/'),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('root'));
    await tester.pumpAndSettle();
    expect(find.text('folder'), findsOneWidget);

    delayedMissing.completeError(Exception('file does not exist'));
    await tester.pump();
    await tester.pump();

    expect(find.text('folder'), findsOneWidget);
    expect(find.textContaining('文件已被删除或不存在'), findsNothing);
  });

  testWidgets('empty backup snapshot result renders an empty state', (
    tester,
  ) async {
    final api = _PickerGateway(
      backupSettings: const ConfigBackupSettings(
        target: ConfigBackupTarget(profileName: 'backup', bucket: 'root'),
      ),
    );
    await tester.pumpWidget(
      ShadApp(
        home: ConfigSetupPage(
          api: api,
          initialState: BootstrapState(
            configPath: '/tmp/config.db',
            configured: false,
            config: RemoteStorageConfig.empty(),
          ),
          onSaved: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('从备份存储还原'));
    await tester.tap(find.text('从备份存储还原'));
    await tester.pumpAndSettle();

    expect(find.textContaining('没有找到配置备份'), findsOneWidget);
    expect(find.byType(AppLoadingIndicator), findsNothing);
  });
}

Widget _pickerHarness({
  required _PickerGateway api,
  required double contentWidth,
  required RemoteDirectoryResult initial,
  double textScale = 1,
}) {
  return ShadApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            key: const ValueKey('picker-frame'),
            width: contentWidth,
            height: 600,
            child: RemoteDirectoryPickerDialog(
              api: api,
              buckets: [_bucketEntry()],
              initial: initial,
              asDialog: false,
            ),
          ),
        ),
      ),
    ),
  );
}

FileManagerBucketEntry _bucketEntry() => FileManagerBucketEntry(
  id: '__restore__::root',
  bucket: const BucketInfo(name: 'root'),
  profileName: '__restore__',
  sourceLabel: 'WebDAV',
  config: RemoteStorageConfig.empty(),
);

RemoteDirectoryResult _initial({
  required String bucket,
  required String prefix,
}) => RemoteDirectoryResult(
  bucket: bucket,
  prefix: prefix,
  profileName: '__restore__',
  config: RemoteStorageConfig.empty(),
);

void _expectActionsInside(WidgetTester tester, Finder frameFinder) {
  final frame = tester.getRect(frameFinder);
  for (final label in const ['桶列表', '新建目录', '取消', '选择当前目录']) {
    final rect = tester.getRect(find.text(label));
    expect(rect.left, greaterThanOrEqualTo(frame.left));
    expect(rect.right, lessThanOrEqualTo(frame.right));
  }
}

class _PickerGateway extends Fake implements RemoteStorageGateway {
  _PickerGateway({
    this.errorsByPrefix = const {},
    this.futuresByPrefix = const {},
    this.objectsByPrefix = const {},
    this.backupSettings = const ConfigBackupSettings(),
  });

  final Map<String, Object> errorsByPrefix;
  final Map<String, Future<List<ObjectInfo>>> futuresByPrefix;
  final Map<String, List<ObjectInfo>> objectsByPrefix;
  final ConfigBackupSettings backupSettings;
  final List<({String bucket, String prefix})> listCalls = [];

  @override
  Future<List<ObjectInfo>> listObjects(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async {
    listCalls.add((bucket: bucket, prefix: prefix));
    final error = errorsByPrefix[prefix];
    if (error != null) throw error;
    final pending = futuresByPrefix[prefix];
    if (pending != null) return await pending;
    return objectsByPrefix[prefix] ?? const [];
  }

  @override
  Future<ConfigBackupSettings> loadConfigBackupSettings() async =>
      backupSettings;

  @override
  Future<List<ConfigBackupSnapshot>> listConfigBackupsWithTarget(
    ConfigBackupTarget target,
  ) async => const [];
}
