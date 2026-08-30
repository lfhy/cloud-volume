// Regression coverage for backup restore directory selection on phone-sized dialogs.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/bootstrap_state.dart';
import 'package:remote_storage/models/config_backup.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_directory_picker_window_args.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/pages/config_setup_page.dart';
import 'package:remote_storage/services/app_modal.dart';
import 'package:remote_storage/services/remote_storage_gateway.dart';
import 'package:remote_storage/utils/config_backup_picker.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:remote_storage/widgets/file_list_tile.dart';
import 'package:remote_storage/widgets/remote_directory_picker_dialog.dart';
import 'package:remote_storage/widgets/settings_config_backup_labels.dart';
import 'package:remote_storage/widgets/settings_config_backup_target.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test(
    'single-root backup providers use an alias without changing identity',
    () {
      for (final type in const [
        StorageType.webdav,
        StorageType.baiduPan,
        StorageType.ftp,
        StorageType.sftp,
      ]) {
        final config = RemoteStorageConfig.empty().copyWith(
          storageType: type,
          displayName: 'root',
          mappedBucketName: 'root',
        );
        final model = buildConfigBackupPickerModel(
          config: config,
          buckets: const [BucketInfo(name: 'root')],
          profileName: '__restore__',
        );

        expect(model.entries.single.label, configBackupStorageDisplayName);
        expect(model.entries.single.bucket.name, 'root');
        expect(model.entries.single.id, '__restore__::root');
        expect(model.entries.single.sourceLabel, type.label);
        expect(model.initialEntry, same(model.entries.single));
      }
    },
  );

  test('backup bucket label helper aliases only synthetic-root providers', () {
    expect(
      configBackupBucketDisplayName(
        storageType: StorageType.webdav,
        bucket: 'webdav-synthetic-user',
      ),
      configBackupStorageDisplayName,
    );
    expect(
      configBackupBucketDisplayName(
        storageType: StorageType.s3,
        bucket: 'root',
      ),
      'root',
    );
  });

  test('S3 keeps its real bucket name even when only one bucket exists', () {
    final model = buildConfigBackupPickerModel(
      config: RemoteStorageConfig.empty().copyWith(displayName: 'S3 备份'),
      buckets: const [BucketInfo(name: 'root')],
      profileName: '__restore__',
    );

    expect(model.entries.single.label, 'root');
    expect(model.entries.single.sourceLabel, 'S3 备份');
    expect(model.initialEntry, isNull);
  });

  test(
    'picker window arguments preserve display aliases and root prefixes',
    () {
      final original = FileManagerBucketEntry(
        id: '__restore__::root',
        bucket: const BucketInfo(name: 'root'),
        profileName: '__restore__',
        sourceLabel: 'SFTP',
        displayName: configBackupStorageDisplayName,
        rootPrefix: 'backups/config',
        config: RemoteStorageConfig.empty(),
      );
      final restored = RemoteDirectoryPickerWindowArgs.fromArguments(
        RemoteDirectoryPickerWindowArgs(
          requestId: 'request',
          creatorWindowId: 'creator',
          buckets: [original],
        ).toArguments(),
      ).buckets.single;

      expect(restored.bucket.name, 'root');
      expect(restored.displayName, configBackupStorageDisplayName);
      expect(restored.rootPrefix, 'backups/config');
    },
  );

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
      _expectTextNotVisuallyTruncated(tester, 'root');
      expect(
        tester
            .widget<FileListTile>(
              find.ancestor(
                of: find.text('root'),
                matching: find.byType(FileListTile),
              ),
            )
            .compact,
        isTrue,
      );
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
    final api = _PickerGateway(
      objectsByPrefix: const {
        '': [
          ObjectInfo(key: 'lost+found/', size: 0, isDir: true),
          ObjectInfo(key: 'media/', size: 0, isDir: true),
        ],
      },
    );
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
    _expectTextNotVisuallyTruncated(tester, 'lost+found');
    _expectTextNotVisuallyTruncated(tester, 'media');
  });

  testWidgets(
    'phone rows show names and backup alias without changing bucket identity',
    (tester) async {
      final config = RemoteStorageConfig.empty().copyWith(
        storageType: StorageType.sftp,
        displayName: 'root',
        mappedBucketName: 'root',
      );
      final model = buildConfigBackupPickerModel(
        config: config,
        buckets: const [BucketInfo(name: 'root')],
        profileName: '__restore__',
      );
      final entry = model.initialEntry!;
      final api = _PickerGateway(
        objectsByPrefix: const {
          '': [
            ObjectInfo(key: 'boot/', size: 0, isDir: true),
            ObjectInfo(key: 'home/', size: 0, isDir: true),
            ObjectInfo(key: 'lost+found/', size: 0, isDir: true),
            ObjectInfo(key: 'media/', size: 0, isDir: true),
            ObjectInfo(key: 'backup-notes.txt', size: 1024, isDir: false),
          ],
        },
      );
      RemoteDirectoryResult? selected;
      await tester.pumpWidget(
        _pickerHarness(
          api: api,
          contentWidth: 363.4,
          buckets: model.entries,
          initial: RemoteDirectoryResult(
            bucket: entry.bucket.name,
            prefix: '',
            profileName: entry.profileName,
            config: config,
          ),
          onConfirm: (result) => selected = result,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(configBackupStorageDisplayName), findsOneWidget);
      expect(find.text('root'), findsNothing);
      expect(api.listCalls, const [(bucket: 'root', prefix: '')]);
      _expectTextNotVisuallyTruncated(tester, configBackupStorageDisplayName);
      for (final name in const [
        'boot',
        'home',
        'lost+found',
        'media',
        'backup-notes.txt',
      ]) {
        _expectTextNotVisuallyTruncated(tester, name);
        final tile = tester.widget<FileListTile>(
          find.ancestor(
            of: find.text(name),
            matching: find.byType(FileListTile),
          ),
        );
        expect(tile.compact, isTrue);
      }
      expect(find.text('1.0 KB'), findsOneWidget);

      await tester.tap(find.text('选择当前目录'));
      await tester.pump();
      expect(selected?.bucket, 'root');
      expect(selected?.prefix, '');
    },
  );

  testWidgets('wide picker keeps both action groups on one row', (
    tester,
  ) async {
    final api = _PickerGateway(
      objectsByPrefix: const {
        '': [ObjectInfo(key: 'lost+found/', size: 0, isDir: true)],
      },
    );
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
    expect(
      tester
          .widget<FileListTile>(
            find.ancestor(
              of: find.text('lost+found'),
              matching: find.byType(FileListTile),
            ),
          )
          .compact,
      isFalse,
    );
  });

  testWidgets('deep phone breadcrumb scrolls instead of overflowing', (
    tester,
  ) async {
    const prefix =
        'first-very-long-directory/second-very-long-directory/third-current-directory/';
    final api = _PickerGateway(objectsByPrefix: const {prefix: []});
    await tester.pumpWidget(
      _pickerHarness(
        api: api,
        contentWidth: 363.4,
        initial: _initial(bucket: 'root', prefix: prefix),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('third-current-directory'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets(
    'settings backup picker aliases a synthetic bucket without changing its saved target',
    (tester) async {
      const bucket = 'webdav-synthetic-user';
      const prefix = 'saved/config-backups/';
      final config = RemoteStorageConfig.empty().copyWith(
        storageType: StorageType.webdav,
        endpoint: 'https://dav.example.test',
        displayName: 'root',
        mappedBucketName: bucket,
        webdavUsername: 'root',
        hasWebdavPassword: true,
      );
      final api = _SettingsBackupPickerGateway(
        buckets: const [BucketInfo(name: bucket)],
      );
      ({String bucket, String prefix})? picked;

      await tester.pumpWidget(
        ShadApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ConfigBackupTargetSection(
                theme: ShadTheme.of(context),
                api: api,
                profiles: const [],
                target: ConfigBackupTarget(
                  standalone: config,
                  bucket: bucket,
                  prefix: prefix,
                ),
                busy: false,
                backingUp: false,
                encryptionEnabled: false,
                onSelectTarget: (_) {},
                onConfigureStandalone: (_) {},
                onPickSaveLocation: (bucket, prefix) {
                  picked = (bucket: bucket, prefix: prefix);
                },
                onToggleEncryption: (_) {},
                onPasswordSaved: (_) {},
                onBackupNow: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('备份存储 / saved/config-backups'), findsOneWidget);
      await tester.tap(find.text('备份存储 / saved/config-backups'));
      await tester.pumpAndSettle();

      final picker = find.byType(RemoteDirectoryPickerDialog);
      expect(picker, findsOneWidget);
      expect(
        find.descendant(
          of: picker,
          matching: find.text(configBackupStorageDisplayName),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: picker, matching: find.text(bucket)),
        findsNothing,
      );
      expect(api.objectListCalls, const [(bucket: bucket, prefix: prefix)]);

      await tester.tap(
        find.descendant(of: picker, matching: find.text('选择当前目录')),
      );
      await tester.pumpAndSettle();
      expect(picked, (bucket: bucket, prefix: prefix));
    },
  );

  testWidgets('Android dialog picker fills bounded sheet height without flex', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
      addTearDown(tester.view.reset);
      final api = _PickerGateway();

      await tester.pumpWidget(
        ShadApp(
          home: RemoteDirectoryPickerDialog(
            api: api,
            buckets: [_bucketEntry()],
            initial: _initial(bucket: '', prefix: ''),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceRect = tester.getRect(_androidSheetSurfaceFinder());
      expect(surfaceRect.left, 0);
      expect(surfaceRect.width, 393);
      expect(surfaceRect.top, greaterThan(0));
      expect(surfaceRect.bottom, 852);
      expect(surfaceRect.height, lessThan(852));
      expect(find.text('选择远端目录'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(800, 360);
      await tester.pumpAndSettle();
      final compactSurface = tester.getRect(_androidSheetSurfaceFinder());
      expect(compactSurface.left, 0);
      expect(compactSurface.width, 800);
      expect(compactSurface.top, greaterThan(0));
      expect(compactSurface.bottom, 360);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'Android landscape picker scrolls create input and actions above IME',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(800, 360);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
        addTearDown(tester.view.reset);
        final api = _PickerGateway();

        await tester.pumpWidget(
          ShadApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: RemoteDirectoryPickerDialog(
                  api: api,
                  buckets: [_bucketEntry()],
                  initial: _initial(bucket: 'root', prefix: ''),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('新建目录'));
        await tester.tap(find.text('新建目录'));
        await tester.pumpAndSettle();
        expect(find.text('输入目录名称'), findsOneWidget);

        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        await tester.pumpAndSettle();

        final surfaceRect = tester.getRect(_androidSheetSurfaceFinder());
        expect(surfaceRect.left, 0);
        expect(surfaceRect.width, 800);
        expect(surfaceRect.top, greaterThan(24));
        expect(surfaceRect.bottom, closeTo(180, .5));
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );

        await tester.ensureVisible(find.text('选择当前目录'));
        await tester.pumpAndSettle();
        final actionRect = tester.getRect(find.text('选择当前目录'));
        expect(actionRect.top, greaterThanOrEqualTo(surfaceRect.top + 24));
        expect(actionRect.bottom, lessThanOrEqualTo(surfaceRect.bottom - 20));
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

Finder _androidSheetSurfaceFinder() => find.descendant(
  of: find.byType(AppShadDialog),
  matching: find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) return false;
    final decoration = widget.decoration;
    return decoration is BoxDecoration &&
        decoration.borderRadius ==
            const BorderRadius.vertical(top: Radius.circular(20));
  }),
);

Widget _pickerHarness({
  required _PickerGateway api,
  required double contentWidth,
  required RemoteDirectoryResult initial,
  List<FileManagerBucketEntry>? buckets,
  ValueChanged<RemoteDirectoryResult>? onConfirm,
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
              buckets: buckets ?? [_bucketEntry()],
              initial: initial,
              asDialog: false,
              onConfirm: onConfirm,
            ),
          ),
        ),
      ),
    ),
  );
}

void _expectTextNotVisuallyTruncated(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  expect(paragraph.didExceedMaxLines, isFalse, reason: '$text should fit');
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

class _SettingsBackupPickerGateway extends Fake
    implements RemoteStorageGateway {
  _SettingsBackupPickerGateway({required this.buckets});

  final List<BucketInfo> buckets;
  final List<({String bucket, String prefix})> objectListCalls = [];

  @override
  Future<List<BucketInfo>> listBuckets(
    RemoteStorageConfig config, {
    bool force = false,
  }) async => buckets;

  @override
  Future<List<ObjectInfo>> listObjects(
    RemoteStorageConfig config,
    String bucket,
    String prefix,
  ) async {
    objectListCalls.add((bucket: bucket, prefix: prefix));
    return const [];
  }
}
