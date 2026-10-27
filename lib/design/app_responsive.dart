// lib/design/app_responsive.dart — THE breakpoints of the app (D-061).
//
//   < mobile (700)          phone shell: bottom bar, one column
//   mobile … < desktop      rail shell: a narrow NavigationRail — tablets, landscape phones, narrow browser windows,
//                           on EVERY platform
//   >= desktop (1000)       wide shell: the sidebar + top bar
//
// Every role shell (student · teacher · parent · admin · organization) picks its shell with [Breakpoints.shellFor];
// content widgets use the [BreakpointCtx] getters. `responsive_framework` in main.dart only scales text / margins
// and is not a layout decision.
library;

import 'package:flutter/material.dart';

/// Which navigation shell a width gets.
enum AppShellKind { mobile, rail, wide }

class Breakpoints {
  /// Below: the phone shell. From here: the rail shell (and two-column content).
  static const double mobile = 700;

  /// From here: the wide shell (sidebar + top bar).
  static const double desktop = 1000;

  /// content max-width — content never stretches beyond this
  static const double contentMax = 860;

  /// sidebar width on web
  static const double sidebarW = 220;

  /// The shell for a window / constraints width.
  static AppShellKind shellFor(double width) {
    if (width >= desktop) return AppShellKind.wide;
    if (width >= mobile) return AppShellKind.rail;
    return AppShellKind.mobile;
  }
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
