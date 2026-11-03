library;

import 'dart:math' as math;

import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/courses/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart'
    show TeacherCourseStatus, TeacherCourse;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
import 'package:provider/provider.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_bar.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../../student/models.dart' show DiscountInfoX;
import '../home/teacher_home_provider.dart';
import '../schedules/schedules_screen.dart';
import '../sessions/sessions_provider.dart';
import '../sessions/sessions_screen.dart';
import 'course_form_screen.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_infinite_scroll.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppActionCard, AppSheetHeader, appConfirm, appText, showAppSheet;
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/context_switcher.dart' show contextSwitchVisible, openOrgDashboard, showContextSwitcherSheet;
import 'package:flutter_education_app/features/shared/course/course_list_card.dart';
import 'package:flutter_education_app/features/shared/course/course_price_tag.dart' show coursePriceLabel;
import 'package:flutter_education_app/features/shared/course/course_scope.dart';
import 'package:flutter_education_app/features/shared/course/course_scope_bar.dart';
import 'package:flutter_education_app/design/home_kit.dart' show homeCardWidth, kHomeWideMax;

/// The teacher's "My courses": the side (CourseScopeBanner — the app mode), ONE calm toolbar (search · All /
/// Published / Drafts) and the shared course cards (course_list_card.dart — the same card the student reads:
/// rows on a phone, a grid of tiles wider; the ⋮ menu holds edit · publish · schedule · delete).
class TeacherCoursesScreen extends StatefulWidget {
  const TeacherCoursesScreen({super.key});

  @override
  State<TeacherCoursesScreen> createState() => _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen> {
  final _searchCtrl = TextEditingController();

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
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherCoursesProvider>();

    // a desktop window: the home's wide calm card (the grid gets four columns instead of a narrow strip)
    return LayoutBuilder(
      builder: (context, area) => BasePage(
      key: const ValueKey('teacher_courses'),
      useWebCard: true,
      maxWith: homeCardWidth(area.maxWidth),
      appBar: ScreenAppBar(title: 'my_courses'.tr, showBack: !kIsWeb),
      floatingActionButton: context.showSidebar || p.scope.isOrg
          ? null
          : ParentComponent(
              featureKey: 'teacher_courses.add',
              child: _FloatingAddBtn(),
            ),
      child: SafeArea(
        bottom: false,
        child: TeacherCoursesBody(controller: _searchCtrl),
      ),
    ),
    );
  }
}

/// The page under the app bar (also what the visual renders pump with a seeded provider).
class TeacherCoursesBody extends StatelessWidget {
  const TeacherCoursesBody({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherCoursesProvider>();
    // wide screens have no floating button: "New course" sits at the end of the toolbar (never in an organization,
    // where a course created here would be a personal one)
    final addInToolbar = context.showSidebar && !p.scope.isOrg && !courseFeatureOff('teacher_courses.add');
    final hasSearch = !courseFeatureOff('teacher_courses.search');
    final hasFilter = !courseFeatureOff('teacher_courses.filters');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner + toolbar + progress share one centred, width-capped block so they line up with the list.
        _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScopeHeader(p: p),
              if (hasSearch || hasFilter || addInToolbar)
                CourseListToolbar(
                  search: hasSearch
                      ? CourseSearchField(
                          controller: controller,
                          hint: 'search_course_by_name_description',
                          onChanged: p.setQuery,
                        )
                      : null,
                  filter: hasFilter
                      ? CourseSegments<TeacherCourseStatus>(
                          selected: p.activeFilter,
                          onSelect: p.setFilter,
                          segments: [
                            CourseSegment(TeacherCourseStatus.all, 'filter_all'.tr),
                            CourseSegment(TeacherCourseStatus.published, 'filter_published'.tr),
                            CourseSegment(TeacherCourseStatus.draft, 'filter_drafts'.tr),
                          ],
                        )
                      : null,
                  action: addInToolbar ? const _NewCourseButton() : null,
                ),
              // Pinned above the list: "Showing 24 of 134" + progress bar.
              if (p.totalCount > 12)
                ParentComponent(
                  featureKey: 'teacher_courses.pagination',
                  child: _CoursesProgress(p: p),
                ),
            ],
          ),
        ),
        Expanded(child: _CourseList(p: p, search: controller)),
      ],
    );
  }
}

