library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter_education_app/core/personal_access.dart' show PersonalAccess;
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart'
    show TeacherCourseStatus, TeacherCourse;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/features/courses/student/details/components/app_responsive.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show DiscountInfoX;
import 'package:flutter_education_app/features/home/teacher/teacher_home_provider.dart';
import 'package:flutter_education_app/features/home/teacher/schedules/schedules_screen.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_infinite_scroll.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppActionCard, AppBorder, AppButton, AppHeroOverlap, AppHeroStat, AppIconSize, AppRadius, AppSheetContent, AppSpace, AppTouch, AppType, AppWidth, showAppSheet;
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/context_switcher.dart' show contextSwitchVisible, openOrgDashboard, showContextSwitcherSheet;
import 'package:flutter_education_app/features/courses/course_list_card.dart';
import 'package:flutter_education_app/features/courses/course_price_tag.dart' show coursePriceLabel;
import 'package:flutter_education_app/features/courses/course_scope.dart';
import 'package:flutter_education_app/features/courses/course_scope_bar.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/routing/web_history.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_view.dart' show EntityPanelAction;
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/entity_viewer_actions.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/features/home/teacher/classroom/teacher_classroom.dart';
import 'package:flutter_education_app/features/courses/teacher/courses_parts.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2Scope;
import 'package:flutter_education_app/utils/live_events.dart';

/// The teacher's "My courses" tab: the strip Courses · My students · Submissions · Reviews (D-290), then the courses:
/// the side (CourseScopeBanner — the app mode), ONE calm toolbar (search · All / Published / Drafts) and the shared
/// course cards (course_list_card.dart — the same card the student reads: rows on a phone, a grid of tiles wider; the
/// ⋮ menu holds edit · publish · schedule · delete). A card opens the course's panel (statistics, enrolled students,
/// reviews), and Open course its page.
class TeacherCoursesScreen extends StatefulWidget {
  const TeacherCoursesScreen({super.key});

  @override
  State<TeacherCoursesScreen> createState() => _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen> {
  final _searchCtrl = TextEditingController();
  final _panel = EntityPanelController(rowKind: EntityKind.course);
  TeacherSpace _space = TeacherSpace.tryParse(kIsWeb ? Uri.base.queryParameters['view'] : null) ?? TeacherSpace.courses;

  void _setSpace(TeacherSpace s) {
    if (s == _space) return;
    _panel.close();
    setState(() => _space = s);
    WebHistory.instance.setPageQuery(this, 'view', s == TeacherSpace.courses ? null : s.name);
  }

  void _openCoursePage(BuildContext context, EntityRef ref) {
    final course = context.read<TeacherCoursesProvider>().allCourses.where((c) => c.id == ref.id).firstOrNull;
    if (course != null) openTeacherCoursePage(context, course);
  }

  void _editCourse(BuildContext context, EntityRef ref) {
    final course = context.read<TeacherCoursesProvider>().allCourses.where((c) => c.id == ref.id).firstOrNull;
    if (course != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredCourseForm(course: course)));
  }

  List<EntityPanelAction> _actions(BuildContext context, EntityRef ref, EntitySummary? s) => [
        ...entityViewerActions(
          context, ref, s,
          controller: _panel,
          openCourse: s?.kind == EntityKind.course ? () => _openCoursePage(context, ref) : null,
        ),
        // the reference's second button: Edit beside Open course
        if (s != null && s.kind == EntityKind.course && s.can.manage && !courseFeatureOff('teacher_courses.edit'))
          EntityPanelAction(
            key: const ValueKey('md.edit_course'),
            icon: Icons.edit_outlined,
            label: 'edit'.tr,
            onPressed: () => _editCourse(context, ref),
          ),
      ];

