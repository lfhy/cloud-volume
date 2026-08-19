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
}
