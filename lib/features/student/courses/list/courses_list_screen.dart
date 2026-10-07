/// courses_list_screen.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/student/courses/my_courses/my_courses_provider.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart' as Helpers;
import '../../../../config/theme/app_theme.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/search_text_field.dart';
import '../../models.dart';
import '../details/course_detail_screen.dart';

class CoursesListScreen extends StatefulWidget {
  const CoursesListScreen({
    super.key,
    this.openSearch = false,
    required this.homeCourses,
    required this.forMyCourses,
  });

  final List<CourseModel> homeCourses;
  final bool forMyCourses;
  final bool openSearch;

  @override
  State<CoursesListScreen> createState() => _CoursesListScreenState();
}

class _CoursesListScreenState extends State<CoursesListScreen> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.openSearch) {
      WidgetsBinding.instance.addPostFrameCallback(
            (_) => _focusNode.requestFocus(),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MyCoursesProvider>().init(widget.homeCourses);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    MyCoursesProvider provider = context.watch<MyCoursesProvider>();
    return BasePage(
      key: const ValueKey('courses_list'),
      useWebCard: true,
      enableFooterWidget: false,
      appBar: ScreenAppBar(
        title: widget.forMyCourses ? 'my_courses'.tr : 'explorer_courses'.tr,
      ),
      child: SafeArea(
        child: Column(
          children: [
            ParentComponent(
              featureKey: 'courses_list.search',
              child: MySearchBar(
                controller: _searchCtrl,
                hint: 'search_course_by_name_description',
                onChanged: provider.setQuery,
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                    context.read<MyCoursesProvider>().loadMore();
                  }
                  return false;
                },
                child: Stack(
                  children: [
                    ParentComponent(
                        featureKey: 'courses_list.list',
                        child: HomeCourseList(
                          hasMore: provider.hasMore,
                          courses: provider.filteredCourses,
                          onTap: (CourseModel c) {
                            Navigator.pushNamed(context, '/course-detail', arguments: c);
                          },
                          isTeacher: false,
                          pageName: widget.forMyCourses
                              ? 'my-courses-profile'
                              : 'other-courses-profile',
                        )),
                    if (provider.isLoadingMore)
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Center(child: _LoadMorePill()),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: context.colors.primaryLight.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 38, color: context.colors.primary),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: context.colors.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small floating pill shown while the next page of a list is loading.
// Overlaid at the bottom of the scrollable rather than appended after it, so
// it works regardless of the internal layout of whatever list widget it sits
// on top of (HomeCourseList here).
// ─────────────────────────────────────────────────────────────────────────────

class _LoadMorePill extends StatelessWidget {
  const _LoadMorePill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(context.colors.primary),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'loading_more'.tr,
          style: TextStyle(
            fontFamily: 'tajawal',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.colors.textMedium,
          ),
        ),
      ],
    ),
  );
}