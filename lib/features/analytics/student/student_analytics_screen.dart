// features/student/analytics/student_analytics_screen.dart
// Used as-is in DashboardScreen — no constructor params needed.
// Shows all enrolled courses; tapping one opens StudentCourseAnalyticsScreen.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/analytics/student/exam/student_exam_list_screen.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'exam/student_exam_provider.dart';
import 'student_attendance_model.dart';
import 'student_analytics_provider.dart';
import 'student_course_analytics_screen.dart';

class StudentAnalyticsScreen extends StatelessWidget {
  const StudentAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => StudentAnalyticsProvider()..loadCourses(),
        child: const _StudentAnalyticsView(),
      );
}

// ── Hub view ─────────────────────────────────────────────────────────────────

class _StudentAnalyticsView extends StatefulWidget {
  const _StudentAnalyticsView();

  @override
  State<_StudentAnalyticsView> createState() => _StudentAnalyticsViewState();
}

class _StudentAnalyticsViewState extends State<_StudentAnalyticsView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final prov = context.watch<StudentAnalyticsProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Column(children: [
            _buildHeader(prov),
            _buildSearchBar(prov),
            Expanded(child: _buildBody(prov)),
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader(StudentAnalyticsProvider prov) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('اختباراتي وحضوري',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87)),
              const SizedBox(height: 2),
              const Text('اختر كورساً لعرض سجل حضورك ونتائجك',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 13, color: Colors.grey)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.analytics_rounded,
                color: context.colors.primary, size: 24),
          ),
        ]),
      );

  Widget _buildSearchBar(StudentAnalyticsProvider prov) => Padding(
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
            suffixIcon: prov.search.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      prov.setSearch('');
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
          onChanged: prov.setSearch,
        ),
      );

  Widget _buildBody(StudentAnalyticsProvider prov) {
    if (prov.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (prov.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(prov.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: prov.loadCourses,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ),
      );
    }

    final list = prov.filtered;
    if (list.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.school_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            prov.courses.isEmpty
                ? 'لم تسجّل في أي كورس بعد'
                : 'لا توجد نتائج للبحث',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                color: Colors.grey,
                fontWeight: FontWeight.w600),
          ),
          if (prov.courses.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('اذهب إلى "كورساتي" للتسجيل',
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 13, color: Colors.grey)),
          ],
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: prov.loadCourses,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) => _CourseCard(
          course: list[i],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentCourseAnalyticsScreen(
                courseId: list[i].id,
                courseTitle: list[i].title,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Course card ───────────────────────────────────────────────────────────────

class _CourseCard extends StatelessWidget {
  final EnrolledCourse course;
  final VoidCallback onTap;

  const _CourseCard({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
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
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    context.colors.primary.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(children: [
                // Thumbnail or icon
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: course.imageUrl != null && course.imageUrl!.isNotEmpty
                      ? Image.network(course.imageUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _coursePlaceholder(context))
                      : _coursePlaceholder(context),
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
                        if (course.teacherName != null) ...[
                          const SizedBox(height: 2),
                          Text(course.teacherName!,
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: Colors.grey)),
                        ],
                        const SizedBox(height: 6),
                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: course.progress / 100,
                            backgroundColor: Colors.grey.shade100,
                            color: context.colors.primary,
                            minHeight: 5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text('${course.progress.toStringAsFixed(0)}% مكتمل',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                color: Colors.grey)),
                      ]),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_back_ios_rounded,
                    size: 16, color: Colors.grey.shade400),
              ]),
            ),
            // Bottom action strip
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Row(children: [
                _ActionChip(
                  icon: Icons.fact_check_rounded,
                  label: 'الحضور',
                  color: context.colors.success,
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider(
                          create: (_) => StudentExamProvider()..loadMyExams(),
                          child: StudentExamListScreen(),
                        ),
                      ),
                    );
                  },
                  child: _ActionChip(
                    icon: Icons.quiz_rounded,
                    label: 'الاختبارات',
                    color: context.colors.primary,
                  ),
                ),
                const Spacer(),
                Row(children: [
                  const Icon(Icons.video_library_outlined,
                      size: 13, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text('${course.sessionsCount} محاضرة',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.grey)),
                ]),
              ]),
            ),
          ]),
        ),
      );

  Widget _coursePlaceholder(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.menu_book_rounded, color: context.colors.primary, size: 22),
      );
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ActionChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ]),
      );
}
