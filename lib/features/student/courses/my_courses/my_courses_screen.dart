import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart' as Helpers;
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../shared/profile/course_instractor_profile.dart';
import '../../models.dart';
import '../details/components/app_responsive.dart';
import '../details/course_detail_screen.dart';
import 'components/course_progress_bar.dart';
import 'my_courses_provider.dart';

class MyCoursesScreen extends StatefulWidget {
  const MyCoursesScreen({super.key});

  @override
  State<MyCoursesScreen> createState() => _MyCoursesScreenState();
}

class _MyCoursesScreenState extends State<MyCoursesScreen> {
  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      child:SafeArea(
          child: Column(
            children: [
              // Header — mobile uses AppBar, web uses inline title
              if (!context.showSidebar)
                ScreenAppBar(title: 'courses'.tr)
              else
                _WebHeader(),

              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: Breakpoints.contentMax),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        const _StatsRow(),
                        const SizedBox(height: 16),
                        const _FilterTabs(),
                        const SizedBox(height: 14),
                        const Expanded(child: _CourseList()),
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

class _WebHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha:0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Text('my_courses'.tr,
            style: context.colors.h2.copyWith(fontSize: 16)),
      ],
    ),
  );
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
            gradient: context.colors.tealGradient,
            shadowColor: context.colors.accent,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'completed_courses'.tr,
            count: p.completedCount,
            icon: Icons.workspace_premium_rounded,
            gradient: context.colors.purpleGradient,
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
            color: shadowColor.withValues(alpha:0.32),
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
                fontFamily: 'Cairo',
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
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Filter tabs ───────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  const _FilterTabs();

  static  final List<(CourseStatus, String, IconData)> _tabs = [
    (CourseStatus.all, 'filter_all'.tr, Icons.apps_rounded),
    (CourseStatus.inProgress, 'ongoing'.tr, Icons.play_arrow_rounded),
    (CourseStatus.completed, 'completed_courses'.tr, Icons.check_circle_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MyCoursesProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.05),
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
                onTap: () =>
                    context.read<MyCoursesProvider>().setFilter(status),
                child: AnimatedContainer(
                  height: 30,
                  margin: EdgeInsets.all(8),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: active
                            ?context.colors.primary:context.colors.textLight,
                        width: 2
                      )
                    ),

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
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
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
      ),
    );
  }
}

// ── Course list ───────────────────────────────────────────────────────────────

class _CourseList extends StatelessWidget {
  const _CourseList();

  @override
  Widget build(BuildContext context) {
    final p      = context.watch<MyCoursesProvider>();
    final isWide = context.showSidebar;

    if (p.isLoading && p.allCourses.isEmpty) {
      return  Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(context.colors.primary),
          strokeWidth: 2.5,
        ),
      );
    }

    final courses = p.filteredCourses;

    if (courses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.colors.primaryLight.withValues(alpha:0.3),
                shape: BoxShape.circle,
              ),
              child:  Icon(Icons.menu_book_rounded,
                  size: 38, color: context.colors.primary),
            ),
            const SizedBox(height: 14),
             Text(
                 'no_courses_in_section'.tr,
                style: context.colors.body),
          ],
        ),
      );
    }

    if (isWide) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 2.0,
        ),
        itemCount: courses.length,
        itemBuilder: (_, i) =>
            _EnrolledCard(course: courses[i]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      physics: const BouncingScrollPhysics(),
      itemCount: courses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _EnrolledCard(course: courses[i]),
    );
  }
}

// ── Enrolled course card ──────────────────────────────────────────────────────

class _EnrolledCard extends StatelessWidget {
  final CourseModel course;
  const _EnrolledCard({required this.course});

  void _open(BuildContext ctx) => Navigator.of(ctx).push(
    MaterialPageRoute(
        builder: (_) => CourseDetailScreen(course: course)),
  );

  @override
  Widget build(BuildContext context) {
    final isDone = course.progress >= 1.0;
    final accentColor = isDone ? context.colors.accent2 : context.colors.primary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _open(context),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: isDone
                ? Border.all(
                color: context.colors.accent2.withValues(alpha:0.3),
                width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha:isDone ? 0.1 : 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Thumbnail with badge
                Stack(
                  children: [
                    AppNetworkImage(
                      url: course.imageUrl,
                      width: 88,
                      height: 88,
                      borderRadius: BorderRadius.circular(14),
                      heroTag: "my_courses-list-${course.id}",

                    ),
                    if (isDone)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: context.colors.accent2,
                            borderRadius: BorderRadius.circular(7),
                            boxShadow: [
                              BoxShadow(
                                color:
                                context.colors.accent2.withValues(alpha:0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child:  Text(
                            'completed_badge'.tr,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ),
                    // Progress arc indicator
                    if (!isDone && course.progress > 0)
                      Positioned(
                        bottom: 5,
                        right: 5,
                        child: _ProgressDot(
                            progress: course.progress),
                      ),
                  ],
                ),
                const SizedBox(width: 14),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.title,
                        style: context.colors.h3.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if(course.teacher!=Null)
                        InstructorAvatar(teacher: course.teacher!, size: 50, canOpen: true,),
                      const SizedBox(height: 10),
                      CourseProgressBar(
                        progress: course.progress,
                        color: accentColor,
                      ),
                    ],
                  ),
                ),

                Icon(Icons.chevron_left_rounded,
                    color: context.colors.textLight, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small circular progress dot on thumbnail
class _ProgressDot extends StatelessWidget {
  final double progress;
  const _ProgressDot({required this.progress});

  @override
  Widget build(BuildContext context) =>
      Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha:0.1),
          blurRadius: 4,
        ),
      ],
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(
          value: progress,
          strokeWidth: 2.5,
          backgroundColor: context.colors.primaryLight,
          valueColor:
           AlwaysStoppedAnimation(context.colors.primary),
        ),
        Text(
          '${(progress * 100).round()}',
          style:  TextStyle(
            fontSize: 6,
            fontWeight: FontWeight.w800,
            color: context.colors.primary,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    ),
  );
}