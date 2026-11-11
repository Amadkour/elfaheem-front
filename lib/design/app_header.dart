// lib/design/app_header.dart — THE page header (D-360, D-612): one surface, one back button, one collapse.
//
//   BasePage(
//     appBar: AppHeader(title: 'Students', subtitle: 'All departments', actions: [IconButton(…)], bottom: TabBar(…)),
//     child: ListView(…),
//   )
//
// A floating bar (D-648, after the Spike admin reference): one white rounded card ([ChromeCard]) inset by the page
// gutter, of the shell's top-bar height — the back button inside it, the title in the editorial page-title face in
// ink, the page's actions and the app-wide tools as ghosts. A page's own accent ([color], an exam's colour) draws a
// thin strip along the card's top. No gradient, no rule under it: the card is the edge.
//
// The page needs no slivers: a Scaffold reports its body's scrolling to whatever sits inside it, so AppHeader shrinks
// when the page scrolls down and grows when it scrolls up, on any scrollable. A page too short to scroll stays open.
// Body-level headers (AppPageHeader, OrgPageHeader) share the same behaviour through [AppHeaderCollapse].
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

import 'app_back_button.dart';
import 'chrome_button.dart' show ChromeCard;
import 'app_focus_mode.dart';
import 'app_responsive.dart';
import 'app_shell_nav.dart' show ShellChrome;
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
      _c.animateTo(to, duration: d, curve: AppMotion.curve);
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

/// The thin brand line on top of a header: solid primary (emerald), never the gradient's teal sweep. [color] is a
/// page's own accent (an exam's colour).
class AppHeaderStrip extends StatelessWidget {
  const AppHeaderStrip({super.key, this.color});

  final Color? color;

  /// Kept thin: a rule, not a band.
  static const double height = 2;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: ColoredBox(color: color ?? context.colors.primary),
        ),
      );
}

