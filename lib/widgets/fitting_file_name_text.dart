// Filename label with a pixel-aware gate: when the full name fits the
// available width it renders verbatim ("default_blurred.png", 19 chars,
// fits wide compact rows); only when it measurably does not fit does it
// fall back to compactDisplayName's character-budget truncation
// (head+tail+extension). This keeps the predictable truncation algorithm
// while removing its over-truncation on wide rows.

import 'package:flutter/material.dart';

import 'package:remote_storage/utils/display_name.dart';

class FittingFileNameText extends StatelessWidget {
  const FittingFileNameText({
    super.key,
    required this.name,
    required this.style,
    this.truncationMaxLength = 18,
  });

  final String name;
  final TextStyle style;

  /// Character budget handed to compactDisplayName when the full name does
  /// not fit (18 for wide compact rows, 14 for the narrow task row).
  final int truncationMaxLength;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = _fits(context, constraints.maxWidth)
            ? name
            : compactDisplayName(name, maxLength: truncationMaxLength);
        // Plain Text on purpose: semanticsLabel/Semantics wrappers change the
        // render-object shape that existing find.text helpers cast to.
        return Text(
          text,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  bool _fits(BuildContext context, double maxWidth) {
    if (maxWidth.isInfinite) return true;
    // Mirror Text.build's effective style: the ambient DefaultTextStyle
    // contributes the themed font family, and merging here keeps the
    // measurement on the same typeface the row actually renders with —
    // otherwise the gate can under-measure and admit names that only the
    // tail ellipsis can absorb (losing the extension again).
    final effective = style.inherit
        ? DefaultTextStyle.of(context).style.merge(style)
        : style;
    final painter = TextPainter(
      text: TextSpan(text: name, style: effective),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    final fits = painter.width <= maxWidth;
    painter.dispose();
    return fits;
  }
}
