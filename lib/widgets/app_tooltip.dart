// App tooltip keeps desktop hints consistent while avoiding touch-hover state
// on Android icon controls.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AppTooltip extends StatelessWidget {
  const AppTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // ShadTooltip turns an Android tap into a persistent hover toggle. A
    // system Back or route change cannot send it the matching leave event, so
    // touch surfaces expose the same name through accessibility only.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return Semantics(label: message, child: child);
    }
    return ShadTooltip(builder: (context) => Text(message), child: child);
  }
}
