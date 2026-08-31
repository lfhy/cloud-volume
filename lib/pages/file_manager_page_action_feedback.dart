// 文件管理页的轻量反馈与错误提示；独立于上传/对象动作，保持行为文件易读。

part of 'file_manager_page.dart';

extension _FileManagerPageActionFeedback on _FileManagerPageState {
  void _showPageSnack(String message) {
    if (!mounted) {
      return;
    }
    showAppToast(context, message: message);
  }

  void _showPageError(Object error) {
    if (!mounted) {
      return;
    }
    _showPageMessage(title: '操作失败', message: describeBridgeError(error));
  }

  void _showPageMessage({required String title, required String message}) {
    if (!mounted) {
      return;
    }
    unawaited(
      showAppModal<void>(
        context: context,
        builder: (dialogContext) => AppShadDialog(
          title: Text(title),
          description: Text(message),
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(height: 12),
                ShadButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('知道了'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