  @override
  void initState() {
    super.initState();
    final courses = context.read<TeacherCoursesProvider>();
    // Any mutation made from this screen (create/update/publish/delete)
    // marks the home dashboard's stats + course preview stale, so it
    // refetches next time it's shown — without a hard dependency between
    // the two providers.
    courses.onCoursesChanged = () =>
        context.read<TeacherHomeProvider>().refreshSilently();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (courses.allCourses.isEmpty) courses.refresh();
    });
    // a publish review decided (docs/redesign/api/governance.md §1): the course's state changed on the server
    _reviewSub = LiveEvents.instance.listen({'course_review'}, (_) {
      if (mounted) courses.refresh();
    });
  }

  StreamSubscription<LiveEvent>? _reviewSub;

  @override
  void dispose() {
    _reviewSub?.cancel();
    _panel.dispose();
    WebHistory.instance.setPageQuery(this, 'view', null);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherCoursesProvider>();
    final me = context.select<MyAuthProvider, int?>((a) => a.currentUser?.id);
    final onCourses = _space == TeacherSpace.courses || me == null;

    final tabs = me != null && !courseFeatureOff('teacher_courses.classroom');
    // a desktop window: the wide calm card (the grid gets more columns instead of a narrow strip)
    return T2Scope(
      child: BasePage(
        key: const ValueKey('teacher_courses'),
        useWebCard: true,
        width: AppWidth.wide,
        appBar: ScreenAppBar(title: 't1_cs_tab_courses'.tr, showBack: !kIsWeb),
        // the panel's sheet sits where the button floats: no button while it is open
        floatingActionButton: ListenableBuilder(
          listenable: _panel,
          builder: (context, _) => context.showSidebar || p.scope.isOrg || !onCourses || _panel.isOpen || !PersonalAccess.enabled
              ? const SizedBox.shrink()
              : ParentComponent(
                  featureKey: 'teacher_courses.add',
                  child: _FloatingAddBtn(),
                ),
        ),
        child: SafeArea(
          bottom: false,
          child: onCourses
              ? MasterDetailScaffold(
                  controller: _panel,
                  rootLabel: 't1_cs_tab_courses'.tr,
                  deepLinks: true,
                  actions: (ref, s) => _actions(context, ref, s),
                  list: TeacherCoursesBody(controller: _searchCtrl, panel: _panel, onSpace: tabs ? _setSpace : null),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TeacherSpaceHero(space: _space, onSelect: _setSpace, overlap: false),
                  Expanded(child: TeacherSpaceList(space: _space, teacherId: me)),
                ]),
        ),
      ),
    );
  }
}

/// The page under the app bar (also what the visual renders pump with a seeded provider): the hero with the space strip
/// ([onSpace] given), the search and filter card riding up over it, then the course cards, in ONE scroll.
class TeacherCoursesBody extends StatelessWidget {
  const TeacherCoursesBody({super.key, required this.controller, this.panel, this.onSpace});

  final TextEditingController controller;

  /// The screen's panel: the list hands it its rows (Previous / Next, the row drawn as open).
  final EntityPanelController? panel;

  /// The space strip in the hero (Courses · My students · …); null draws no hero (the bare list).
  final ValueChanged<TeacherSpace>? onSpace;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherCoursesProvider>();
    return _CourseList(p: p, search: controller, panel: panel, header: _header(context, p));
  }

  Widget _header(BuildContext context, TeacherCoursesProvider p) {
    // wide screens have no floating button: "New course" sits in the hero (never in an organization, where a course
    // created here would be a personal one)
    final addInHero = context.showSidebar && !p.scope.isOrg && !courseFeatureOff('teacher_courses.add') && PersonalAccess.enabled;
    final hasSearch = !courseFeatureOff('teacher_courses.search');
    final hasFilter = !courseFeatureOff('teacher_courses.filters');
    final loaded = p.allCourses;
    final published = loaded.where((c) => c.isPublished).length;
    final total = p.totalCount > loaded.length ? p.totalCount : loaded.length;
    final rated = [for (final c in loaded) if ((c.rateSummary?.average ?? 0) > 0) c.rateSummary!.average];
    final stats = loaded.isEmpty
        ? const <AppHeroStat>[]
        : [
            AppHeroStat(value: '$total', label: 't1_cs_stat_courses'.tr),
            AppHeroStat(value: '$published', label: 't1_cs_stat_published'.tr),
            AppHeroStat(value: '${loaded.fold<int>(0, (a, c) => a + c.studentsCount)}', label: 't1_cs_stat_students'.tr),
            if (rated.isNotEmpty)
              AppHeroStat(
                value: (rated.reduce((a, b) => a + b) / rated.length).toStringAsFixed(1),
                label: 't1_cs_stat_rating'.tr,
              ),
          ];
    return ListenableBuilder(
      listenable: AppModeController.instance,
      builder: (context, _) {
        final scope = _ScopeHeader.visible(p) ? _ScopeHeader(p: p) : null;
        final card = TeacherCoursesToolbarCard(
          scope: scope,
          search: hasSearch
              ? CourseSearchField(controller: controller, hint: 't1_cs_search_courses', onChanged: p.setQuery)
              : null,
          filter: hasFilter
              ? CourseSegments<TeacherCourseStatus>(
                  selected: p.activeFilter,
                  onSelect: p.setFilter,
                  segments: [
                    CourseSegment(TeacherCourseStatus.all, 'filter_all'.tr, count: loaded.isEmpty ? null : total),
                    CourseSegment(TeacherCourseStatus.published, 'filter_published'.tr, count: loaded.isEmpty ? null : published),
                    CourseSegment(TeacherCourseStatus.draft, 'filter_drafts'.tr, count: loaded.isEmpty ? null : loaded.length - published),
                  ],
                )
              : null,
        );
        final body = _Centered(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              if (!card.isEmpty) card,
              // Pinned above the list: "Showing 24 of 134" + progress bar.
              if (p.totalCount > 12)
                ParentComponent(featureKey: 'teacher_courses.pagination', child: _CoursesProgress(p: p)),
            ]),
          ),
        );
        if (onSpace == null) return Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: body);
        return AppHeroOverlap(
          hero: TeacherSpaceHero(
            space: TeacherSpace.courses,
            onSelect: onSpace!,
            stats: stats,
            action: addInHero ? const _NewCourseButton() : null,
          ),
          body: body,
        );
      },
    );
  }
}

