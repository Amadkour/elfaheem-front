library;

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
import '../../../config/app_config.dart' as Helpers;
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/app_bar.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../home/teacher_home_provider.dart';
import '../schedules/schedules_screen.dart';
import '../sessions/sessions_provider.dart';
import '../sessions/sessions_screen.dart';
import 'course_form_screen.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/core/display/app_fonts.dart';

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

    return BasePage(
      key: const ValueKey('teacher_courses'),
      useWebCard: true,
      appBar: ScreenAppBar(title: 'my_courses'.tr, showBack: !kIsWeb),
      floatingActionButton: context.showSidebar
          ? null
          : ParentComponent(
              featureKey: 'teacher_courses.add',
              child: _FloatingAddBtn(),
            ),
      child: SafeArea(
        bottom: false,
        child: p.isLoading && p.allCourses.isEmpty
            ? const AppListSkeleton(withAvatar: false)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search + filters + progress share one centred, width-capped
                  // block so they line up with the list on wide screens.
                  _Centered(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 4),
                        ParentComponent(
                          featureKey: 'teacher_courses.filters',
                          child: _FilterTabs(p: p),
                        ),
                        const SizedBox(height: 10),
                        ParentComponent(
                          featureKey: 'teacher_courses.search',
                          child: _CourseSearchBar(
                            controller: _searchCtrl,
                            p: p,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Pinned above the list: "Showing 24 of 134" + progress bar.
                        if (p.totalCount > 12)
                          ParentComponent(
                            featureKey: 'teacher_courses.pagination',
                            child: _CoursesProgress(p: p),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: _CourseList(p: p)),
                ],
              ),
      ),
    );
  }
}

/// Centres [child] and caps it at the app's content width.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
      child: child,
    ),
  );
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
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    );
  }
}

class _FloatingAddBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FloatingActionButton(
    heroTag: "add_course_float",
    key: ValueKey("add_course_float"),
    onPressed: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CourseFormScreen())),
    backgroundColor: Colors.transparent,
    elevation: 0,
    child: Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: context.colors.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: context.colors.primaryShadow,
      ),
      child: Icon(Icons.add_rounded, color: context.colors.onHero, size: 26),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Search bar — server-side search by course name/description, debounced in
//  TeacherCoursesProvider.setQuery so it re-fetches the first page shortly
//  after the teacher stops typing. Glows with the primary colour on focus.
// ═══════════════════════════════════════════════════════════════════════════════

class _CourseSearchBar extends StatefulWidget {
  const _CourseSearchBar({required this.controller, required this.p});

  final TextEditingController controller;
  final TeacherCoursesProvider p;

  @override
  State<_CourseSearchBar> createState() => _CourseSearchBarState();
}

class _CourseSearchBarState extends State<_CourseSearchBar> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Local listeners (independent of provider rebuilds) so the clear "×"
    // button and the focus glow react immediately as the teacher types.
    widget.controller.addListener(_refresh);
    _focus.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = widget.controller;
    final p = widget.p;
    final focused = _focus.hasFocus;
    bool isAr=AppConfig.lang == 'ar';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 52,
        padding: const EdgeInsetsDirectional.only(start: 8, end: 10),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: focused ? c.primary : c.primary.withValues(alpha: 0.10),
            width: focused ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: c.primary.withValues(alpha: focused ? 0.20 : 0.06),
              blurRadius: focused ? 18 : 10,
              offset: Offset(0, focused ? 6 : 3),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: focused ? c.primaryGradient : null,
                color: focused ? null : c.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.search_rounded,
                size: 20,
                color: focused ? c.onHero : c.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child:
            TextField(
              controller: controller,
              focusNode: _focus,
              onChanged: (v) => p.setQuery(v),
              textInputAction: TextInputAction.search,
              textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
              textAlign: isAr ? TextAlign.right : TextAlign.left,
              style: c.label.copyWith(color: c.textDark),
              decoration: InputDecoration(
                isDense: false,
                filled: false,
                fillColor: Colors.transparent,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: 'search_course_by_name_description'.tr,
                hintStyle: c.label.copyWith(color: c.textLight),
                hintTextDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
              ),
            ),
            ),
            if (controller.text.isNotEmpty)
              Semantics(
                button: true,
                label: 'clear'.tr,
                child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  controller.clear();
                  p.setQuery('');
                },
                child: Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: c.textLight.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: c.textMedium,
                  ),
                ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Filter tabs — segmented control with a gradient pill that slides to the