/// The warm hairline that closes a header.
class AppHeaderRule extends StatelessWidget {
  const AppHeaderRule({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          height: AppBorder.hairline,
          width: double.infinity,
          child: ColoredBox(color: context.colors.divider),
        ),
      );
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
    this.compact = false,
  });

  /// Tool screens (editors, designers): always the compact height, every pixel goes to the work area.
  final bool compact;

  final String title;
  final String? subtitle;

  /// Draws [AppBackButton] at the start.
  final bool showBack;
  final VoidCallback? onBack;

  /// Replaces the back button (a close icon, a menu). It sits on the canvas: draw it in ink, or as a [ChromePlate].
  final Widget? leading;

  /// Icon buttons or text buttons. They sit on a paper tray at the end of the title row.
  final List<Widget> actions;

  /// Tabs under the title row; they never collapse.
  final PreferredSizeWidget? bottom;

  /// The accent strip's colour (the brand primary by default).
  final Color? color;

  /// Kept for existing callers: the header no longer draws a gradient, so the seed changes nothing.
  final int seed;

  static const double compactHeight = 56;

  /// The open bar: the shell's top bar height, so a pushed page's bar matches the tab's (D-648).
  static const double openHeight = ChromeCard.barHeight;
  static const double openHeightWithSubtitle = 84;

  /// The upper limit a Scaffold gives its app bar: the header draws itself shorter than this and the body follows.
  /// It covers text scale 1.3 (the header scales its own heights).
  @override
  Size get preferredSize =>
      Size.fromHeight(openHeightWithSubtitle * 1.6 + AppSpace.lg + AppSpace.xs + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!compact && ShellChrome.ownsHeaderOf(context)) return _foldedIntoShell(context);
    final top = MediaQuery.paddingOf(context).top;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final sub = subtitle;
    final hasSub = sub != null && sub.isNotEmpty;
    final open = (hasSub ? openHeightWithSubtitle : openHeight) * scale;
    final shutHeight = compactHeight * (1 + (scale - 1) * 0.5);
    // the fallback: a title in the other script (a design or course name) still draws in full
    final titleOpen = AppType.pageTitle(context).copyWith(fontFamilyFallback: AppFonts.fallback);
    final titleCompact = AppType.section(context).copyWith(fontFamilyFallback: AppFonts.fallback);
    final tabs = bottom;
    Widget paint(BuildContext context, Animation<double> collapse) => RepaintBoundary(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Material(
            color: c.background,
            child: Padding(
              padding: EdgeInsets.only(top: top),
              // the floating bar (D-648): the card inset by the page gutter, the back button and the tools inside it
              child: LayoutBuilder(builder: (context, box) => ChromeCard(
                margin: appBarCardMargin(box.maxWidth),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // a page's own accent (an exam's colour) keeps its strip along the card's top
                if (color != null) AppHeaderStrip(color: color),
                AnimatedBuilder(
                  animation: collapse,
                  builder: (context, _) {
                    final t = collapse.value;
                    return SizedBox(
                      height: lerpDouble(open, shutHeight, t),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xxs),
                        child: Row(children: [
                          if (leading != null)
                            leading!
                          else if (showBack)
                            AppBackButton(onPressed: onBack)
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
              )),
            ),
          ),
        ),
      );
    if (compact) return paint(context, kAlwaysCompleteAnimation);
    return AppHeaderCollapse(builder: (context, collapse, _) => paint(context, collapse));
  }
}

/// A tab's first page under the shell's bar: the title is already up there, so only tabs and actions remain.
extension on AppHeader {
  Widget _foldedIntoShell(BuildContext context) {
    final c = context.colors;
    final tabs = bottom;
    if (tabs == null && actions.isEmpty && leading == null) return const SizedBox.shrink();
    return Material(
      color: c.background,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ?leading,
          Expanded(
            child: tabs == null
                ? const SizedBox(height: AppTouch.min)
                : SizedBox(height: tabs.preferredSize.height, child: _HeaderTabs(child: tabs)),
          ),
          ...actions,
          const SizedBox(width: AppSpace.xs),
        ]),
        const AppHeaderRule(),
      ]),
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
                    child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// In this order at the end of every header: the page's actions, the app-wide actions, the focus toggle last.
class _Tools extends StatelessWidget {
  const _Tools({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final global = MediaQuery.sizeOf(context).width >= Breakpoints.desktop ? ShellChrome.toolsOf(context) : null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (actions.isNotEmpty) ...[
        // inside the floating bar the actions stand bare: the card is their tray (D-648)
        ...actions,
        const SizedBox(width: AppSpace.xs),
      ],
      // the app-wide tools (calendar, messages, assistant, bell) draw as paper chips on the canvas, like the rest
      if (global != null) global(context),
      const AppFocusToggle(),
      const SizedBox(width: AppSpace.xs),
    ]);
  }
}

/// The paper tray that holds a header's actions: the card surface with a warm hairline, so the icon buttons inside
/// read as one group of chips, whatever their own colours.
class AppHeaderTray extends StatelessWidget {
  const AppHeaderTray({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.controlAll,
        side: BorderSide(color: c.divider, width: AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Tabs under the title: labels in ink, the chosen one under a 2 px ink rule (the underline tabs of the kit).
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
          labelColor: c.textDark,
          unselectedLabelColor: c.textMedium,
          indicatorColor: c.textDark,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          overlayColor: WidgetStatePropertyAll(c.textDark.withValues(alpha: 0.06)),
        ),
      ),
      child: SizedBox(height: child.preferredSize.height, child: child),
    );
  }
}

/// Where a page's floating bar sits (D-648): in from the sides by the page gutter, and from the top by the gutter on
/// wide pages (level with the shell's sidebar card) or a hair on phones, where every pixel of height counts.
EdgeInsets appBarCardMargin(double width) {
  final g = AppSpace.gutter(width);
  return EdgeInsets.fromLTRB(g, width < AppWidth.phoneMax ? AppSpace.xs : g, g, AppSpace.xs);
}
