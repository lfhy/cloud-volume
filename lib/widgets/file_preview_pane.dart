// File preview pane is shared by the modal fallback and detached preview window.

import 'package:flutter/material.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/widgets/local_preview_image.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FilePreviewPane extends StatelessWidget {
  const FilePreviewPane({
    super.key,
    required this.kind,
    this.source,
    this.localPath,
    this.loading = false,
    this.errorText,
  });

  final FilePreviewKind kind;
  final FilePreviewSource? source;
  final String? localPath;
  final bool loading;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: AppLoadingIndicator(size: 22, strokeWidth: 2.4),
      );
    }
    if (errorText != null) {
      return message(context, Icons.error_outline, errorText!);
    }
    if (kind == FilePreviewKind.image) {
      final image = _image(context);
      if (image != null) {
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: Center(child: image),
        );
      }
    }
    return message(context, iconForKind(kind), fallbackText(kind));
  }

  Widget? _image(BuildContext context) {
    final bytes = source?.bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: _brokenImage,
      );
    }
    final uri = source?.uri;
    if (uri != null) {
      return Image.network(
        uri.toString(),
        fit: BoxFit.contain,
        errorBuilder: _brokenImage,
      );
    }
    final path = localPath;
    if (path != null && path.trim().isNotEmpty) {
      return localPreviewImage(path: path, errorBuilder: _brokenImage);
    }
    return null;
  }

  Widget _brokenImage(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return message(context, Icons.broken_image_outlined, '图片预览失败，可以下载后查看。');
  }

  static Widget message(BuildContext context, IconData icon, String text) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.mutedForeground),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.mutedForeground,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData iconForKind(FilePreviewKind kind) {
  return switch (kind) {
    FilePreviewKind.video => Icons.movie_outlined,
    FilePreviewKind.pdf => Icons.picture_as_pdf_outlined,
    FilePreviewKind.word => Icons.description_outlined,
    FilePreviewKind.image => Icons.image_outlined,
    FilePreviewKind.unsupported => Icons.visibility_off_outlined,
  };
}

String fallbackText(FilePreviewKind kind) {
  return switch (kind) {
    FilePreviewKind.video => '当前客户端暂不支持内嵌视频预览，需要下载后查看。',
    FilePreviewKind.pdf => '当前客户端暂不支持内嵌 PDF 预览，需要下载后查看。',
    FilePreviewKind.word => '当前客户端暂不支持内嵌 Word 预览，需要下载后查看。',
    FilePreviewKind.image => '当前图片无法预览，需要下载后查看。',
    FilePreviewKind.unsupported => '暂不支持该文件类型预览，需要下载后查看。',
  };
}
