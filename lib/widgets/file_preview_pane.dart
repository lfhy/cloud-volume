// File preview pane is shared by the modal fallback and detached preview window.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:remote_storage/models/file_preview_source.dart';
import 'package:remote_storage/widgets/local_preview_image.dart';
import 'package:remote_storage/widgets/app_loading_indicator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

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

  static const Set<String> _allowedMarkdownLinkSchemes = {
    'http',
    'https',
    'mailto',
    'tel',
  };

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
    if (kind == FilePreviewKind.markdown) {
      final markdown = _markdown(context);
      if (markdown != null) {
        return markdown;
      }
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

  /// Markdown is loaded into the same validated local cache as images, so it
  /// can be rendered without giving a remote object URL to the widget tree.
  Widget? _markdown(BuildContext context) {
    final bytes = source?.bytes;
    if (bytes == null) {
      return null;
    }
    final theme = ShadTheme.of(context);
    final textStyle = TextStyle(
      color: theme.colorScheme.foreground,
      fontSize: 16,
      height: 1.55,
    );
    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: textStyle,
      h1: textStyle.copyWith(fontSize: 26, fontWeight: FontWeight.w700),
      h2: textStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      h3: textStyle.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      a: textStyle.copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      code: textStyle.copyWith(
        fontFamily: 'monospace',
        fontSize: 14,
        backgroundColor: theme.colorScheme.background,
      ),
      blockquote: textStyle.copyWith(color: theme.colorScheme.mutedForeground),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(6),
      ),
      tableBorder: TableBorder.all(color: theme.colorScheme.border),
    );
    return Semantics(
      label: 'Markdown 预览',
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: MarkdownBody(
            data: utf8.decode(bytes, allowMalformed: true),
            selectable: true,
            styleSheet: styleSheet,
            onTapLink: (_, href, _) => _openMarkdownLink(href),
            // Remote objects are untrusted Markdown. Never let their image
            // URIs trigger network, file-system, or data-URI loading.
            imageBuilder: (_, _, _) => Text(
              '（图片未加载）',
              style: textStyle.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openMarkdownLink(String? href) {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || !_allowedMarkdownLinkSchemes.contains(uri.scheme)) {
      return;
    }
    unawaited(_launchMarkdownLink(uri));
  }

  Future<void> _launchMarkdownLink(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A bad link must not tear down an otherwise usable file preview.
    }
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
    FilePreviewKind.markdown => Icons.article_outlined,
    FilePreviewKind.unsupported => Icons.visibility_off_outlined,
  };
}

String fallbackText(FilePreviewKind kind) {
  return switch (kind) {
    FilePreviewKind.video => '当前客户端暂不支持内嵌视频预览，需要下载后查看。',
    FilePreviewKind.pdf => '当前客户端暂不支持内嵌 PDF 预览，需要下载后查看。',
    FilePreviewKind.word => '当前客户端暂不支持内嵌 Word 预览，需要下载后查看。',
    FilePreviewKind.image => '当前图片无法预览，需要下载后查看。',
    FilePreviewKind.markdown => 'Markdown 内容无法加载，可以下载后查看。',
    FilePreviewKind.unsupported => '暂不支持该文件类型预览，需要下载后查看。',
  };
}
