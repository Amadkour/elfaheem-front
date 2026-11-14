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
//
// How WIDE a page body gets is its page-width role (D-304, [AppWidth] in app_tokens.dart): `BasePage(useWebCard:
// true, width: AppWidth.wide)` for a page card, [AppWidthBox] for any other body, [ContentBox] for a reading column.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Which navigation shell a width gets.
enum AppShellKind { mobile, rail, wide }

class Breakpoints {
  /// Below: the phone shell. From here: the rail shell (and two-column content).
  static const double mobile = 700;

  /// From here: the wide shell (sidebar + top bar).
  static const double desktop = 1000;

  /// content max-width of a reading column — the same 860 as [AppWidth.reading]
  static const double contentMax = 860;

  /// sidebar width on web
  static const double sidebarW = 248;

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

/// Constrains [child] to [Breakpoints.contentMax] (or [width]'s role) and centres it.
class ContentBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  /// The page-width role; null keeps the reading column ([Breakpoints.contentMax]).
  final AppWidth? width;

  const ContentBox({super.key, required this.child, this.padding, this.width});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width?.max ?? Breakpoints.contentMax),
          child: padding != null
              ? Padding(padding: padding!, child: child)
              : child,
        ),
      );
}

/// Centres a page body at its page-width role (D-304) with the responsive side gutter (16 · 24): the wrapper
/// for a body that is not a BasePage web card — a shell tab, a scrolling list, a detail column. With
/// [gutters] off the body keeps the role's max only (it pads itself).
///
///   AppWidthBox(width: AppWidth.wide, child: list)
class AppWidthBox extends StatelessWidget {
  const AppWidthBox({
    super.key,
    required this.width,
    required this.child,
    this.gutters = true,
    this.alignment = Alignment.topCenter,
  });

  final AppWidth width;
  final Widget child;
  final bool gutters;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (!box.hasBoundedWidth) return child;
        final w = gutters ? width.inside(box.maxWidth) : math.min(width.max, box.maxWidth);
        return Align(alignment: alignment, child: SizedBox(width: w, child: child));
      });
}
