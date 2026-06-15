// File access transfer requests expose queue tasks while callers await paths.

import 'dart:async';

import 'package:remote_storage/models/s3_objects.dart';
import 'package:remote_storage/state/transfer_queue.dart';

typedef FileAccessDirectoryLister =
    Future<List<ObjectInfo>> Function(String prefix);

class FileAccessTransferRequest {
  const FileAccessTransferRequest({required this.completion, this.task});

  final Future<String> completion;
  final TransferTask? task;
}

Future<void> waitForTransferTaskSuccess(String taskId) {
  final queue = TransferQueue.instance;
  final completer = Completer<void>();

  void completeFromTask() {
    final task = queue.tasks.where((task) => task.id == taskId).firstOrNull;
    if (task == null || !task.isFinished) {
      return;
    }
    queue.removeListener(completeFromTask);
    if (task.status == TransferStatus.done) {
      completer.complete();
    } else if (task.status == TransferStatus.canceled) {
      completer.completeError(StateError('下载已取消'));
    } else {
      completer.completeError(StateError(task.error ?? '下载失败'));
    }
  }

  queue.addListener(completeFromTask);
  completeFromTask();
  return completer.future;
}
