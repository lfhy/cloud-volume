// Pins display-layer mappings: subsystem phases must not leak as raw
// English, terminal/blocked/cancel states fall back to localized labels,
// and row titles derive from the last path segment.
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_storage/models/remote_task.dart';
import 'package:remote_storage/models/remote_task_display.dart';
import 'package:remote_storage/widgets/remote_task_style_helpers.dart';

RemoteTask _task(
  RemoteTaskStatus status, {
  String phaseDetail = '',
  String targetPath = '',
  String blockedReason = '',
}) => RemoteTask(
  id: 'sync:test:display',
  kind: RemoteTaskKind.write,
  status: status,
  targetPath: targetPath,
  phaseDetail: phaseDetail,
  blockedReason: blockedReason,
);

void main() {
  group('phaseLabel suppresses subsystem markers', () {
    test('terminal history phase maps to empty and subtitle shows 已完成', () {
      final task = _task(RemoteTaskStatus.done, phaseDetail: 'history');
      expect(task.phaseLabel, '');
      expect(remoteTaskSubtitle(task), '已完成');
    });

    test('provider/verification/dependency markers stay hidden', () {
      expect(
        _task(RemoteTaskStatus.waiting, phaseDetail: 'provider').phaseLabel,
        '',
      );
      expect(
        _task(
          RemoteTaskStatus.verifying,
          phaseDetail: 'verification',
        ).phaseLabel,
        '',
      );
      expect(
        _task(RemoteTaskStatus.blocked, phaseDetail: 'dependency').phaseLabel,
        '',
      );
    });

    test('active states fall back to localized status labels', () {
      expect(
        remoteTaskSubtitle(
          _task(RemoteTaskStatus.waiting, phaseDetail: 'provider'),
        ),
        '等待同步',
      );
      expect(
        remoteTaskSubtitle(
          _task(RemoteTaskStatus.verifying, phaseDetail: 'verification'),
        ),
        '验证远端',
      );
    });

    test('cancel-progress sentences are state, not phase', () {
      expect(
        _task(
          RemoteTaskStatus.cancelRequested,
          phaseDetail: 'cancel requested; waiting for provider context to stop',
        ).phaseLabel,
        '',
      );
      expect(
        remoteTaskSubtitle(
          _task(
            RemoteTaskStatus.cancelRequested,
            phaseDetail:
                'cancel requested; waiting for provider context to stop',
          ),
        ),
        '正在取消',
      );
      expect(
        remoteTaskSubtitle(
          _task(
            RemoteTaskStatus.reconciling,
            phaseDetail: 'cancel requested; remote outcome is being reconciled',
          ),
        ),
        '正在对账',
      );
    });

    test('physical phases keep their labels', () {
      expect(
        _task(RemoteTaskStatus.running, phaseDetail: 'uploading').phaseLabel,
        '上传中',
      );
    });
  });

  group('blocked reasons localize known wire strings', () {
    test('journal dependency reason maps to Chinese', () {
      final task = _task(
        RemoteTaskStatus.blocked,
        blockedReason: 'waiting for journal dependencies',
      );
      expect(remoteTaskBlockedReasonLabel(task), '等待前置操作完成');
      expect(remoteTaskSubtitle(task), '等待前置操作完成');
    });

    test('unknown reasons pass through unchanged', () {
      final task = _task(
        RemoteTaskStatus.blocked,
        blockedReason: 'custom reason',
      );
      expect(remoteTaskBlockedReasonLabel(task), 'custom reason');
    });
  });

  group('journal event kinds localize', () {
    test('known kinds map to compact Chinese verbs', () {
      expect(remoteTaskEventKindLabel('write'), '写入');
      expect(remoteTaskEventKindLabel('mkdir'), '创建目录');
      expect(remoteTaskEventKindLabel('rename'), '重命名');
      expect(remoteTaskEventKindLabel('delete'), '删除');
    });

    test('unknown kinds pass through unchanged', () {
      expect(remoteTaskEventKindLabel('custom'), 'custom');
    });
  });

  group('remoteTaskEntryName derives the row title', () {
    test('takes the last path segment', () {
      expect(
        remoteTaskEntryName(
          _task(RemoteTaskStatus.waiting, targetPath: 'root/dir/file.txt'),
        ),
        'file.txt',
      );
      expect(
        remoteTaskEntryName(
          _task(RemoteTaskStatus.waiting, targetPath: 'dir/'),
        ),
        'dir',
      );
      expect(
        remoteTaskEntryName(
          _task(RemoteTaskStatus.waiting, targetPath: 'file.txt'),
        ),
        'file.txt',
      );
    });

    test('empty paths fall back to the kind label', () {
      expect(remoteTaskEntryName(_task(RemoteTaskStatus.waiting)), '写入文件');
    });
  });
}
