// lib/design/app_hscroll.dart
//
// Wide content (tables, timetables, grids) that must be usable with a mouse on web / desktop:
//
//     AppHScroll(child: DataTable(...))
//
// • an always-visible scrollbar you can grab and drag (only painted when the content is wider than the view);
// • click-and-drag with the mouse / trackpad (Flutter only drags with touch by default);
// • shift + mouse wheel scrolls sideways (also when the browser already turned it into a horizontal delta).
//
// [AppScrollBehavior] is the app-wide behaviour set on MaterialApp.scrollBehavior: every scrollable can be dragged
// with the mouse, trackpad or stylus, not only with a finger.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Every pointer kind can drag a scrollable (mouse included — Flutter web scrolls only with touch by default).
const Set<PointerDeviceKind> kAppDragDevices = {
  PointerDeviceKind.touch,
  PointerDeviceKind.mouse,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.trackpad,
  PointerDeviceKind.unknown,
};

/// App-wide scroll behaviour: Material look + mouse / trackpad drag.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => kAppDragDevices;
}

/// Horizontal scroller for wide content, with a draggable always-visible scrollbar, mouse drag and shift+wheel.
class AppHScroll extends StatefulWidget {
  const AppHScroll({
    super.key,
    required this.child,
    this.controller,
    this.padding,
    this.thumbVisibility = true,
  });

  final Widget child;

  /// Optional — pass one to sync with another scroller (e.g. a sticky header row).
  final ScrollController? controller;

  /// Padding around the content. The default leaves room under it for the scrollbar.
  final EdgeInsetsGeometry? padding;

  final bool thumbVisibility;

  @override
  State<AppHScroll> createState() => _AppHScrollState();
}

class _AppHScrollState extends State<AppHScroll> {
  ScrollController? _own;

  ScrollController get _ctrl => widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  /// The inner Scrollable already handles horizontal deltas and shift+wheel on a physical wheel. This catches what it
  /// leaves (e.g. a browser that reports shift+wheel in a way the framework flips back to 0) — it only registers when
  /// the scroll would move, and the pointer-signal resolver lets the deepest scrollable win, so nothing scrolls twice.
  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final c = _ctrl;
    if (!c.hasClients) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final dx = e.scrollDelta.dx, dy = e.scrollDelta.dy;
    final d = dx != 0 ? dx : (shift ? dy : 0.0);
    if (d == 0) return;
    final p = c.position;
    final signed = Directionality.of(context) == TextDirection.rtl ? -d : d;
    final target = (p.pixels + signed).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (target == p.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      if (c.hasClients) c.position.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
      _ => false,
    };
    return ScrollConfiguration(
      // our own Scrollbar below; the default one would be a second, non-persistent bar
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: kAppDragDevices, scrollbars: false),
      child: Listener(
        onPointerSignal: _onSignal,
        child: Scrollbar(
          controller: c,
          thumbVisibility: widget.thumbVisibility,
          trackVisibility: widget.thumbVisibility && desktop,
          interactive: true,
          thickness: desktop ? 10 : null,
          radius: const Radius.circular(8),
          // only this scroller's bar — not a nested vertical list's
          notificationPredicate: (n) => n.depth == 0 && n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: c,
            scrollDirection: Axis.horizontal,
            padding: widget.padding ?? const EdgeInsets.only(bottom: 14),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
