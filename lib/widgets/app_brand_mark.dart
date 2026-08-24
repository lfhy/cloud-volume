// Shared brand logo used by the sidebar and setup screen.

import 'package:flutter/material.dart';
import 'package:remote_storage/app/app_brand.dart';
import 'package:remote_storage/theme/theme_controller.dart';
import 'package:remote_storage/widgets/app_brand_logo_svg.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.height = 40, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final accent = ThemeController.of(context).accent.color;
    final iconHeight = height.clamp(24.0, 56.0);
    final iconWidth = iconHeight * (72 / 52);
    final availableWidth = width;
    final textScale = (iconHeight / 40).clamp(0.78, 1.2);
    final titleStyle = TextStyle(
      fontSize: 28 * textScale,
      height: 1,
      fontWeight: FontWeight.w800,
      color: const Color(0xff0f172a),
      letterSpacing: -0.8,
    );
    final subtitleStyle = TextStyle(
      fontSize: 10.5 * textScale,
      height: 1.1,
      fontWeight: FontWeight.w500,
      color: const Color(0xff64748b),
      letterSpacing: 0.1,
    );

    final brandText = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(appBrandName, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
        const SizedBox(height: 3),
        Text(
          'cloud-volumn',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: subtitleStyle,
        ),
      ],
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.string(
          buildAppBrandIconSvg(accent),
          height: iconHeight,
          width: iconWidth,
        ),
        SizedBox(width: 12 * textScale),
        Flexible(child: brandText),
      ],
    );

    if (availableWidth != null) {
      return SizedBox(width: availableWidth, child: content);
    }
    return content;
  }
}
