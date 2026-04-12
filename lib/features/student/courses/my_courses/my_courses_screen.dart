import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart' as Helpers;
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/app_network_image.dart';
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
  void initState() {
    super.initState();
    // Fetch enrolled courses once on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MyCoursesProvider>().fetchMyEnrollments();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenAppBar(title: 'courses'.tr),
              const SizedBox(height: 8),
              const _FilterTabs(),
              const SizedBox(height: 16),
              const Expanded(child: _CourseList()),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Filter Tabs ───────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  const _FilterTabs();

  static const _tabs = [
    (CourseStatus.all, 'الكل'),
    (CourseStatus.inProgress, 'مستمر'),
    (CourseStatus.completed, 'مكتمله'),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MyCoursesProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: _tabs.map((t) {
          final (status, label) = t;
          final isActive = provider.activeFilter == status;

          return Expanded(
            child: GestureDetector(
              onTap: () => context.read<MyCoursesProvider>().setFilter(status),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? AppTheme.primary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTheme.label.copyWith(
                    color: isActive ? AppTheme.primary : AppTheme.textMedium,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Course List ───────────────────────────────────────────────────────────────

class _CourseList extends StatelessWidget {
  const _CourseList();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MyCoursesProvider>();

    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(AppTheme.primary),
        ),
      );
    }

    final courses = provider.filteredCourses;

    if (courses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_rounded, size: 64, color: AppTheme.textLight),
            SizedBox(height: 12),
            Text('لا توجد كورسات في هذا القسم', style: AppTheme.body),
          ],
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: ListView.separated(
        key: ValueKey(courses.length),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const BouncingScrollPhysics(),
        itemCount: courses.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) => _EnrolledCourseCard(course: courses[i]),
      ),
    );
  }
}

// ── Enrolled Course Card ──────────────────────────────────────────────────────

class _EnrolledCourseCard extends StatelessWidget {
  final CourseModel course;

  const _EnrolledCourseCard({required this.course});

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseDetailScreen(
          course: course,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = course.progress >= 1.0;

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            // ── Thumbnail ────────────────────────────────────────────────────
            Stack(
              children: [
                AppNetworkImage(
                  url: course.imageUrl,
                  width: 88,
                  height: 88,
                  borderRadius: BorderRadius.circular(14),
                ),
                if (isCompleted)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'مكتمل',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'bahji',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            // ── Info ─────────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // course.title is an alias for course.name
                  Text(
                    course.title,
                    style: AppTheme.h3,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // course.instructorName is an alias for course.teacherName
                  Text(
                    '${course.instructorName} | ${course.categoryName ?? ''}',
                    style: AppTheme.caption,
                  ),
                  const SizedBox(height: 10),
                  CourseProgressBar(
                    progress: course.progress,
                    color: isCompleted ? AppTheme.success : AppTheme.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