/// Centres [child] and caps it at the page's width.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: AppWidth.wide.max),
      child: child,
    ),
  );
}

/// Which side the list shows — the app mode: "My personal courses" or the organization — with its count, how many
/// courses wait on the other sides and "Switch". Drawn only for a teacher who has an organization or courses in one.
class _ScopeHeader extends StatelessWidget {
  const _ScopeHeader({required this.p});

  final TeacherCoursesProvider p;

  static bool visible(TeacherCoursesProvider p) {
    final ctl = AppModeController.instance;
    return !(p.scope.isAll || (!ctl.available && p.elsewhereCount == 0));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppModeController.instance,
    builder: (context, _) {
      final ctl = AppModeController.instance;
      final scope = p.scope;
      if (!visible(p)) return const SizedBox.shrink();
      // "+N in your organizations" leads to those courses: the organization's Courses page, where its teacher opens
      // each course (Exams, attendance, tools) — not the dashboard's home, where they could not be found
      final holding = scope.isPersonal ? orgsHoldingCourses(p.scopes) : const <CourseScopeCount>[];
      return CourseScopeBanner(
        scope: scope,
        org: scope.isOrg ? courseOrgFor(scope.orgId!, p.scopes, ctl.current) : null,
        count: p.scopes.isEmpty ? null : countFor(p.scopes, scope),
        elsewhere: p.elsewhereCount,
        onSwitch: contextSwitchVisible(ctl) ? () => showContextSwitcherSheet(context) : null,
        onShowElsewhere: holding.isEmpty ? null : () => openOrgCoursesOf(context, holding),
      );
    },
  );
}

/// Opens the Courses page of the organization holding [holding]'s courses (the organization dashboard on
/// Academics · Courses); with several organizations, a sheet asks which one first.
Future<void> openOrgCoursesOf(BuildContext context, List<CourseScopeCount> holding) async {
  Future<void> open(int orgId) => openOrgDashboard(context, orgId, section: 'academics', sub: 'courses');
  if (holding.length == 1) return open(holding.first.org!.id);
  await showAppSheet<void>(context, (ctx) {
    final c = ctx.colors;
    return AppSheetContent(
      title: 'ctx_organizations'.tr,
      children: [
        for (final h in holding)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppActionCard(
              key: ValueKey('course_scope.org.${h.org!.id}'),
              icon: Icons.account_balance_rounded,
              color: h.org!.argb != null ? Color(h.org!.argb!) : c.primary,
              title: h.org!.name,
              subtitle: countText(h.count, ar1: 'كورس واحد', ar2: 'كورسان', arFew: '{n} كورسات', arMany: '{n} كورسًا',
                  en1: '1 course', en: '{n} courses'),
              onTap: () {
                Navigator.pop(ctx);
                open(h.org!.id);
              },
            ),
          ),
      ],
    );
  });
}

/// Progress card (same widget the admin lists use). With "All" it reads
/// loaded / total from the server; with a filter it counts what that filter
/// shows (the screen keeps loading in the background until it has them all).
class _CoursesProgress extends StatelessWidget {
  const _CoursesProgress({required this.p});

