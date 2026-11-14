import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/features/home/student/home_provider.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
import 'package:flutter_education_app/features/courses/course_list_card.dart';
import 'package:flutter_education_app/features/courses/home_course_list.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/courses/student/details/course_detail_screen.dart';
import 'package:flutter_education_app/features/courses/student/list/courses_list_screen.dart';
import 'package:flutter_education_app/features/courses/student/my_courses/my_courses_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/org_member_pages.dart' show OrgCoursesScreen;
import 'package:flutter_education_app/features/courses/course_scope.dart';
import 'package:flutter_education_app/features/courses/course_scope_bar.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppSpace, AppWidth;
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_view.dart' show EntityPanelAction;
import 'package:flutter_education_app/design/master_detail/entity_list_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/entity_viewer_actions.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/features/home/student/record/student_record_pages.dart';

/// The student's "My courses": which side (scope chips, only when the courses live on several), then ONE calm
/// toolbar (search · All / In progress / Completed with their counts · Left), then the shared course cards
/// (course_list_card.dart: rows on a phone, a grid of tiles wider). A card opens the course's panel, the student's
/// own story in it (progress, what is due, lessons, grades, history; if they left, the date and reason), and
/// Continue learning its page.
class MyCoursesScreen extends StatefulWidget {
  const MyCoursesScreen({super.key, required this.courses});
  final List<CourseModel> courses;
  @override
  State<MyCoursesScreen> createState() => _MyCoursesScreenState();
}

class _MyCoursesScreenState extends State<MyCoursesScreen> {
  final _search = TextEditingController();
  final _panel = EntityPanelController(rowKind: EntityKind.course);
  late final HomeProvider _home;
  List<CourseModel>? _synced;

  void _openPage(BuildContext context, CourseModel c) => Navigator.push(
      context,
      MaterialPageRoute(
          settings: RouteSettings(name: '/course-detail', arguments: c), builder: (_) => CourseDetailScreen(course: c)));

  List<EntityPanelAction> _actions(BuildContext context, EntityRef ref, EntitySummary? s) {
    final course = context.read<MyCoursesProvider>().allCourses.where((c) => '${c.id}' == '${ref.id}').firstOrNull;
    return entityViewerActions(context, ref, s,
        controller: _panel,
        openCourse: s?.kind == EntityKind.course && course != null ? () => _openPage(context, course) : null);
  }

  /// [widget.courses] is only a snapshot taken when the dashboard was built (usually still empty, and
  /// stale after any later refresh / enrolment). Follow the HomeProvider's CURRENT list instead and
  /// re-seed the provider whenever the home dashboard loads a new one.
  void _syncFromHome() {
    if (!mounted) return;
    final list = _home.myCourses;
    if (identical(list, _synced)) return; // same list as last time → nothing new
    // still empty (the home answered with no courses): page 1 was already requested for the first empty list
    if (list.isEmpty && _synced != null && _synced!.isEmpty) return;
    _synced = list;
    context.read<MyCoursesProvider>().init(list);
  }

  @override
  void dispose() {
    _home.removeListener(_syncFromHome);
    _panel.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _home = context.read<HomeProvider>();
    _home.addListener(_syncFromHome);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromHome());
  }

  @override
  Widget build(BuildContext context) {
    // a desktop window: the wide page, the grid takes as many columns as fit and the panel opens beside it
    return BasePage(
      key: const ValueKey('my_courses'),
      appBar: ScreenAppBar(title: 'courses'.tr, showBack: !kIsWeb),
      useWebCard: true,
      width: AppWidth.wide,
      child: SafeArea(
        child: MasterDetailScaffold(
          controller: _panel,
          rootLabel: 'courses'.tr,
          deepLinks: true,
          actions: (ref, s) => _actions(context, ref, s),
          list: MyCoursesBody(controller: _search, panel: _panel),
        ),
      ),
    );
  }
}

/// The page under the app bar (also what the visual renders pump with a seeded provider).
class MyCoursesBody extends StatelessWidget {
  const MyCoursesBody({super.key, required this.controller, this.panel});

  final TextEditingController controller;

  /// The screen's panel (a card opens it, Previous / Next walk the cards).
  final EntityPanelController? panel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ScopeBar(),
        _Toolbar(controller: controller),
        Expanded(child: _CourseList(controller: controller, panel: panel)),
      ],
    );
  }
}

// ── Scope chips ───────────────────────────────────────────────────────────────

/// All · Personal · each organization, with counts — drawn only when the student's courses live on more than one
/// side (or Organization mode is open). A chip changes this list only, never the app mode; the list opens on the
/// mode's side (MyCoursesProvider.scope).
class _ScopeBar extends StatelessWidget {
  const _ScopeBar();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MyCoursesProvider>();
    return ListenableBuilder(
      listenable: AppModeController.instance,
      builder: (context, _) {
        final mode = p.modeScope;
        final modeOrg = mode.isOrg ? courseOrgFor(mode.orgId!, p.scopes, AppModeController.instance.current) : null;
        final chips = courseScopeChips(p.scopes, selected: p.scope, modeOrg: modeOrg);
        if (chips.length < 2) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xxs),
          child: CourseScopeChipBar(chips: chips, selected: p.scope, onSelect: p.selectScope),
        );
      },
    );
  }
}

