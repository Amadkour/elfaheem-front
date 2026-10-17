import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/features/student/home/home_provider.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart' as Helpers;
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/paged_progress.dart';
import '../../../../utils/widget/search_text_field.dart';
import '../../../shared/course/home_course_list.dart';
import '../../models.dart';
import '../details/components/app_responsive.dart';
import '../details/course_detail_screen.dart';
import 'my_courses_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

class MyCoursesScreen extends StatefulWidget {
  const MyCoursesScreen({super.key, required this.courses});
  final List<CourseModel> courses;
  @override
  State<MyCoursesScreen> createState() => _MyCoursesScreenState();
}

class _MyCoursesScreenState extends State<MyCoursesScreen> {
  final _search = TextEditingController();
  late final HomeProvider _home;
  List<CourseModel>? _synced;

  /// [widget.courses] is only a snapshot taken when the dashboard was built (usually still empty, and
  /// stale after any later refresh / enrolment). Follow the HomeProvider's CURRENT list instead and
  /// re-seed the provider whenever the home dashboard loads a new one.
  void _syncFromHome() {
    if (!mounted) return;
    final list = _home.myCourses;
    if (identical(list, _synced)) return; // same list as last time → nothing new
    _synced = list;
    context.read<MyCoursesProvider>().init(list);
  }

  @override
  void dispose() {
    _home.removeListener(_syncFromHome);
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
    return BasePage(
      key: const ValueKey('my_courses'),
      appBar: ScreenAppBar(title: 'courses'.tr, showBack: !kIsWeb),
      useWebCard: true,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints:
                  const BoxConstraints(maxWidth: Breakpoints.contentMax),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      const ParentComponent(
                          featureKey: 'my_courses.stats', child: _StatsRow()),
                      const SizedBox(height: 14),
                      Expanded(child: _CourseList(controller: _search)),
                    ],
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

// ── Stat cards ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MyCoursesProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _StatCard(
            label: 'registered_courses'.tr,
            count: p.allCount,
            icon: Icons.library_books_rounded,
            gradient: context.colors.accentGradient,
            shadowColor: context.colors.primary,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'ongoing_courses'.tr,
            count: p.inProgressCount,
            icon: Icons.trending_up_rounded,
            gradient: context.colors.accentGradient,
            shadowColor: context.colors.accent,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'completed_courses'.tr,
            count: p.completedCount,
            icon: Icons.workspace_premium_rounded,
            gradient: context.colors.goldCharcoalGradient,
            shadowColor: context.colors.accent2,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final LinearGradient gradient;
  final Color shadowColor;

  const _StatCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.gradient,
    required this.shadowColor,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.32),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                fontFamily: 'bahji',
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontFamily: 'bahji',
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Filter tabs ───────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.p});
  final MyCoursesProvider p;
  static final List<(CourseStatus, String, IconData)> _tabs = [
    (CourseStatus.all, 'filter_all'.tr, Icons.apps_rounded),
    (CourseStatus.inProgress, 'ongoing'.tr, Icons.play_arrow_rounded),
    (
    CourseStatus.completed,
    'completed_courses'.tr,
    Icons.check_circle_rounded
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: _tabs.map((t) {
          final (status, label, icon) = t;
          final active = p.activeFilter == status;

          return Expanded(
            child: GestureDetector(
              onTap: () => context.read<MyCoursesProvider>().setFilter(status),
              child: AnimatedContainer(
                height: 30,
                margin: const EdgeInsets.all(8),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: active
                              ? context.colors.primary
                              : context.colors.textLight,
                          width: 2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: active
                          ? context.colors.primary
                          : context.colors.textLight,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: context.colors.label.copyWith(
                        color: active
                            ? context.colors.primary
                            : context.colors.textLight,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Course list ───────────────────────────────────────────────────────────────

class _CourseList extends StatelessWidget {
  const _CourseList({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Consumer<MyCoursesProvider>(builder: (context, provider, child) {
      if (provider.isLoading && provider.allCourses.isEmpty) {
        return Center(child: AppLoadingIndicator());
      }

      final courses = provider.filteredCourses;
      // Only show "empty" once the server has nothing more: with client-side search / filter an
      // empty result on page 1 must still be allowed to load page 2.
      final showEmpty = courses.isEmpty && !provider.hasMore;

      return Column(children: [
        ParentComponent(
          featureKey: 'my_courses.search',
          child: MySearchBar(
            controller: controller,
            hint: 'search_course_by_name_description',
            onChanged: provider.setQuery,
          ),
        ),
        ParentComponent(
            featureKey: 'my_courses.filters', child: _FilterTabs(p: provider)),
        const SizedBox(height: 10),
        if (provider.allCount > 0 && (provider.total > 0 || !provider.hasMore) && (provider.total > provider.allCount
            ? provider.total
            : provider.allCount)>20)
          PagedCountCard(
            loaded: provider.allCount,
            total: provider.total > provider.allCount
                ? provider.total
                : provider.allCount,
            loadingMore: provider.isLoadingMore,
            done: !provider.hasMore,
            icon: Icons.library_books_rounded,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          ),
        Expanded(
          child: showEmpty
              ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color:
                    context.colors.primaryLight.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.menu_book_rounded,
                      size: 38, color: context.colors.primary),
                ),
                const SizedBox(height: 14),
                Text('no_courses_in_section'.tr,
                    style: context.colors.body),
              ],
            ),
          )
              : ParentComponent(
            featureKey: 'my_courses.list',
            child: HomeCourseList(
              hasMore: provider.hasMore,
              courses: courses,
              loadingMore: provider.isLoadingMore,
              onLoadMore: provider.loadMore,
              onRefresh: provider.refresh,
              onTap: (CourseModel c) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CourseDetailScreen(course: c)));
              },
              isTeacher: false,
              pageName: 'My-courses-profile-filtered',
            ),
          ),
        ),
      ]);
    });
  }
}