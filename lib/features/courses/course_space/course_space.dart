// lib/features/courses/course_space/course_space.dart
//
// THE course page of the app, shared by the student's course details and the teacher's course studio (sessions
// screen). Plain values only — no provider is read here — so `test/ui/course_space_layout_test.dart` pumps it at
// every size, in both languages.
//
//   phone / tablet (< 1000)   hero (the cover full bleed, the hero block overlapping its foot) → spotlight cards →
//                             quick actions strip → PINNED tab bar → the active tab → footer, with an optional sticky
//                             bottom bar (price + enroll).
//   desktop (≥ 1000)          ONE scroll (D-944): the hero across the FULL width (chrome pinned above it; ONE block:
//                             the text and the call to action with the cover framed at 16:9 beside them, the stats
//                             as a balanced row under a hairline) → the spotlight cards → the shortcuts as one slim
//                             row → then two columns: pinned tab bar + the active tab + footer, and beside them the
//                             aside card (only when there is one: no empty side column).
//
// Warm Editorial (D-610 – D-629): the hero block is the page's one memorable thing — the title in the editorial
// serif, the figures that count up once and the emerald progress that fills; the spotlight cards rise in after it
// (the page's one orchestrated entrance); everything else is still paper on the canvas.
//
// Slots:
//   hero        CourseSpaceHeroData — title, pills, teacher, figures, progress, the block's tone and the role's ONE
//               call to action (cta, D-941: left out on a phone that has a bottomBar — price once, D-943)
//   spotlight   contextual cards ("live now", "continue learning", "open attendance", the setup checklist …).
//               A card that has nothing to say returns SizedBox.shrink() and leaves no gap.
//   actions     CourseSpaceAction tiles — every "go somewhere" entry of the course in one place
//   tabs        CourseSpaceTab — only the active one is built
//   aside       wide only: the side card (price + enroll, the teacher's course status …)
//   bottomBar   narrow only: e.g. the sticky price + enroll bar
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppRefresh, AppShimmer, AppSkeletonBox, AppListSkeleton, AppSpace, AppRadius, AppShadow, AppMotion, AppBlockTone;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal, AppEase;
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space_parts.dart';

export 'package:flutter_education_app/features/courses/course_space/course_space_parts.dart';
export 'package:flutter_education_app/features/courses/course_space/course_sessions.dart';
export 'package:flutter_education_app/features/courses/course_space/course_overview.dart';

/// The horizontal gutter every block of the page lines up on.
const double kCourseGutter = AppSpace.md;

/// Width of the side column on desktop.
const double kCourseAsideW = 340;

// ═════════════════════════════════════════════════════════════════════════════
// Plain values
// ═════════════════════════════════════════════════════════════════════════════

/// One figure of the hero's stats (students · sessions · hours · price · rating). With [onTap] the cell is drawn as a
/// button (a paper chip with a chevron), never as underlined text.
class CourseSpaceStat {
  const CourseSpaceStat({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
    this.featureKey,
    this.tone,
    this.footer,
    this.bars,
    this.barsCaption,
    this.warn = false,
  });

  final IconData icon;
  final String value, label;
  final VoidCallback? onTap;
  final String? featureKey;

  /// The hint under the figure ("12 lectures · 40 sections"), the mini bars of its recent values (oldest first) with
  /// their caption, and [warn] (something here is late) — the A2 count card's extras (D-1081, D-1090).
  final String? footer;
  final List<num>? bars;
  final String? barsCaption;
  final bool warn;

  /// The icon's colour when it means something (the rating's star in accent2); null → the block's muted ink.
  final Color? tone;
}

/// A labelled button of the hero's call to action.
class CourseSpaceButton {
  const CourseSpaceButton({required this.label, required this.onTap, this.icon, this.featureKey});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final String? featureKey;
}

/// The hero's call to action (D-941): the ONE primary action of the role (teacher: New session · enrolled student:
/// Continue · a visitor: Enroll), an optional [secondary] (Edit course), small [icons] (Share), the [price] beside
/// them for a visitor, and a [note] that stands in for the primary (a payment under review, contact support).
/// On a phone that has a [CourseSpace.bottomBar] the bar carries this action and the hero leaves it out.
class CourseSpaceCta {
  const CourseSpaceCta({this.price, this.primary, this.secondary, this.icons = const [], this.note, this.caption});

  final Widget? price;
  final CourseSpaceButton? primary;
  final CourseSpaceButton? secondary;

  /// Icon-only actions after the buttons (their [CourseSpaceTopAction.tooltip] is the label).
  final List<CourseSpaceTopAction> icons;
  final Widget? note;

  /// One quiet line under the buttons ("Up next: Functions").
  final String? caption;

  bool get isEmpty => price == null && primary == null && secondary == null && icons.isEmpty && note == null;
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

/// One action of the hero's top bar. The inline ones sit in ONE frosted capsule at the bar's end (share · favourite
/// · edit …); [overflow] ones go into its ⋮ menu (refresh on web / desktop, ask the documents …); a [primary] one
/// (the teacher's Edit) shows its [tooltip] as a label on wide screens.
class CourseSpaceTopAction {
  const CourseSpaceTopAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.featureKey,
    this.overflow = false,
    this.primary = false,
    this.selected,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  final String? featureKey;
  final bool overflow;
  final bool primary;

  /// A toggle (favourite): its on / off state for screen readers.
  final bool? selected;
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
    this.tone = AppBlockTone.peach,
    this.cta,
    this.coverImage,
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

