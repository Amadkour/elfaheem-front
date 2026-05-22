/// courses_list_screen.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
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
import 'courses_provider.dart';

class CoursesListScreen extends StatefulWidget {
  const CoursesListScreen({super.key, this.openSearch = false});

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
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focusNode.requestFocus());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch(String q) => context.read<CoursesProvider>().fetchCourses(
        search: q.trim().isEmpty ? null : q.trim(),
      );

  void _clearSearch() {
    _searchCtrl.clear();
    context.read<CoursesProvider>().fetchCourses();
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      child: SafeArea(
        child: Column(
          children: [
            // Only show app-bar on mobile (web uses sidebar topbar)
              ScreenAppBar(title: 'explorer_courses'.tr),

            ContentBox(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              child: _SearchBar(
                controller: _searchCtrl,
                focusNode: _focusNode,
                onChanged: _onSearch,
                onClear: _clearSearch,
              ),
            ),
            const SizedBox(height: 14),
            const Expanded(child: _CourseList()),
          ],
        ),
      ),
    );
  }
}
// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Container(
        height: 52,
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textDirection: TextDirection.rtl,
          onChanged: onChanged,
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 14,
              color: context.colors.textDark),
          decoration: InputDecoration(
            hintText: 'بحث عن كورس...',
            hintStyle: context.colors.caption.copyWith(fontSize: 14),
            hintTextDirection: TextDirection.rtl,
            prefixIcon: Container(
              margin: const EdgeInsets.all(10),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.colors.primaryLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.search_rounded,
                  color: context.colors.primary, size: 18),
            ),
            suffixIcon: ListenableBuilder(
              listenable: controller,
              builder: (_, __) => controller.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: context.colors.textLight, size: 18),
                      onPressed: onClear)
                  : const SizedBox.shrink(),
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      );
}

// ── Course list ───────────────────────────────────────────────────────────────

class _CourseList extends StatelessWidget {
  const _CourseList();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CoursesProvider>();


    if (provider.isLoading && provider.courses.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(context.colors.primary),
          strokeWidth: 2.5,
        ),
      );
    }

    if (!provider.isLoading && provider.courses.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off_rounded,
        message: 'لا توجد كورسات',
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
          provider.loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        color: context.colors.primary,
        onRefresh: provider.fetchCourses,
        child: HomeCourseList(hasMore: provider.hasMore, courses: provider.courses, onTap: (CourseModel course){Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CourseDetailScreen(course: course)),
        );}, isTeacher: context.read<AuthProvider>().isTeacher)
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
            Text(message,
                style:
                    context.colors.body.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
