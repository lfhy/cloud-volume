// Pins the expanded detail panel layout: aligned label column, localized
// journal events, one physical transfer ID per line, and the wrap contract
// for long values.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/widgets/remote_task_details.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('detail rows align and localize journal content', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const task = RemoteTask(
      id: 'sync:test:details',
      kind: RemoteTaskKind.write,
      status: RemoteTaskStatus.failed,
      bucket: 'bucket-a',
      targetPath: 'root/dir/file.txt',
      error: 'provider handshake failed after retries',
      events: <RemoteTaskEvent>[
        RemoteTaskEvent(
          sequence: 2713,
          kind: 'write',
          targetPath: 'root/a.txt',
          folded: true,
        ),
        RemoteTaskEvent(
          sequence: 2714,
          kind: 'delete',
          targetPath: 'root/b.txt',
        ),
      ],
      physicalTaskIds: <String>['metadata-op-ns1-1', 'metadata-op-ns1-2'],
    );

    await tester.pumpWidget(
      const ShadApp(
        home: Scaffold(body: RemoteTaskDetails(task: task)),
      ),
    );

    // Metadata rows keep their labels; values localize.
    expect(find.text('操作'), findsOneWidget);
    expect(find.text('所属桶'), findsOneWidget);
    expect(find.text('完整路径'), findsOneWidget);
    expect(find.text('写入文件'), findsOneWidget);

    // Journal events: grouped under one 事件记录 label (blank labels keep
    // alignment for the rest); each value reads #序号 中文动词 路径（已合并）.
    expect(find.text('事件记录'), findsOneWidget);
    expect(find.text('#2713 写入 root/a.txt（已合并）'), findsOneWidget);
    expect(find.text('#2714 删除 root/b.txt'), findsOneWidget);

    // Physical snapshots print one ID per line: each is its own Text widget.
    expect(find.text('metadata-op-ns1-1'), findsOneWidget);
    expect(find.text('metadata-op-ns1-2'), findsOneWidget);
    expect(find.text('传输'), findsOneWidget);

    // Wrap contract: value columns have no maxLines (long errors wrap),
    // label columns stay single-line with ellipsis.
    final errorValue = tester.widget<Text>(
      find.text('provider handshake failed after retries'),
    );
    expect(errorValue.maxLines, isNull);
    final label = tester.widget<Text>(find.text('完整路径'));
    expect(label.maxLines, 1);
  });
}
