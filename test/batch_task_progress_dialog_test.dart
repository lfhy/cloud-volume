// Batch task progress dialog tests cover modal copy and background behavior.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/state/transfer_queue.dart';
import 'package:remote_storage/widgets/batch_task_progress_dialog.dart';
import 'package:remote_storage/widgets/batch_task_progress_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TransferQueue.instance.resetForTest();
  });

  tearDown(() {
    TransferQueue.instance.resetForTest();
  });

  testWidgets('delete batch dialog shows progress and can run in background', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final first = TransferQueue.instance.startTask(
      kind: TransferKind.delete,
      bucket: 'bucket-a',
      key: 'docs/a.txt',
      localPath: '',
    )..status = TransferStatus.running;
    final second = TransferQueue.instance.startTask(
      kind: TransferKind.delete,
      bucket: 'bucket-a',
      key: 'docs/b.txt',
      localPath: '',
    )..status = TransferStatus.running;
    var backgroundRequested = false;

    await tester.pumpWidget(
      ShadApp(
        home: Material(
          child: BatchTaskProgressDialog(
            taskIds: <String>[first.id, second.id],
            currentPathLabel: 'bucket-a / docs',
            mode: BatchTaskProgressMode.delete,
            onRunInBackground: () => backgroundRequested = true,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('正在删除'), findsOneWidget);
    expect(find.text('当前有 2 个删除任务正在进行，可关闭弹框后继续后台删除。'), findsOneWidget);
    expect(find.text('取消删除'), findsOneWidget);
    expect(find.text('后台运行'), findsOneWidget);
    expect(find.text('a.txt'), findsOneWidget);
    expect(find.text('b.txt'), findsOneWidget);

    await tester.tap(find.text('后台运行'));
    await tester.pump();

    expect(backgroundRequested, isTrue);
    expect(TransferQueue.instance.statusOf(first.id), TransferStatus.running);
    expect(TransferQueue.instance.statusOf(second.id), TransferStatus.running);
    await tester.pumpWidget(const SizedBox.shrink());
    TransferQueue.instance.resetForTest();
    await tester.pump();
  });

  testWidgets('finished delete batch shows determinate complete progress', (
    tester,
  ) async {
    final first = TransferQueue.instance.startTask(
      kind: TransferKind.delete,
      bucket: 'bucket-a',
      key: 'docs/a.txt',
      localPath: '',
    )..status = TransferStatus.done;
    final second = TransferQueue.instance.startTask(
      kind: TransferKind.delete,
      bucket: 'bucket-a',
      key: 'docs/b.txt',
      localPath: '',
    )..status = TransferStatus.done;

    await tester.pumpWidget(
      ShadApp(
        home: Material(
          child: BatchTaskProgressDialog(
            taskIds: <String>[first.id, second.id],
            currentPathLabel: 'bucket-a / docs',
            mode: BatchTaskProgressMode.delete,
            onRunInBackground: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator).first,
    );
    expect(indicator.value, 1.0);
    expect(find.text('删除完成'), findsOneWidget);
    expect(find.text('后台运行'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    TransferQueue.instance.resetForTest();
    await tester.pump();
  });
}
