// lib/features/shared/course/course_space/course_space.dart
//
// THE course page of the app, shared by the student's course details and the teacher's course studio (sessions
// screen). Plain values only — no provider is read here — so `test/ui/course_space_layout_test.dart` pumps it at
// every size, in both languages.
//
//   phone / tablet (< 1000)   hero (full bleed) → spotlight cards → quick actions strip → PINNED tab bar →
//                             the active tab → footer, with an optional sticky bottom bar (price + enroll).
//   desktop (≥ 1000)          main column: hero (rounded) → pinned tab bar → the active tab → footer;
//                             side column (sticky, own scroll): aside card → spotlight cards → quick actions list.
//
// Slots:
//   hero        CourseSpaceHeroData — title, pills, teacher, glass stats strip, progress ring
//   spotlight   contextual cards ("live now", "continue learning", "open attendance", the setup checklist …).
//               A card that has nothing to say returns SizedBox.shrink() and leaves no gap.
//   actions     CourseSpaceAction tiles — every "go somewhere" entry of the course in one place
//   tabs        CourseSpaceTab — only the active one is built
//   aside       wide only: the side card (price + enroll, the teacher's course status …)
//   bottomBar   narrow only: e.g. the sticky price + enroll bar
library;

import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../design/app_kit.dart' show AppRefresh, AppShimmer, AppSkeletonBox, AppListSkeleton;
import '../../../../design/app_responsive.dart';
import 'course_space_parts.dart';

export 'course_space_parts.dart';

/// The horizontal gutter every block of the page lines up on.
const double kCourseGutter = 16;

/// Width of the side column on desktop.
const double kCourseAsideW = 340;

// ═════════════════════════════════════════════════════════════════════════════
// Plain values
// ═════════════════════════════════════════════════════════════════════════════

/// One number of the hero's glass strip (students · lessons · hours …).
class CourseSpaceStat {
  const CourseSpaceStat({required this.icon, required this.value, required this.label, this.onTap, this.featureKey});

  final IconData icon;
  final String value, label;
  final VoidCallback? onTap;
  final String? featureKey;
}

/// A small pill on the hero (live · recorded · certificate · draft …).
class CourseSpaceBadge {
  const CourseSpaceBadge({required this.label, this.icon, this.color, this.featureKey});

  final String label;
  final IconData? icon;

  /// Filled pill in this colour; null → the glass pill.
  final Color? color;
  final String? featureKey;
}

/// A round glass button in the hero's top bar.
class CourseSpaceTopAction {
  const CourseSpaceTopAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.featureKey,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  final String? featureKey;
}

/// Everything the hero shows.
class CourseSpaceHeroData {
  const CourseSpaceHeroData({
    required this.title,
    this.subtitle,
    this.imageUrl = '',
    this.category,
    this.isPrivate = false,
    this.privateLabel,
    this.badges = const [],
    this.teacherName,
    this.teacherImageUrl,
    this.onTeacher,
    this.stats = const [],
    this.progress,
    this.progressLabel,
  });

  final String title;
  final String? subtitle;
  final String imageUrl;
  final String? category;
  final bool isPrivate;
  final String? privateLabel;
  final List<CourseSpaceBadge> badges;
  final String? teacherName, teacherImageUrl;
  final VoidCallback? onTeacher;
  final List<CourseSpaceStat> stats;

  /// 0…1; a ring at the end of the stats strip when set (an enrolled student's progress).
  final double? progress;
  final String? progressLabel;
}

/// One entry of the quick actions (course profile · attendance · students · schedule · support …).
class CourseSpaceAction {
  const CourseSpaceAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
    this.color,
    this.badge,
    this.featureKey,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback onTap;

  /// Tint of the icon tile; null → primary.
  final Color? color;

  /// A short count / word drawn on the icon's corner ("3", "new").
  final String? badge;
  final String? featureKey;
}

/// One tab of the page. Only the active tab's [builder] runs.
class CourseSpaceTab {
  const CourseSpaceTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
    this.count,
    this.live = false,
    this.featureKey,
  });

  final String id;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
  final int? count;

  /// A pulsing dot (a live session is running).
  final bool live;
  final String? featureKey;
}

// ═════════════════════════════════════════════════════════════════════════════
// Scaffold
// ═════════════════════════════════════════════════════════════════════════════

class CourseSpace extends StatelessWidget {
  const CourseSpace({
    super.key,
    required this.hero,
    required this.tabs,
    required this.activeTab,
    required this.onTab,
    this.heroBackground,
    this.topActions = const [],
    this.onBack,
    this.onRefresh,
    this.spotlight = const [],
    this.actions = const [],
    this.actionsTitle,
    this.aside,
    this.bottomBar,
    this.footer,
    this.onNearEnd,
    this.wideAt = Breakpoints.desktop,
  });

  final CourseSpaceHeroData hero;

  /// Replaces the cover image (the intro reel). Null → the cover image over the brand gradient.
  final Widget? heroBackground;
  final List<CourseSpaceTopAction> topActions;
  final VoidCallback? onBack;
  final Future<void> Function()? onRefresh;
  final List<Widget> spotlight;
  final List<CourseSpaceAction> actions;
  final String? actionsTitle;
  final List<CourseSpaceTab> tabs;
  final String activeTab;
  final ValueChanged<String> onTab;
  final Widget? aside;
  final Widget? bottomBar;
  final Widget? footer;

  /// Called when the main scroll gets near its end (the next page of sessions).
  final VoidCallback? onNearEnd;

  /// From this width: the two-column layout.
  final double wideAt;

  /// The tabs the kill switches leave on.
  List<CourseSpaceTab> get _shown => [
    for (final t in tabs)
      if (t.featureKey == null || !AppConfig.disableList.contains(t.featureKey)) t,
  ];