  final TeacherCoursesProvider p;

  @override
  Widget build(BuildContext context) {
    final shown = p.filteredCourses.length;
    final done = !p.hasMore;
    if (shown == 0 && done) return const SizedBox.shrink();

    final all = p.activeFilter == TeacherCourseStatus.all;
    final total = all && p.totalCount > shown ? p.totalCount : shown;

    return PagedCountCard(
      loaded: shown,
      total: total,
      loadingMore: p.loadingMore || p.isLoading,
      done: done,
      icon: Icons.menu_book_rounded,
      margin: const EdgeInsets.only(top: AppSpace.xs),
    );
  }
}

void _openNewCourse(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredCourseForm()));

class _FloatingAddBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FloatingActionButton(
    heroTag: "add_course_float",
    key: const ValueKey("add_course_float"),
    tooltip: 'add_new_course'.tr,
    onPressed: () => _openNewCourse(context),
    backgroundColor: context.colors.primary,
    foregroundColor: context.colors.onHero,
    elevation: 2,
    child: const Icon(Icons.add_rounded, size: AppIconSize.lg),
  );
}

/// "New course" at the end of the toolbar on wide screens.
class _NewCourseButton extends StatelessWidget {
  const _NewCourseButton();

  @override
  Widget build(BuildContext context) => AppButton.primary(
    label: 't1_cs_new_course'.tr,
    icon: Icons.add_rounded,
    onPressed: () => _openNewCourse(context),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Course list — infinite scroll (AppInfiniteScroll, the one every course list uses)
//  • loads the next page when the end is near — also when the pages don't fill the screen
//  • while a filter is active it keeps loading until every course is loaded,
//    because the filter runs on the loaded courses
//  • the shared CourseCardSliver: rows on a phone, a grid of tiles wider
//  • last row: PagedListFooter ("Loading more…" / "All loaded")
// ═══════════════════════════════════════════════════════════════════════════════

class _CourseList extends StatefulWidget {
  const _CourseList({required this.p, required this.search, required this.header, this.panel});

  final TeacherCoursesProvider p;

  /// The hero and the search card: the first thing of the scroll in every state.
  final Widget header;
  final TextEditingController search;
  final EntityPanelController? panel;

  @override
  State<_CourseList> createState() => _CourseListState();
}

class _CourseListState extends State<_CourseList> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The scroll: [header], then [states] (the cards, or the skeleton / error / empty plate in their place).
  Widget _scrollOf(List<Widget> states) {
    final p = widget.p;
    final needEverything = p.activeFilter != TeacherCourseStatus.all;
    return AppInfiniteScroll(
      controller: _scroll,
      hasMore: p.hasMore,
      loading: p.isLoading || p.loadingMore,
      failed: p.loadMoreFailed,
      onLoadMore: p.loadMore,
      onRetry: () => p.loadMore(retry: true),
      threshold: needEverything ? double.infinity : 600,
      // Pull-to-refresh means "get me the latest": reload the first page.
      child: AppRefresh(
        onRefresh: p.refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [SliverToBoxAdapter(child: widget.header), ...states],
        ),
      ),
    );
  }

  Widget _plate(Widget child, {double height = 360}) =>
      SliverToBoxAdapter(child: _Centered(child: SizedBox(height: height, child: child)));