/// Centres [child] and caps it at the desktop home's width.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kHomeWideMax),
      child: child,
    ),
  );
}

/// Which side the list shows — the app mode: "My personal courses" or the organization — with its count, how many
/// courses wait on the other sides and "Switch". Drawn only for a teacher who has an organization or courses in one.
class _ScopeHeader extends StatelessWidget {
  const _ScopeHeader({required this.p});

  final TeacherCoursesProvider p;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppModeController.instance,
    builder: (context, _) {
      final ctl = AppModeController.instance;
      final scope = p.scope;
      if (scope.isAll || (!ctl.available && p.elsewhereCount == 0)) {
        return const SizedBox.shrink();
      }
      // "+N in your organizations" leads to those courses: the organization's Courses page, where its teacher opens
      // each course (Exams, attendance, tools) — not the dashboard's home, where they could not be found
      final holding = scope.isPersonal ? orgsHoldingCourses(p.scopes) : const <CourseScopeCount>[];
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: CourseScopeBanner(
          scope: scope,
          org: scope.isOrg ? courseOrgFor(scope.orgId!, p.scopes, ctl.current) : null,
          count: p.scopes.isEmpty ? null : countFor(p.scopes, scope),
          elsewhere: p.elsewhereCount,
          onSwitch: contextSwitchVisible(ctl) ? () => showContextSwitcherSheet(context) : null,
          onShowElsewhere: holding.isEmpty ? null : () => openOrgCoursesOf(context, holding),
        ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader('ctx_organizations'.tr),
        for (final h in holding)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
      ]),
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    );
  }
}

void _openNewCourse(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CourseFormScreen()));

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
    child: const Icon(Icons.add_rounded, size: 26),
  );
}