//  selected segment (RTL-safe: AlignmentDirectional follows the text direction).
// ═══════════════════════════════════════════════════════════════════════════════

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.p});

  final TeacherCoursesProvider p;
  static const _tabs = [
    (TeacherCourseStatus.all, 'filter_all', Icons.grid_view_rounded),
    (TeacherCourseStatus.published, 'filter_published', Icons.public_rounded),
    (TeacherCourseStatus.draft, 'filter_drafts', Icons.edit_note_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final index = _tabs.indexWhere((t) => t.$1 == p.activeFilter);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 50,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.primary.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: c.primary.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Sliding selection pill
            AnimatedAlign(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: AlignmentDirectional(index - 1.0, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / _tabs.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: c.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: c.primary.withValues(alpha: 0.30),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: _tabs.map((t) {
                final (status, labelKey, icon) = t;
                final active = p.activeFilter == status;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context
                        .read<TeacherCoursesProvider>()
                        .setFilter(status),
                    child: Center(
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(
                          end: active ? c.onHero : c.textMedium,
                        ),
                        duration: const Duration(milliseconds: 260),
                        builder: (_, col, _) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 15, color: col),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                labelKey.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: c.label.copyWith(
                                  color: col,
                                  fontWeight: active
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Course list — infinite scroll (same model as the admin lists)
//  • loads the next page when the scroll nears the end
//  • while a filter is active it keeps loading until every course is loaded,
//    because the filter runs on the loaded courses
//  • Web → _TwoColumnMasonry (self-sizing, no childAspectRatio)
//  • Mobile → plain ListView
//  • last row: PagedListFooter ("Loading more…" / "All loaded")
// ═══════════════════════════════════════════════════════════════════════════════

class _CourseList extends StatefulWidget {
  const _CourseList({required this.p});

  final TeacherCoursesProvider p;

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

  /// [userInitiated] = the user scrolled, so a previously failed load is retried.
  void _maybeLoadMore({bool userInitiated = false}) {
    final p = widget.p;
    if (!p.hasMore || p.isLoading || p.loadingMore) return;

    // Not scrollable yet (page too short to fill the screen) counts as
    // "near the end", so the list keeps filling itself until it scrolls.
    final nearEnd = !_scroll.hasClients || _scroll.position.extentAfter < 600;
    final needEverything = p.activeFilter != TeacherCourseStatus.all;
    if (nearEnd || needEverything) p.loadMore(retry: userInitiated);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final isWide = context.showSidebar;

    // Runs after every rebuild — each finished load notifies, which chains
    // the next page until the screen is filled (or everything is loaded).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMore();
    });

    if (p.isLoading && p.filteredCourses.isEmpty) {
      return const AppListSkeleton(withAvatar: false);
    }

    // A failed first page used to fall through to "no courses yet": say it failed and offer a retry.
    if (p.hasError && p.allCourses.isEmpty) {
      return ErrorRetry(message: p.errorMessage ?? 'failed_to_load'.tr, onRetry: p.refresh);
    }

    final courses = p.filteredCourses;
    if (courses.isEmpty) {
      // Still looking through further pages for this filter.
      if (p.hasMore && !p.loadMoreFailed) {
        return const AppListSkeleton(withAvatar: false);
      }
      return _EmptyState(
        searching:
            p.query.trim().isNotEmpty ||
            p.activeFilter != TeacherCourseStatus.all,
      );
    }

    final footer = PagedListFooter(
      loadingMore: p.loadingMore,
      hasMore: p.hasMore,
    );

    return AppRefresh(
      // Pull-to-refresh means "get me the latest": reload the first page.
      onRefresh: p.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0 &&
              (n is ScrollUpdateNotification || n is OverscrollNotification)) {
            _maybeLoadMore(userInitiated: true);
          }
          return false;
        },
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            child: isWide
                ? _TwoColumnMasonry(
                    courses: courses,
                    controller: _scroll,
                    footer: footer,
                  )
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    itemCount: courses.length + 1,
                    separatorBuilder: (_, i) =>
                        SizedBox(height: i < courses.length - 1 ? 14 : 0),
                    itemBuilder: (_, i) => i == courses.length
                        ? footer
                        : _CourseCard(
                            key: ValueKey(courses[i].id),
                            course: courses[i],
                          ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Two-column masonry: splits courses into left/right lists so each card
/// sizes itself naturally — no fixed childAspectRatio, no overflow.
class _TwoColumnMasonry extends StatelessWidget {
  final List<TeacherCourse> courses;
  final ScrollController controller;
  final Widget footer;

  const _TwoColumnMasonry({
    required this.courses,
    required this.controller,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final left = <TeacherCourse>[];
    final right = <TeacherCourse>[];
    for (var i = 0; i < courses.length; i++) {
      (i.isEven ? left : right).add(courses[i]);
    }

    Widget column(List<TeacherCourse> items) => Expanded(
      child: Column(
        children: items
            .map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _CourseCard(key: ValueKey(c.id), course: c),
              ),
            )
            .toList(),
      ),
    );

    return SingleChildScrollView(
      controller: controller,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [column(left), const SizedBox(width: 14), column(right)],
          ),
          footer,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Empty state
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.searching = false});

  /// A search or filter is active: "nothing matches" instead of the
  /// "add your first course" call to action.
  final bool searching;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  context.colors.primaryLight.withValues(alpha: 0.5),
                  context.colors.primaryLight.withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              searching ? Icons.search_off_rounded : Icons.school_outlined,
              size: 40,
              color: context.colors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            searching ? 'admin_no_courses_found'.tr : 'no_courses_section'.tr,
            style: context.colors.body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
          if (!searching) ...[
            const SizedBox(height: 6),
            Text(
              'add_first_course_hint'.tr,
              style: context.colors.caption.copyWith(
                color: context.colors.textLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CourseFormScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: context.colors.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: context.colors.primaryShadow,
                ),
                child: Text(
                  'add_new_course'.tr,
                  style: TextStyle(
                    color: context.colors.onHero,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppFonts.display,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Course card
// ═══════════════════════════════════════════════════════════════════════════════

class _CourseCard extends StatefulWidget {
  final TeacherCourse course;

  const _CourseCard({required this.course, super.key});

  @override
  State<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<_CourseCard> {
  bool _expanded = false;

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: Helpers.pageDirection,
        child: AlertDialog(
          backgroundColor: context.colors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'delete_course'.tr,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            '${'delete_course_confirm'.tr} "${(AppConfig.lang == 'ar' ? widget.course.titleAr : widget.course.titleEn) ?? ''}"؟',
            style: TextStyle(fontFamily: AppFonts.display),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'cancel'.tr,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: context.colors.textMedium,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: context.colors.danger,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'delete'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: context.colors.onHero,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      final deleted = await context.read<TeacherCoursesProvider>().deleteCourse(
        widget.course.id,
      );
      if (mounted && deleted) {
        showAppNotice('course_deleted'.tr);
      }
    }
  }

  Future<void> _togglePublish() async {
    final p = context.read<TeacherCoursesProvider>();
    await (widget.course.isPublished
        ? p.unpublishCourse(widget.course.id)
        : p.publishCourse(widget.course.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    final isDraft = !c.isPublished;
    final statusColor = isDraft ? context.colors.warning : context.colors.success;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.32),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: context.colors.heroShade.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Full-width 16:9 thumbnail with a bottom gradient scrim and
          //    floating status / type / rating chips ────────────────────
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 8.5,
                child: AppNetworkImage(
                  url: c.imageUrl,
                  width: double.infinity,
                  borderRadius: BorderRadius.zero,
                  heroTag: "courses-screen-${c.id}",
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.55, 1.0],
                      colors: [
                        Colors.transparent,
                        context.colors.heroShade.withValues(alpha: 0.45),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 10,
                end: 10,
                child: _GlassChip(
                  icon: c.type == 'live'
                      ? Icons.podcasts_rounded
                      : Icons.play_circle_fill_rounded,
                  label: c.type == 'live' ? 'live'.tr : 'recorded'.tr,
                  dark: true,
                ),
              ),
              PositionedDirectional(
                top: 10,
                start: 10,
                child: _GlassChip(
                  icon: isDraft
                      ? Icons.edit_note_rounded
                      : Icons.public_rounded,
                  label: isDraft ? 'status_draft'.tr : 'status_published'.tr,
                  color: statusColor,
                ),
              ),
              if (c.rateSummary != null)
                PositionedDirectional(
                  bottom: 10,
                  end: 10,
                  child: _GlassChip(
                    icon: Icons.star_rounded,
                    label: c.rateSummary!.average.toStringAsFixed(1),
                    color: context.colors.accent,
                    dark: true,
                  ),
                ),
            ],
          ),

          // ── Title + stats ────────────────────────────────────────────
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider(
                  create: (_) => TeacherCourseScreenProvider(initialCourse: c),
                  child: TeacherSessionsScreen(),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (AppConfig.lang == 'ar' ? c.titleAr : c.titleEn) ?? '',
                    style: context.colors.h3.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // 2×2 stats grid — deterministic height, no Wrap
                  ParentComponent(
                    featureKey: 'teacher_courses.card_stats',
                    child: _StatsGrid(course: c),
                  ),
                ],
              ),
            ),
          ),

          // ── Expand toggle ────────────────────────────────────────────
          ParentComponent(
            featureKey: 'teacher_courses.card_details',
            child: InkWell(
              onTap: () {
                if (mounted) setState(() => _expanded = !_expanded);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Text(
                      _expanded ? 'hide_details'.tr : 'show_details'.tr,
                      style: context.colors.label.copyWith(
                        color: context.colors.primary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: context.colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Expandable extras ────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            child: _expanded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Divider(height: 1, color: context.colors.divider),
                      _ExtrasPanel(course: c),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          Divider(height: 1, color: context.colors.divider),

          // ── Premium management toolbar ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: ParentComponent(
                    featureKey: 'teacher_courses.edit',
                    child: _ToolbarAction(
                      icon: Icons.edit_rounded,
                      label: 'edit'.tr,
                      color: context.colors.primary,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CourseFormScreen(course: c),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ParentComponent(
                    featureKey: 'teacher_courses.publish',
                    child: _ToolbarAction(
                      icon: isDraft
                          ? Icons.upload_rounded
                          : Icons.visibility_off_rounded,
                      label: isDraft
                          ? 'publish_course'.tr
                          : 'unpublish_course'.tr,
                      color: statusColor,
                      filled: true,
                      onTap: _togglePublish,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ParentComponent(
                  featureKey: 'teacher_courses.delete',
                  child: _ToolbarAction(
                    icon: Icons.delete_rounded,
                    color: context.colors.danger,
                    onTap: _confirmDelete,
                    iconOnly: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Stats — 2×2 fixed grid so height is always deterministic
// ═══════════════════════════════════════════════════════════════════════════════

class _StatsGrid extends StatelessWidget {
  final TeacherCourse course;

  const _StatsGrid({required this.course});

  @override
  Widget build(BuildContext context) {
    final c = course;
    final rows = [
      [
        (
          Icons.people_alt_rounded,
          '${c.studentsCount} ${'student'.tr}',
          context.colors.primary,
        ),
        (
          Icons.video_library_rounded,
          '${c.sessionsCount} ${'session'.tr}',
          context.colors.primary,
        ),
      ],
      [
        (
          Icons.access_time_rounded,
          '${c.totalHours.toStringAsFixed(0)}${'h'.tr}',
          context.colors.accent2,
        ),
        (
          Icons.star_rounded,
          c.rateSummary?.average.toStringAsFixed(1),
          context.colors.accent,
        ),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows.map((row) {
        final isLast = row == rows.last;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
          child: Row(
            children: row.map((item) {
              final (icon, label, color) = item;
              final isLastInRow = item == row.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(end: isLastInRow ? 0 : 4),
                  child: _StatCell(icon, label ?? '', color),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatCell(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: context.colors.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Glass chip — floats on top of the thumbnail (status / type / rating)
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool dark;

  const _GlassChip({
    required this.icon,
    required this.label,
    this.color,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? context.colors.heroShade.withValues(alpha: 0.45)
            : context.colors.onHero.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: dark ? 0.55 : 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: dark ? context.colors.onHero : c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: dark ? context.colors.onHero : c,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Toolbar action — one button in the card's bottom management bar
// ═══════════════════════════════════════════════════════════════════════════════

class _ToolbarAction extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;
  final bool iconOnly;

  const _ToolbarAction({
    required this.icon,
    this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? context.colors.onHero : color;
    final radius = BorderRadius.circular(14);

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: fg),
        if (!iconOnly && label != null) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ],
      ],
    );

    return Material(
      color: Colors.transparent,
      child: Ink(
        height: 44,
        width: iconOnly ? 44 : null,
        decoration: BoxDecoration(
          // Primary action gets a soft gradient + glow; the rest are tonal.
          gradient: filled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, context.colors.heroEnd(color, 0.18)],
                )
              : null,
          color: filled ? null : color.withValues(alpha: 0.10),
          borderRadius: radius,
          border: filled
              ? null
              : Border.all(color: color.withValues(alpha: 0.30)),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: iconOnly
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Extras panel
// ═══════════════════════════════════════════════════════════════════════════════

class _ExtrasPanel extends StatelessWidget {
  final TeacherCourse course;

  const _ExtrasPanel({required this.course});

  @override
  Widget build(BuildContext context) {
    final hasContent =
        course.schedules.isNotEmpty ||
        course.certificates.isNotEmpty ||
        course.tools.isNotEmpty ||
        course.prerequisites.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasContent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'no_extra_details'.tr,
                style: context.colors.caption.copyWith(
                  color: context.colors.textLight,
                ),
              ),
            ),
          if (course.schedules.isNotEmpty)
            _ExtRow(
              Icons.calendar_month_rounded,
              'weekly_schedule'.tr,
              course.schedules
                  .map((s) => '${s.dayLabel}  ${AppTime.clock(s.startTime)} – ${AppTime.clock(s.endTime)}')
                  .toList(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TeacherSchedulesScreen(course: course),
                ),
              ),
            ),
          if (course.certificates.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtRow(
              Icons.workspace_premium_rounded,
              'certificates'.tr,
              course.certificates.map((c) => c.title).toList(),
            ),
          ],
          if (course.tools.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtRow(
              Icons.build_rounded,
              'required_tools'.tr,
              course.tools.map((t) => t.name).toList(),
            ),
          ],
          if (course.prerequisites.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtRow(
              Icons.checklist_rounded,
              'prerequisites'.tr,
              course.prerequisites.map((p) => p.title).toList(),
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _ExtRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> items;
  final VoidCallback? onTap;

  const _ExtRow(this.icon, this.label, this.items, {this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 13, color: context.colors.primary),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: context.colors.label.copyWith(
                  color: context.colors.primary,
                  fontSize: 12,
                ),
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.edit_calendar_rounded,
                size: 16,
                color: context.colors.primary,
              ),
          ],
        ),
        const SizedBox(height: 5),
        ...items
            .take(3)
            .map(
              (item) => Padding(
                padding: const EdgeInsetsDirectional.only(start: 29, bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: context.colors.textLight,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(child: Text(item, style: context.colors.caption)),
                  ],
                ),
              ),
            ),
        if (items.length > 3)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 29, top: 2),
            child: Text(
              '+ ${items.length - 3} ${'others'.tr}',
              style: context.colors.caption.copyWith(
                color: context.colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    ),
  );
}
