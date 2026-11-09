// lib/design/app_header.dart — THE page header (D-360): one gradient, one back button, one collapse.
//
//   BasePage(
//     appBar: AppHeader(title: 'Students', subtitle: 'All departments', actions: [IconButton(…)], bottom: TabBar(…)),
//     child: ListView(…),
//   )
//
// The page needs no slivers: a Scaffold reports its body's scrolling to whatever sits inside it, so AppHeader shrinks
// when the page scrolls down and grows when it scrolls up, on any scrollable. A page too short to scroll stays open.
// Body-level headers (AppPageHeader, OrgPageHeader) share the same behaviour through [AppHeaderCollapse].
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_back_button.dart';
import 'app_focus_mode.dart';
import 'app_mesh.dart';
import 'app_tokens.dart';

/// Drives a header's collapse from the enclosing Scaffold's scrolling: [builder] gets 0 (open) … 1 (compact).
/// Stays compact while focus mode is on.
class AppHeaderCollapse extends StatefulWidget {
  const AppHeaderCollapse({super.key, required this.builder, this.child});

  final Widget Function(BuildContext context, Animation<double> collapse, Widget? child) builder;
  final Widget? child;

  /// Scrolled distance in one direction before the header reacts: a resting finger must not flicker it.
  static const double threshold = 14;

  /// A list must be able to scroll at least this far to collapse a header.
  static const double minScrollable = 140;

  @override
  State<AppHeaderCollapse> createState() => _AppHeaderCollapseState();
}

class _AppHeaderCollapseState extends State<AppHeaderCollapse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  ScrollNotificationObserverState? _observer;
  double _travel = 0;
  bool _target = false;

  @override
  void initState() {
    super.initState();
    AppFocusMode.instance.addListener(_applyFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ScrollNotificationObserver.maybeOf(context);
    if (!identical(next, _observer)) {
      _observer?.removeListener(_onScroll);
      _observer = next;
      _observer?.addListener(_onScroll);
    }
    _applyFocus(animate: false);
  }

  bool get _focused => AppFocusMode.activeIn(context);

  void _applyFocus({bool animate = true}) {
    if (!mounted) return;
    if (_focused) {
      _set(true, animate: animate);
    } else if (_target && _c.value == 1 && _travel == 0) {
      _set(false, animate: animate);
    }
  }

  void _set(bool collapsed, {bool animate = true}) {
    if (_target == collapsed && (_c.isAnimating || _c.value == (collapsed ? 1 : 0))) return;
    _target = collapsed;
    final to = collapsed ? 1.0 : 0.0;
    final d = AppMotion.of(context).base;
    if (!animate || d == Duration.zero) {
      _c.value = to;
    } else {
      _c.animateTo(to, duration: d, curve: Curves.easeOutCubic);
    }
  }

  void _onScroll(ScrollNotification n) {
    if (!mounted || _focused || n.metrics.axis != Axis.vertical || n.depth > 1) return;
    final m = n.metrics;
    // the content fits even with the header compact: nothing can bring it back by scrolling, so open it now
    if (m.maxScrollExtent <= 0) {
      _travel = 0;
      if (_target) _set(false);
      return;
    }
    if (m.pixels <= AppHeaderCollapse.threshold) {
      _travel = 0;
      if (_target) _set(false);
      return;
    }
    if (m.outOfRange) return;
    final double delta;
    if (n is ScrollUpdateNotification) {
      delta = n.scrollDelta ?? 0;
    } else if (n is UserScrollNotification && n.direction == ScrollDirection.idle) {
      _travel = 0;
      return;
    } else {
      return;
    }
    if (delta == 0) return;
    if (_travel != 0 && delta.sign != _travel.sign) _travel = 0;
    _travel += delta;
    if (_travel > AppHeaderCollapse.threshold && !_target && m.maxScrollExtent >= AppHeaderCollapse.minScrollable) {
      _set(true);
    } else if (_travel < -AppHeaderCollapse.threshold && _target) {
      _set(false);
    }
  }

  @override
  void dispose() {
    AppFocusMode.instance.removeListener(_applyFocus);
    _observer?.removeListener(_onScroll);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _c, widget.child);
}