  /// 0…1; the emerald bar under the figures when set (an enrolled student's progress).
  final double? progress;
  final String? progressLabel;

  /// The hero block's tint (peach: learning; sky for an information-led page).
  final AppBlockTone tone;

  /// The role's call to action, drawn in the hero (D-941).
  final CourseSpaceCta? cta;

  /// A cover already in hand (a picture just picked, a test image); else [imageUrl].
  final ImageProvider? coverImage;
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
            extent: CourseSpaceTabBar.heightFor(context, width: width, tabs: tabs),
            background: context.colors.pinnedBackground,
          ),
        ),
      if (active != null)
        SliverToBoxAdapter(
          // a tab is opened many times a day: a quick crossfade, no travel
          child: AnimatedSwitcher(
            duration: AppMotion.of(context).fast,
            switchInCurve: AppEase.out,
            switchOutCurve: AppEase.out,
            transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous.map((p) => Positioned(top: 0, left: 0, right: 0, child: p)), ?current],
            ),
            child: KeyedSubtree(key: ValueKey('course_tab_${active.id}'), child: active.builder(context)),
          ),
        ),
      if (footer != null) SliverToBoxAdapter(child: footer!),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
    ];
  }

  Widget _heroWidget({required bool rounded}) => CourseSpaceHero(
    data: hero,
    background: heroBackground,
    topActions: topActions,
    onBack: onBack,
    rounded: rounded,
    // a phone's sticky bottom bar is the call to action there: the hero does not repeat it (price once, D-943)
    showCta: rounded || bottomBar == null,
    // desktop: the bar is pinned over both columns ([_withBar]), not drawn in the scrolling masthead
    withBar: !rounded,
  );

  /// Desktop: the floating bar (Back + the page's actions, D-648) pinned over the page, then [body].
  Widget _withBar(Widget body) => onBack == null && topActions.isEmpty
      ? Padding(padding: const EdgeInsets.only(top: AppSpace.md), child: body)
      : Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(kCourseGutter, AppSpace.lg, kCourseGutter, AppSpace.xs),
        child: CourseSpaceBar(topActions: topActions, onBack: onBack),
      ),
      Expanded(child: body),
    ],
  );

  /// The page's one entrance: the spotlight cards rise in once, a beat apart, after the hero (which arrives with
  /// the route and then counts its figures and fills its bar).
  static List<Widget> _revealed(List<Widget> cards) => [
    for (final (i, w) in cards.indexed) AppReveal(index: i + 1, group: 'course_spotlight', rise: AppSpace.xs, child: w),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
      if (w < wideAt) return _narrow(context, w);
      return _wide(context, w);
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
                padding: const EdgeInsets.fromLTRB(kCourseGutter, AppSpace.md, kCourseGutter, 0),
                child: CourseSpotlightStack(children: _revealed(spotlight)),
              ),
            ),
          if (actions.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpace.md),
                child: CourseActionStrip(actions: actions),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xs)),
          ..._tabSlivers(context, w),
        ]),
      ),
      ?bottomBar,
    ],
  );

  /// Desktop (D-944): the hero, the spotlight cards and the shortcuts across the full width, then the tabs — with the
  /// aside card beside them when the page has one (SliverCrossAxisGroup: one scroll, the tab bar still pinned).
  Widget _wide(BuildContext context, double w) {
    final side = aside != null;
    return _withBar(_scroll(context, [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kCourseGutter, AppSpace.xs, kCourseGutter, 0),
          child: _heroWidget(rounded: true),
        ),
      ),
      if (spotlight.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kCourseGutter, AppSpace.md, kCourseGutter, 0),
            child: CourseSpotlightStack(children: _revealed(spotlight)),
          ),
        ),
      if (actions.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kCourseGutter, AppSpace.md, kCourseGutter, 0),
            child: CourseActionRow(actions: actions, title: actionsTitle),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.sm)),
      if (!side)
        ..._tabSlivers(context, w)
      else
        SliverCrossAxisGroup(
          slivers: [
            SliverCrossAxisExpanded(
              flex: 1,
              sliver: SliverMainAxisGroup(slivers: _tabSlivers(context, w - kCourseAsideW)),
            ),
            SliverConstrainedCrossAxis(
              maxExtent: kCourseAsideW,
              sliver: SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xs, kCourseGutter, kCourseGutter),
                sliver: SliverToBoxAdapter(child: aside),
              ),
            ),
          ],
        ),
    ]));
  }
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
    final lifted = overlapsContent || shrinkOffset > 0;
    return AnimatedContainer(
      duration: AppMotion.of(context).fast,
      curve: AppEase.out,
      // pinned over the list it floats: the faint level-1 lift, none at rest
      decoration: BoxDecoration(color: background, boxShadow: lifted ? AppShadow.card(context) : null),
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
              child: AppShimmer(child: AppSkeletonBox(height: wide ? 300 : 320, radius: wide ? AppRadius.block : 0)),
            ),
            const SizedBox(height: AppSpace.md),
            if (!wide)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: kCourseGutter),
                child: AppShimmer(child: AppSkeletonBox(height: 84, radius: AppRadius.card)),
              ),
            const SizedBox(height: AppSpace.sm),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: kCourseGutter),
              child: AppShimmer(child: AppSkeletonBox(height: 48, radius: AppRadius.control)),
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
                  AppShimmer(child: AppSkeletonBox(height: 220, radius: AppRadius.card)),
                  SizedBox(height: AppSpace.sm),
                  AppShimmer(child: AppSkeletonBox(height: 260, radius: AppRadius.card)),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