  int get _visibleTabs => _shown.length;

  /// The active tab, or the first one shown when it is switched off.
  CourseSpaceTab? get _active {
    final shown = _shown;
    if (shown.isEmpty) return null;
    return shown.firstWhere((t) => t.id == activeTab, orElse: () => shown.first);
  }

  bool _onScroll(ScrollNotification n) {
    if (onNearEnd != null && n.metrics.axis == Axis.vertical && n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
      onNearEnd!();
    }
    return false;
  }

  Widget _scroll(BuildContext context, List<Widget> slivers) {
    Widget view = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: slivers,
    );
    view = NotificationListener<ScrollNotification>(onNotification: _onScroll, child: view);
    return onRefresh == null ? view : AppRefresh(onRefresh: onRefresh!, child: view);
  }

  List<Widget> _tabSlivers(BuildContext context, double width) {
    final active = _active;
    return [
      if (_visibleTabs > 1)
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            tabs: tabs,
            active: active?.id ?? '',
            onTab: onTab,
            extent: CourseSpaceTabBar.heightFor(context, width: width, count: _visibleTabs),
            background: context.colors.background,
          ),
        ),
      if (active != null)
        SliverToBoxAdapter(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous.map((p) => Positioned(top: 0, left: 0, right: 0, child: p)), ?current],
            ),
            child: KeyedSubtree(key: ValueKey('course_tab_${active.id}'), child: active.builder(context)),
          ),
        ),
      if (footer != null) SliverToBoxAdapter(child: footer!),
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ];
  }

  Widget _heroWidget({required bool rounded}) => CourseSpaceHero(
    data: hero,
    background: heroBackground,
    topActions: topActions,
    onBack: onBack,
    rounded: rounded,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
      final side = aside != null || spotlight.isNotEmpty || actions.isNotEmpty;
      if (w < wideAt) return _narrow(context, w);
      return side ? _wide(context, w - kCourseAsideW) : _single(context, w);
    },
  );

  Widget _narrow(BuildContext context, double w) => Column(
    children: [
      Expanded(
        child: _scroll(context, [
          SliverToBoxAdapter(child: _heroWidget(rounded: false)),
          if (spotlight.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(kCourseGutter, 16, kCourseGutter, 0),
                child: CourseSpotlightStack(children: spotlight),
              ),
            ),
          if (actions.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: CourseActionStrip(actions: actions),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ..._tabSlivers(context, w),
        ]),
      ),
      ?bottomBar,
    ],
  );

  /// Desktop with nothing for the side column: one column, the hero as a rounded card.
  Widget _single(BuildContext context, double w) => _scroll(context, [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kCourseGutter, kCourseGutter, kCourseGutter, 8),
        child: _heroWidget(rounded: true),
      ),
    ),
    ..._tabSlivers(context, w),
  ]);

  Widget _wide(BuildContext context, double w) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _scroll(context, [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(kCourseGutter, kCourseGutter, 8, 8),
              child: _heroWidget(rounded: true),
            ),
          ),
          ..._tabSlivers(context, w),
        ]),
      ),
      SizedBox(
        width: kCourseAsideW,
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(8, kCourseGutter, kCourseGutter, kCourseGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (aside != null) ...[aside!, const SizedBox(height: 14)],
              if (spotlight.isNotEmpty) ...[CourseSpotlightStack(children: spotlight), const SizedBox(height: 14)],
              if (actions.isNotEmpty) CourseActionList(actions: actions, title: actionsTitle),
            ],
          ),
        ),
      ),
    ],
  );
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate({
    required this.tabs,
    required this.active,
    required this.onTab,
    required this.extent,
    required this.background,
  });

  final List<CourseSpaceTab> tabs;
  final String active;
  final ValueChanged<String> onTab;
  final double extent;
  final Color background;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = context.colors;
    final lifted = overlapsContent || shrinkOffset > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: background,
        boxShadow: lifted
            ? [BoxShadow(color: c.heroShade.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 6))]
            : null,
      ),
      // fills the whole extent: a pinned header whose child is shorter fails its geometry check
      child: SizedBox(height: extent, child: Center(child: CourseSpaceTabBar(tabs: tabs, active: active, onTab: onTab))),
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) =>
      old.active != active || old.tabs != tabs || old.extent != extent || old.background != background;
}

// ═════════════════════════════════════════════════════════════════════════════
// First-load skeleton (the page's own shape, so nothing jumps)
// ═════════════════════════════════════════════════════════════════════════════

class CourseSpaceSkeleton extends StatelessWidget {
  const CourseSpaceSkeleton({super.key, this.wideAt = Breakpoints.desktop});

  final double wideAt;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
      final wide = w >= wideAt;
      final main = SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: wide ? const EdgeInsets.all(kCourseGutter) : EdgeInsets.zero,
              child: AppShimmer(child: AppSkeletonBox(height: wide ? 300 : 320, radius: wide ? 28 : 0)),
            ),
            const SizedBox(height: 16),
            if (!wide)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: kCourseGutter),
                child: AppShimmer(child: AppSkeletonBox(height: 84, radius: 18)),
              ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: kCourseGutter),
              child: AppShimmer(child: AppSkeletonBox(height: 48, radius: 16)),
            ),
            const AppListSkeleton(items: 4),
          ],
        ),
      );
      if (!wide) return main;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: main),
          const SizedBox(
            width: kCourseAsideW,
            child: Padding(
              padding: EdgeInsets.all(kCourseGutter),
              child: Column(
                children: [
                  AppShimmer(child: AppSkeletonBox(height: 220, radius: 24)),
                  SizedBox(height: 14),
                  AppShimmer(child: AppSkeletonBox(height: 260, radius: 24)),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
