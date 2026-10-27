// lib/design/app_refresh.dart — pull-to-refresh, ONE way for every list screen.
//
//   AppRefresh(onRefresh: provider.load, child: ListView(...))
//       the Material RefreshIndicator in the theme's colours. Every scrollable inside accepts the pull even when
//       its content is shorter than the screen (the scroll physics get an AlwaysScrollableScrollPhysics parent).
//   AppRefresh(scrollable: false, child: Column(...))
//       the child has no scroll view of its own: it is laid out inside one that fills the viewport
//       (`fill: true` gives it exactly the viewport height — for a child with an Expanded inside).
//   AppRefreshAction(onRefresh: provider.load)
//       the small refresh IconButton for an app bar: mouse users cannot pull, so it shows on web and desktop
//       (`always: true` shows it everywhere — for a section embedded in someone else's scroll view).
//
// Layout test: test/ui/app_refresh_layout_test.dart.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';

class AppRefresh extends StatelessWidget {
  const AppRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.scrollable = true,
    this.fill = false,
    this.edgeOffset = 0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// false: [child] has no scroll view — AppRefresh wraps it in one.
  final bool scrollable;

  /// With `scrollable: false`: give the child exactly the viewport height (bounded) instead of "at least".
  final bool fill;

  final double edgeOffset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = ScrollConfiguration.of(context);
    final physics = AlwaysScrollableScrollPhysics(parent: base.getScrollPhysics(context));
    final body = scrollable
        ? child
        : CustomScrollView(
            physics: physics,
            slivers: [SliverFillRemaining(hasScrollBody: fill, child: child)],
          );
    return RefreshIndicator(
      color: c.primary,
      backgroundColor: c.cardBg,
      edgeOffset: edgeOffset,
      onRefresh: onRefresh,
      child: ScrollConfiguration(behavior: base.copyWith(physics: physics), child: body),
    );
  }
}

/// The app-bar refresh button for platforms without a touch pull (web, desktop); [always] shows it everywhere.
class AppRefreshAction extends StatefulWidget {
  const AppRefreshAction({super.key, required this.onRefresh, this.always = false, this.color, this.size = 22});

  final Future<void> Function() onRefresh;
  final bool always;
  final Color? color;
  final double size;

  /// Whether this platform needs the button: no touch pull with a mouse.
  static bool get wanted =>
      kIsWeb || !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<AppRefreshAction> createState() => _AppRefreshActionState();
}

class _AppRefreshActionState extends State<AppRefreshAction> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.always && !AppRefreshAction.wanted) return const SizedBox.shrink();
    final c = context.colors;
    final color = widget.color ?? c.textDark;
    return IconButton(
      tooltip: 'refresh'.tr,
      onPressed: _busy ? null : _run,
      icon: _busy
          ? SizedBox(
              width: widget.size - 6,
              height: widget.size - 6,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
            )
          : Icon(Icons.refresh_rounded, size: widget.size, color: color),
    );
  }
}