/// The unified header. Goes in `BasePage.appBar` / `Scaffold.appBar`.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.onBack,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.color,
    this.seed = 0,
  });

  final String title;
  final String? subtitle;

  /// Draws [AppBackButton] at the start.
  final bool showBack;
  final VoidCallback? onBack;

  /// Replaces the back button (a close icon, a menu).
  final Widget? leading;

  /// Icon buttons or text buttons. They sit on a card-coloured tray, so their own ink stays readable on the gradient.
  final List<Widget> actions;

  /// Tabs under the title row; they never collapse.
  final PreferredSizeWidget? bottom;

  /// The main colour (the brand primary by default).
  final Color? color;
  final int seed;

  static const double compactHeight = 56;
  static const double openHeight = 88;
  static const double openHeightWithSubtitle = 104;

  /// The upper limit a Scaffold gives its app bar: the header draws itself shorter than this and the body follows.
  /// It covers text scale 1.3 (the header scales its own heights).
  @override
  Size get preferredSize => Size.fromHeight(openHeightWithSubtitle * 1.6 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.paddingOf(context).top;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final sub = subtitle;
    final hasSub = sub != null && sub.isNotEmpty;
    final open = (hasSub ? openHeightWithSubtitle : openHeight) * scale;
    final compact = compactHeight * (1 + (scale - 1) * 0.5);
    final titleOpen = AppType.headline(context).copyWith(color: c.onHero);
    final titleCompact = AppType.section(context).copyWith(color: c.onHero);
    final tabs = bottom;
    return AppHeaderCollapse(
      builder: (context, collapse, _) => RepaintBoundary(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: AppMeshSurface(
            color: color,
            seed: seed,
            drift: collapse,
            child: Padding(
              padding: EdgeInsets.only(top: top),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AnimatedBuilder(
                  animation: collapse,
                  builder: (context, _) {
                    final t = collapse.value;
                    return SizedBox(
                      height: lerpDouble(open, compact, t),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xxs),
                        child: Row(children: [
                          if (leading != null)
                            leading!
                          else if (showBack)
                            AppBackButton(onHero: true, onPressed: onBack)
                          else
                            const SizedBox(width: AppSpace.sm),
                          const SizedBox(width: AppSpace.xxs),
                          Expanded(
                            child: _TitleBlock(
                              title: title,
                              subtitle: hasSub ? sub : null,
                              style: TextStyle.lerp(titleOpen, titleCompact, t)!,
                              collapse: t,
                            ),
                          ),
                          _Tools(actions: actions),
                        ]),
                      ),
                    );
                  },
                ),
                if (tabs != null) _HeaderTabs(child: tabs),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.subtitle, required this.style, required this.collapse});

  final String title;
  final String? subtitle;
  final TextStyle style;
  final double collapse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = subtitle;
    // the subtitle is gone by the middle of the collapse, so it never crowds the shrinking title
    final subShare = (1 - collapse * 2).clamp(0.0, 1.0);
    return ClipRect(
      child: OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minHeight: 0,
        maxHeight: double.infinity,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Text(title, maxLines: collapse < 0.4 ? 2 : 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          if (sub != null && subShare > 0)
            ClipRect(
              child: Align(
                alignment: AlignmentDirectional.topStart,
                heightFactor: subShare,
                child: Opacity(
                  opacity: subShare,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xxs),
                    child: Text(sub,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The actions' tray, then the focus toggle.
class _Tools extends StatelessWidget {
  const _Tools({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (actions.isNotEmpty)
        AppHeaderTray(child: Row(mainAxisSize: MainAxisSize.min, children: actions)),
      const AppFocusToggle(onHero: true),
      const SizedBox(width: AppSpace.xxs),
    ]);
  }
}

/// The card-coloured tray that holds a header's actions: any action's own colours stay readable on the gradient.
class AppHeaderTray extends StatelessWidget {
  const AppHeaderTray({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Tabs drawn on the gradient, in the on-hero ink.
class _HeaderTabs extends StatelessWidget {
  const _HeaderTabs({required this.child});

  final PreferredSizeWidget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        tabBarTheme: theme.tabBarTheme.copyWith(
          labelColor: c.onHero,
          unselectedLabelColor: c.onHeroMuted,
          indicatorColor: c.onHero,
          dividerColor: Colors.transparent,
        ),
      ),
      child: SizedBox(height: child.preferredSize.height, child: child),
    );
  }
}