/// "New course" at the end of the toolbar on wide screens.
class _NewCourseButton extends StatelessWidget {
  const _NewCourseButton();

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: () => _openNewCourse(context),
    style: FilledButton.styleFrom(
      backgroundColor: context.colors.primary,
      foregroundColor: context.colors.onHero,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: const Icon(Icons.add_rounded, size: 18),
    label: Text('course_list_new'.tr, style: appText(14, w: FontWeight.w600, c: context.colors.onHero)),
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
  const _CourseList({required this.p, required this.search});

  final TeacherCoursesProvider p;
  final TextEditingController search;

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

  @override
  Widget build(BuildContext context) {
    final p = widget.p;

    // A filter runs on the loaded courses: it must see every page (it keeps loading, the skeleton meanwhile).
    final needEverything = p.activeFilter != TeacherCourseStatus.all;
    if (p.isLoading && p.filteredCourses.isEmpty) {
      return const CourseListSkeleton();
    }

    final error = p.hasError
        ? CourseListError(message: p.errorMessage ?? 'failed_to_load'.tr, onRetry: p.refresh)
        : null;
    // A failed first page used to fall through to "no courses yet": say it failed and offer a retry.
    if (error != null && p.allCourses.isEmpty) {
      return _Centered(child: Column(children: [error, const Spacer()]));
    }

    final courses = p.filteredCourses;
    if (courses.isEmpty) {
      // Still looking through further pages for this filter.
      if (p.hasMore && !p.loadMoreFailed) {
        if (needEverything && !p.loadingMore) WidgetsBinding.instance.addPostFrameCallback((_) => p.loadMore());
        return const CourseListSkeleton();
      }
      return _empty(context, p);
    }

    final footer = PagedListFooter(
      loadingMore: p.loadingMore,
      hasMore: p.hasMore,
    );

    return AppInfiniteScroll(
      controller: _scroll,
      hasMore: p.hasMore,
      loading: p.isLoading || p.loadingMore,
      failed: p.loadMoreFailed,
      onLoadMore: p.loadMore,
      onRetry: () => p.loadMore(retry: true),
      threshold: needEverything ? double.infinity : 600,
      child: AppRefresh(
        // Pull-to-refresh means "get me the latest": reload the first page.
        onRefresh: p.refresh,
        child: _Centered(
          child: LayoutBuilder(
            builder: (context, box) => CustomScrollView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                if (error != null) SliverToBoxAdapter(child: error),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: CourseCardSliver(
                    width: math.max(0.0, box.maxWidth - 32),
                    count: courses.length,
                    itemBuilder: (_, i, shape) => _TeacherCourseCard(
                      key: ValueKey(courses[i].id),
                      course: courses[i],
                      shape: shape,
                    ),
                  ),
                ),
                // room for the floating "Add course" button
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 96),
                  sliver: SliverToBoxAdapter(child: footer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      actionLabel: courseFeatureOff('teacher_courses.add') ? null : 'add_new_course'.tr,
      onAction: () => _openNewCourse(context),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Course card — the shared CourseListCard with the teacher's status, figures and ⋮ menu
// ═══════════════════════════════════════════════════════════════════════════════

enum _CourseAction { edit, publish, schedule, delete }

class _TeacherCourseCard extends StatelessWidget {
  const _TeacherCourseCard({super.key, required this.course, required this.shape});

  final TeacherCourse course;
  final CourseCardShape shape;

  Future<void> _confirmDelete(BuildContext context) async {
    final c = course;
    final title = (AppConfig.lang == 'ar' ? c.titleAr : c.titleEn) ?? '';
    final ok = await appConfirm(
      context,
      message: '${'delete_course_confirm'.tr} "$title"${AppConfig.lang == 'ar' ? '؟' : '?'}',
      danger: true,
      confirmLabel: 'delete'.tr,
    );
    if (!ok || !context.mounted) return;
    final deleted = await context.read<TeacherCoursesProvider>().deleteCourse(c.id);
    if (deleted) showAppNotice('course_deleted'.tr);
  }

  Future<void> _togglePublish(BuildContext context) async {
    final p = context.read<TeacherCoursesProvider>();
    await (course.isPublished ? p.unpublishCourse(course.id) : p.publishCourse(course.id));
  }

  void _act(BuildContext context, _CourseAction a) {
    switch (a) {
      case _CourseAction.edit:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourseFormScreen(course: course)));
      case _CourseAction.publish:
        _togglePublish(context);
      case _CourseAction.schedule:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeacherSchedulesScreen(course: course)));
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
          course.isPublished ? Icons.visibility_off_outlined : Icons.public_rounded,
          course.isPublished ? 'unpublish_course'.tr : 'publish_course'.tr,
        ),
      if (!courseFeatureOff('teacher_courses.card_details'))
        (_CourseAction.schedule, Icons.calendar_month_outlined, 'weekly_schedule'.tr),
      if (!courseFeatureOff('teacher_courses.delete')) (_CourseAction.delete, Icons.delete_outline_rounded, 'delete'.tr),
    ];
    if (actions.isEmpty) return null;
    return SizedBox(
      width: 40,
      height: 40,
      child: PopupMenuButton<_CourseAction>(
        tooltip: 'course_list_more'.tr,
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.divider)),
        onSelected: (a) => _act(context, a),
        itemBuilder: (_) => [
          for (final (action, icon, label) in actions)
            PopupMenuItem(
              value: action,
              child: Row(children: [
                Icon(icon, size: 18, color: action == _CourseAction.delete ? c.danger : c.textMedium),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: appText(14, w: FontWeight.w400, c: action == _CourseAction.delete ? c.danger : c.textDark),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  void _open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => TeacherCourseScreenProvider(initialCourse: course),
        child: TeacherSessionsScreen(),
      ),
    ),
  );

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
      chip: CourseCoverChip.status(context, published: c.isPublished),
      corner: _menu(context),
      meta: [
        c.type == 'live' ? 'course_list_live'.tr : 'course_list_recorded'.tr,
        ?where,
        coursePriceLabel(c.currency, c.effectivePrice),
      ],
      isPrivate: c.isPrivate,
      footer: ParentComponent(
        featureKey: 'teacher_courses.card_stats',
        child: CourseStatsFooter(
          students: c.studentsCount,
          sessions: c.sessionsCount,
          rating: c.rateSummary?.average,
        ),
      ),
      onTap: () => _open(context),
    );
  }
}
