// features/teacher/dashboard/analytics/analytics_hub_screen.dart
// Replaces the old analytics_hub_screen.dart — Tab 3 in TeacherDashboardScreen
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../config/app_theme.dart';
import '../../teacher/home/teacher_models.dart';
import '../../teacher/home/teacher_provider.dart';
import 'exam/teacher_exam_hub_screen.dart';
import 'teacher_attendance_screen.dart';

class TeacherAnalyticsHubScreen extends StatefulWidget {
  const TeacherAnalyticsHubScreen({super.key});

  @override
  State<TeacherAnalyticsHubScreen> createState() => _TeacherAnalyticsHubScreenState();
}

class _TeacherAnalyticsHubScreenState extends State<TeacherAnalyticsHubScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<TeacherProvider>().init();
    });
    super.initState();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final prov = context.read<TeacherProvider>();
    final filtered = _search.isEmpty
        ? prov.allCourses
        : prov.allCourses
            .where((c) => c.title.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyState(prov.allCourses.isEmpty)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      physics: const BouncingScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (_, i) =>
                          _CourseAnalyticsCard(course: filtered[i]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('الحضور والاختبارات', style: AppTheme.h1),
                const SizedBox(height: 2),
                const Text('اختر كورساً لإدارة الحضور أو الاختبارات',
                    style: AppTheme.body),
              ])),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.analytics_rounded,
                color: AppTheme.primary, size: 24),
          ),
        ]),
      );

  Widget _buildSearchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(
          controller: _searchCtrl,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText: 'ابحث عن كورس...',
            hintStyle: const TextStyle(
                fontFamily: 'Cairo', color: Colors.grey, fontSize: 13),
            prefixIcon:
                const Icon(Icons.search_rounded, color: Colors.grey, size: 20),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    })
                : null,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
      );

  Widget _buildEmptyState(bool noCoursesAtAll) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.school_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            noCoursesAtAll ? 'لا توجد كورسات بعد' : 'لا توجد نتائج للبحث',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                color: Colors.grey,
                fontWeight: FontWeight.w600),
          ),
          if (noCoursesAtAll) ...[
            const SizedBox(height: 8),
            const Text('أضف كورساً أولاً من تبويب "كورساتي"',
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 13, color: Colors.grey)),
          ],
        ]),
      );
}

// ── Course Analytics Card ────────────────────────────────────────────────────
class _CourseAnalyticsCard extends StatelessWidget {
  final TeacherCourse course;

  const _CourseAnalyticsCard({required this.course});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(children: [
        // Course header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                AppTheme.primary.withValues(alpha: 0.06),
                Colors.transparent
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.menu_book_rounded,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(course.title,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.people_rounded,
                        size: 13, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text('${course.studentsCount} طالب',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey)),
                    const SizedBox(width: 10),
                    const Icon(Icons.video_library_outlined,
                        size: 13, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text('${course.sessionsCount} محاضرة',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey)),
                  ]),
                ])),
          ]),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: Row(children: [
            // Attendance
            Expanded(
              child: _ActionButton(
                icon: Icons.fact_check_rounded,
                label: 'الحضور',
                sublabel: 'تسجيل وتعديل',
                color: AppTheme.success,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeacherAttendanceScreen(
                      courseId: course.id,
                      courseTitle: course.title,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Exams
            Expanded(
              child: _ActionButton(
                icon: Icons.quiz_rounded,
                label: 'الاختبارات',
                sublabel: 'إنشاء وإدارة',
                color: AppTheme.primary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TeacherExamHubScreen(
                      courseId: course.id,
                      courseTitle: course.title,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.icon,
      required this.label,
      required this.sublabel,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color)),
              Text(sublabel,
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 10, color: Colors.grey)),
            ]),
          ]),
        ),
      );
}
