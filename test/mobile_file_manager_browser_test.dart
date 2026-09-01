// Touch-row hover regression: idle remains a basic cursor until pointer entry.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/file_manager_bucket_entry.dart';
import 'package:remote_storage/models/remote_storage_config.dart';
import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/widgets/local_cloudpan_file_icon.dart';
import 'package:remote_storage/widgets/mobile_file_manager_browser.dart';
import 'package:remote_storage/widgets/whitesur_file_icon.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('mobile file row changes cursor only while hovered', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: MobileFileManagerRow(
            leading: const Icon(Icons.folder),
            title: '资料',
            subtitle: '文件夹',
            onTap: () {},
          ),
        ),
      ),
    );

    final row = find.byType(MobileFileManagerRow);
    final mouseRegion = find.descendant(
      of: row,
      matching: find.byType(MouseRegion),
    );
    expect(
      tester.widget<MouseRegion>(mouseRegion).cursor,
      SystemMouseCursors.basic,
    );

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(row));
    await tester.pump();
    expect(
      tester.widget<MouseRegion>(mouseRegion).cursor,
      SystemMouseCursors.click,
    );

    await pointer.moveTo(tester.getBottomRight(row) + const Offset(0, 20));
    await tester.pump();
    expect(
      tester.widget<MouseRegion>(mouseRegion).cursor,
      SystemMouseCursors.basic,
    );
  });

  testWidgets('mobile bucket row uses the desktop storage-server icon', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: MobileFileManagerBrowser(
            section: MobileFileManagerSection.buckets,
            scrollController: controller,
            buckets: [
              FileManagerBucketEntry(
                id: 'profile::bucket',
                bucket: const BucketInfo(name: 'bucket'),
                profileName: 'profile',
                sourceLabel: '账号',
                config: RemoteStorageConfig.empty(),
              ),
            ],
            onOpenBucket: (_) {},
          ),
        ),
      ),
    );

    final icon = tester.widget<WhiteSurFileIcon>(find.byType(WhiteSurFileIcon));
    expect(
      icon.assetPath,
      'assets/icons/whitesur/places/network-server-balanced.svg',
    );
  });

  testWidgets('mobile object row keeps the LocalCloudPan file icon', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: MobileFileManagerBrowser(
            section: MobileFileManagerSection.objects,
            scrollController: controller,
            objects: const [ObjectInfo(key: '资料/', size: 0, isDir: true)],
            onOpenDirectory: (_) {},
          ),
        ),
      ),
    );

    final icon = tester.widget<LocalCloudPanFileIcon>(
      find.byType(LocalCloudPanFileIcon),
    );
    expect(icon.isBucket, isFalse);
    expect(
      localCloudPanIconPathFor(icon.name, isDirectory: icon.isDirectory),
      'assets/icons/local_cloudpan/fileType/directory.svg',
    );
  });
}