// ── Toolbar: search + filter (the filter carries the counts the old stat cards showed) ──────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MyCoursesProvider>();
    final counts = !courseFeatureOff('my_courses.stats');
    final hasSearch = !courseFeatureOff('my_courses.search');
    final hasFilter = !courseFeatureOff('my_courses.filters');
    if (!hasSearch && !hasFilter) return const SizedBox(height: AppSpace.xs);
    return CourseListToolbar(
      search: hasSearch
          ? CourseSearchField(controller: controller, hint: 'search_course_by_name_description', onChanged: p.setQuery)
          : null,
      filter: hasFilter
          ? CourseSegments<CourseStatus>(
              selected: p.activeFilter,
              onSelect: p.setFilter,
              segments: [
                CourseSegment(CourseStatus.all, 'filter_all'.tr, count: counts ? p.allCount : null),
                CourseSegment(
                  CourseStatus.inProgress,
                  'course_list_in_progress'.tr,
                  count: counts ? p.inProgressCount : null,
                ),
                CourseSegment(CourseStatus.completed, 'completed_courses'.tr, count: counts ? p.completedCount : null),
                CourseSegment(CourseStatus.withdrawn, 'md_p7_left'.tr),
              ],
            )
          : null,
    );
  }
}

// ── Course list ───────────────────────────────────────────────────────────────

class _CourseList extends StatelessWidget {
  const _CourseList({required this.controller, this.panel});

  final TextEditingController controller;
  final EntityPanelController? panel;

  EntityRef _refOf(CourseModel c) => EntityRef(EntityKind.course, int.tryParse('${c.id}') ?? 0, label: c.titleAr, labelEn: c.titleEn, imageUrl: c.imageUrl);

  @override
  Widget build(BuildContext context) {
    return Consumer<MyCoursesProvider>(builder: (context, provider, child) {
      final me = context.select<MyAuthProvider, int?>((a) => a.currentUser?.id);
      if (provider.activeFilter == CourseStatus.withdrawn && me != null && panel != null) {
        return EntityListBody<EnrollmentRow>(config: studentLeftCoursesList(me), panel: panel!);
      }
      if (provider.isLoading && provider.allCourses.isEmpty) {
        return const CourseListSkeleton();
      }
      final error = provider.hasError
          ? CourseListError(message: provider.errorMessage ?? 'failed_to_load'.tr, onRetry: provider.refresh)
          : null;
      if (error != null && provider.allCourses.isEmpty) {
        return Column(children: [error, const Spacer()]);
      }

      final courses = provider.filteredCourses;
      panel?.siblings = [for (final c in courses) _refOf(c)];
      // the list mixes the personal account and organizations → every card says where it lives
      final mixed = courses.map((c) => c.org?.id).toSet().length > 1;
      final scope = provider.scope;
      // Only show "empty" once the server has nothing more: with client-side search / filter an
      // empty result on page 1 must still be allowed to load page 2.
      final showEmpty = courses.isEmpty && !provider.hasMore;
      final total = provider.total > provider.allCount ? provider.total : provider.allCount;

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?error,
        if (provider.allCount > 0 && (provider.total > 0 || !provider.hasMore) && total > 20)
          PagedCountCard(
            loaded: provider.allCount,
            total: total,
            loadingMore: provider.isLoadingMore,
            done: !provider.hasMore,
            icon: Icons.library_books_rounded,
            margin: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
          ),
        Expanded(
          child: showEmpty
              ? _empty(context, provider, scope)
              : ParentComponent(
                  featureKey: 'my_courses.list',
                  child: HomeCourseList(
                    hasMore: provider.hasMore,
                    courses: courses,
                    loadingMore: provider.isLoadingMore,
                    loadFailed: provider.pageFailed,
                    onLoadMore: provider.loadMore,
                    onRetry: () => provider.loadMore(retry: true),
                    onRefresh: provider.refresh,
                    onTap: (CourseModel c) => EntityNavigator.open(context, _refOf(c)),
                    isTeacher: false,
                    pageName: 'My-courses-profile-filtered',
                    maxWidth: AppWidth.wide.max,
                    badgeFor: mixed ? (c) => CourseOrgBadge(org: c.org) : null,
                  ),
                ),
        ),
      ]);
    });
  }

  Widget _empty(BuildContext context, MyCoursesProvider provider, CourseScope scope) {
    // a search or a filter found nothing → offer to clear them
    if (controller.text.trim().isNotEmpty || provider.activeFilter != CourseStatus.all) {
      return CourseListEmpty(
        icon: Icons.search_off_rounded,
        message: 'course_list_not_found'.tr,
        actionLabel: 'course_list_clear_search'.tr,
        onAction: () {
          controller.clear();
          provider.setQuery('');
          provider.setFilter(CourseStatus.all);
        },
      );
    }
    if (scope.isOrg) {
      return CourseListEmpty(
        icon: Icons.apartment_rounded,
        message: 'course_scope_org_empty_student'.tr,
        actionLabel: 'course_scope_browse_org'.tr,
        onAction: () => _browseOrg(context, scope.orgId!),
      );
    }
    return CourseListEmpty(
      icon: Icons.menu_book_rounded,
      message: 'course_list_empty'.tr,
      actionLabel: 'course_list_browse'.tr,
      onAction: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CoursesListScreen(homeCourses: context.read<HomeProvider>().otherCourses, forMyCourses: false),
      )),
    );
  }
}

/// The organization's own catalogue (its courses the student has not joined yet).
void _browseOrg(BuildContext context, int orgId) {
  final entry = AppModeController.instance.current?['organization'];
  final org = entry is Map && entry['id'] == orgId ? Map<String, dynamic>.from(entry) : <String, dynamic>{'id': orgId};
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgCoursesScreen(org: org)));
}
