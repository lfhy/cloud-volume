// Display helpers keep physical mount-read ranges from replacing task paths.
import 'package:remote_storage/models/remote_task.dart';

extension RemoteTaskDisplay on RemoteTask {
  bool get isMountRead => phaseDetail.trim().toLowerCase() == 'mount_read';

  // Mounted reads store their current byte range in targetPath for monitor
  // compatibility, while sourcePath remains the object the user opened.
  String get operationPath {
    if (isMountRead && sourcePath.trim().isNotEmpty) {
      return sourcePath;
    }
    if (targetPath.trim().isNotEmpty) return targetPath;
    if (sourcePath.trim().isNotEmpty) return sourcePath;
    return displayPath;
  }

  String get mountReadRange => isMountRead ? targetPath.trim() : '';

  String get sourceTargetSummary {
    if ((kind == RemoteTaskKind.copy || kind == RemoteTaskKind.move) &&
        sourcePath.trim().isNotEmpty &&
        targetPath.trim().isNotEmpty) {
      return '$sourcePath -> $targetPath';
    }
    return '';
  }

  String get phaseLabel => switch (phaseDetail.trim().toLowerCase()) {
    'queued' || 'sync_wait' || 'upload_wait' => '等待执行',
    'uploading' => '上传中',
    'downloading' => '下载中',
    'deleting' => '删除中',
    'moving' => '移动中',
    'copying' => '复制中',
    'scanning' => '扫描中',
    'directory_child' => '目录文件',
    'mount_read' => '挂载读取',
    'verifying' => '验证远端',
    'installing' => '安装中',
    'preparing' => '准备更新',
    'cached' => '使用缓存',
    'cont' => '继续下载',
    _ => phaseDetail,
  };
}
