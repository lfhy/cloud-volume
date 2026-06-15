// Desktop local preview image renders cached files by path.

import 'dart:io';

import 'package:flutter/material.dart';

Widget localPreviewImage({
  required String path,
  required ImageErrorWidgetBuilder errorBuilder,
}) {
  return Image.file(
    File(path),
    fit: BoxFit.contain,
    errorBuilder: errorBuilder,
  );
}