  @override
  Widget build(BuildContext context) {
    final p = widget.p;

    // A filter runs on the loaded courses: it must see every page (it keeps loading, the skeleton meanwhile).
    final needEverything = p.activeFilter != TeacherCourseStatus.all;
    if (p.isLoading && p.filteredCourses.isEmpty) {
      return _scrollOf([_plate(const CourseListSkeleton(), height: 520)]);
    }

    final error = p.hasError
        ? CourseListError(message: p.errorMessage ?? 'failed_to_load'.tr, onRetry: p.refresh)
        : null;
    // A failed first page used to fall through to "no courses yet": say it failed and offer a retry.
    if (error != null && p.allCourses.isEmpty) {
      return _scrollOf([SliverToBoxAdapter(child: _Centered(child: error))]);
    }

    final courses = p.filteredCourses;
    widget.panel?.siblings = [for (final c in courses) courseRefOf(c)];
    if (courses.isEmpty) {
      // Still looking through further pages for this filter.
      if (p.hasMore && !p.loadMoreFailed) {
        if (needEverything && !p.loadingMore) WidgetsBinding.instance.addPostFrameCallback((_) => p.loadMore());
        return _scrollOf([_plate(const CourseListSkeleton(), height: 520)]);
      }
      return _scrollOf([_plate(_empty(context, p))]);
    }

    final footer = PagedListFooter(
      loadingMore: p.loadingMore,
      hasMore: p.hasMore,
    );

    return _scrollOf([
      if (error != null) SliverToBoxAdapter(child: _Centered(child: error)),
      // the cards are real slivers (lazy), centred under the width cap
      SliverLayoutBuilder(
        builder: (context, sc) {
          final side = math.max(0.0, (sc.crossAxisExtent - AppWidth.wide.max) / 2) + AppSpace.md;
          return SliverPadding(
            padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, 0),
            sliver: CourseCardSliver(
              width: math.max(0.0, sc.crossAxisExtent - 2 * side),
              count: courses.length,
              itemBuilder: (_, i, shape) => _TeacherCourseCard(
                key: ValueKey(courses[i].id),
                course: courses[i],
                shape: shape,
              ),
            ),
          );
        },
      ),
      // room for the floating "Add course" button
      SliverPadding(
        padding: const EdgeInsets.only(bottom: AppSpace.xxl * 2),
        sliver: SliverToBoxAdapter(child: footer),
      ),
    ]);
  }

  Widget _empty(BuildContext context, TeacherCoursesProvider p) {
    // A search or filter is active: "nothing matches" and a way back.
    if (p.query.trim().isNotEmpty || p.activeFilter != TeacherCourseStatus.all) {
      return CourseListEmpty(
        icon: Icons.search_off_rounded,
        message: 'course_list_not_found'.tr,
        actionLabel: 'course_list_clear_search'.tr,
        onAction: () {
          widget.search.clear();
          p.setQuery('');
          p.setFilter(TeacherCourseStatus.all);
        },
      );
    }
    // Organization mode: its courses are given by the organization, so no
    // "add your first course" (that would create a personal one).
    if (p.scope.isOrg) {
      return CourseListEmpty(icon: Icons.apartment_rounded, message: 'course_scope_org_empty'.tr);
    }
    return CourseListEmpty(
      icon: Icons.school_outlined,
      message: 'add_first_course_hint'.tr,
      // a personal course needs the personal account (UX v3 phase 3)
      actionLabel: courseFeatureOff('teacher_courses.add') || !PersonalAccess.enabled ? null : 'add_new_course'.tr,
      onAction: () => _openNewCourse(context),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Course card — the shared CourseListCard with the teacher's status, figures and ⋮ menu
// ═══════════════════════════════════════════════════════════════════════════════

enum _CourseAction { edit, publish, schedule, copyLink, delete }

class _TeacherCourseCard extends StatelessWidget {
  const _TeacherCourseCard({super.key, required this.course, required this.shape});

  final TeacherCourse course;
  final CourseCardShape shape;

  Future<void> _confirmDelete(BuildContext context) async {
    final c = course;
    final title = (AppConfig.lang == 'ar' ? c.titleAr ?? c.titleEn : c.titleEn ?? c.titleAr) ?? '';
    final ok = await showTeacherDeleteCourseSheet(context, title: title, students: c.studentsCount);
    if (!ok || !context.mounted) return;
    final deleted = await context.read<TeacherCoursesProvider>().deleteCourse(c.id);
    if (deleted) showAppNotice('course_deleted'.tr);
  }

  Future<void> _togglePublish(BuildContext context) async {
    final p = context.read<TeacherCoursesProvider>();
    // a course waiting for review is withdrawn by the same unpublish (it goes back to a draft)
    if (course.isPublished || course.underReview) {
      await p.unpublishCourse(course.id);
      return;
    }
    final ok = await p.publishCourse(course.id);
    if (ok && p.isUnderReview(course.id)) showAppNotice('ow_course_sent_review'.tr);
  }

  void _act(BuildContext context, _CourseAction a) {
    switch (a) {
      case _CourseAction.edit:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredCourseForm(course: course)));
      case _CourseAction.publish:
        _togglePublish(context);
      case _CourseAction.schedule:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeacherSchedulesScreen(course: course)));
      case _CourseAction.copyLink:
        Clipboard.setData(ClipboardData(text: 'https://alfheemacademy.com/c/${course.id}'));
        showAppNotice('t1_cs_link_copied'.tr);
      case _CourseAction.delete:
        _confirmDelete(context);
    }
  }

  Widget? _menu(BuildContext context) {
    final c = context.colors;
    final actions = [
      if (!courseFeatureOff('teacher_courses.edit')) (_CourseAction.edit, Icons.edit_outlined, 'edit'.tr),
      if (!courseFeatureOff('teacher_courses.publish'))
        (
          _CourseAction.publish,
          course.isPublished || course.underReview ? Icons.visibility_off_outlined : Icons.public_rounded,
          course.isPublished
              ? 'unpublish_course'.tr
              : course.underReview
                  ? 'ow_course_withdraw'.tr
                  : 'publish_course'.tr,
        ),
      if (!courseFeatureOff('teacher_courses.card_details'))
        (_CourseAction.schedule, Icons.calendar_month_outlined, 't1_cs_weekly_slots'.tr),
      (_CourseAction.copyLink, Icons.link_rounded, 't1_cs_copy_link'.tr),
      if (!courseFeatureOff('teacher_courses.delete')) (_CourseAction.delete, Icons.delete_outline_rounded, 'delete'.tr),
    ];
    if (actions.isEmpty) return null;
    return SizedBox(
      width: AppTouch.min,
      height: AppTouch.min,
      child: PopupMenuButton<_CourseAction>(
        tooltip: 'course_list_more'.tr,
        padding: EdgeInsets.zero,
        iconSize: AppIconSize.md,
        // the reference's round ⋮ on a soft disc
        icon: DecoratedBox(
          decoration: BoxDecoration(color: c.kit.track, shape: BoxShape.circle),
          child: SizedBox.square(
            dimension: AppTouch.min - AppSpace.xs,
            child: Icon(Icons.more_vert_rounded, size: AppIconSize.md, color: c.textMedium),
          ),
        ),
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
        onSelected: (a) => _act(context, a),
        itemBuilder: (_) => [
          for (final (action, icon, label) in actions)
            PopupMenuItem(
              value: action,
              child: Row(children: [
                Icon(icon, size: AppIconSize.sm, color: action == _CourseAction.delete ? c.danger : c.textMedium),
                AppSpace.gapSm,
                Text(
                  label,
                  style: AppType.row(context).copyWith(color: action == _CourseAction.delete ? c.danger : c.textDark),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = course;
    final ar = AppConfig.lang == 'ar';
    final where = c.org?.name ?? (c.category == null ? null : (ar ? c.category!.nameAr : c.category!.nameEn));
    return CourseListCard(
      shape: shape,
      title: (ar ? c.titleAr ?? c.titleEn : c.titleEn ?? c.titleAr) ?? '',
      imageUrl: c.imageUrl,
      heroTag: 'courses-screen-${c.id}',
      chip: c.underReview
          ? CourseCoverChip(label: 'ow_course_under_review'.tr, icon: Icons.hourglass_top_rounded)
          : c.reviewRejected
              ? CourseCoverChip(label: 'ow_course_rejected'.tr, dot: context.colors.danger)
              : CourseCoverChip.status(context, published: c.isPublished),
      corner: _menu(context),
      meta: [
        c.type == 'live' ? 'course_list_live'.tr : 'course_list_recorded'.tr,
        ?where,
        if (c.reviewRejected && (c.reviewReason ?? '').trim().isNotEmpty) '${'ow_pq_reason_label'.tr}: ${c.reviewReason!.trim()}',
      ],
      priceLine: coursePriceLabel(c.currency, c.effectivePrice),
      isPrivate: c.isPrivate,
      footer: ParentComponent(
        featureKey: 'teacher_courses.card_stats',
        child: CourseStatsFooter(
          students: c.studentsCount,
          sessions: c.sessionsCount,
          rating: c.rateSummary?.average,
        ),
      ),
      onTap: () => EntityNavigator.open(context, courseRefOf(c)),
    );
  }
}

/// The ref of a course card (the card's own title and cover draw at once in the panel).
EntityRef courseRefOf(TeacherCourse c) =>
    EntityRef(EntityKind.course, c.id, label: c.titleAr, labelEn: c.titleEn, imageUrl: c.imageUrl);

/// The course's page: sessions, students, tools (what a card opened before the panel).
void openTeacherCoursePage(BuildContext context, TeacherCourse course) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ChangeNotifierProvider(
      create: (_) => TeacherCourseScreenProvider(initialCourse: course),
      child: deferredTeacherSessionsScreen(),
    ),
  ),
);
