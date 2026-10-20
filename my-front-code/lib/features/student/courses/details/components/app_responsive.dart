/// app_responsive.dart — shared breakpoints & helpers
library;

import 'package:flutter/material.dart';

class Breakpoints {
  static const double mobile  = 700;
  static const double tablet  = 900;
  static const double desktop = 1200;

  /// content max-width — content never stretches beyond this
  static const double contentMax = 860;
  /// sidebar width on web
  static const double sidebarW   = 220;
}

extension BreakpointCtx on BuildContext {
  double get screenW => MediaQuery.of(this).size.width;
  bool get isMobile  => screenW < Breakpoints.mobile;
  bool get isTablet  => screenW >= Breakpoints.mobile && screenW < Breakpoints.desktop;
  bool get isDesktop => screenW >= Breakpoints.desktop;
  bool get showSidebar => screenW >= Breakpoints.mobile;
}

/// Constrains [child] to [Breakpoints.contentMax] and centres it.
class ContentBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const ContentBox({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: Breakpoints.contentMax),
          child: padding != null
              ? Padding(padding: padding!, child: child)
              : child,
        ),
      );
}
