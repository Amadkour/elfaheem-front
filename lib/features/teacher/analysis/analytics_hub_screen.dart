library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/analysis/exam/exam_ui.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../courses/teacher_courses_provider.dart';
import '../home/teacher_models.dart';
import 'attendance/teacher_attendance_screen.dart';
import 'exam/teacher_exam_hub_screen.dart';
import 'flags/teacher_read_flags_screen.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

String _courseTitle(TeacherCourse c) =>
    (AppConfig.lang == 'ar' ? c.titleAr : c.titleEn) ?? '';

class TeacherAnalyticsHubScreen extends StatefulWidget {
  const TeacherAnalyticsHubScreen({super.key});

  @override
  State<TeacherAnalyticsHubScreen> createState() =>
      _TeacherAnalyticsHubScreenState();
}

class _TeacherAnalyticsHubScreenState extends State<TeacherAnalyticsHubScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(TeacherCourse c, String q) {
    final s = q.toLowerCase();
    return (c.titleAr?.toLowerCase().contains(s) ?? false) ||
        (c.titleEn?.toLowerCase().contains(s) ?? false) ||
        (c.descriptionEn?.toLowerCase().contains(s) ?? false) ||
        (c.descriptionAr?.toLowerCase().contains(s) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final prov = context.watch<TeacherCoursesProvider>();
    final all = prov.allCourses;
    final filtered =
    _search.isEmpty ? all : all.where((c) => _matches(c, _search)).toList();

    return BasePage(
      key: const ValueKey('analytics_hub'),
      useWebCard: true,
      enableFooterWidget: false,
      child: prov.isLoading
          ? const Center(child: AppLoadingIndicator())
          : Column(
        children: [
          ParentComponent(
            featureKey: 'analytics_hub.header',
            child: _buildHero(all),
          ),
          ParentComponent(
            featureKey: 'analytics_hub.search',
            child: _buildSearchBar(),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState(all.isEmpty)
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              physics: const BouncingScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) =>
              const SizedBox(height: 14),
              itemBuilder: (_, i) =>
                  _CourseAnalyticsCard(course: filtered[i]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero ────────────────────────────────────────────────────────────────────
  Widget _buildHero(List<TeacherCourse> all) {
    final students = all.fold<int>(0, (s, c) => s + c.studentsCount);
    final sessions = all.fold<int>(0, (s, c) => s + c.sessionsCount);

    return ExamHero(
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('analytics_hub_title'.tr,
                    style: examT(20, w: FontWeight.w800, c: Colors.white)),
                const SizedBox(height: 3),
                Text('analytics_hub_subtitle'.tr,
                    style: examT(12, c: Colors.white70, h: 1.5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.analytics_rounded,
                color: Colors.white, size: 26),
          ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          HeroStat(
            icon: Icons.menu_book_rounded,
            color: const Color(0xFF80D8FF),
            value: '${all.length}',
            label: 'courses'.tr,
          ),
          const SizedBox(width: 10),
          HeroStat(
            icon: Icons.people_rounded,
            color: const Color(0xFF69F0AE),
            value: '$students',
            label: 'total_students'.tr,
          ),
          const SizedBox(width: 10),
          HeroStat(
            icon: Icons.video_library_rounded,
            color: const Color(0xFFFFD740),
            value: '$sessions',
            label: 'sessions'.tr,
          ),
        ]),
      ]),
    );
  }

  Widget _buildSearchBar() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: ExamCard(
        radius: 16,
        child: TextField(
          controller: _searchCtrl,
          textDirection: Helpers.pageDirection,
          style: examT(14, c: c.textDark),
          decoration: InputDecoration(
            hintText: 'search_course_hint'.tr,
            hintStyle: examT(13, c: c.textMedium),
            prefixIcon:
            Icon(Icons.search_rounded, color: c.textMedium, size: 21),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
              icon: Icon(Icons.close_rounded,
                  color: c.textMedium, size: 18),
              onPressed: () {
                _searchCtrl.clear();
                if (mounted) setState(() => _search = '');
              },
            )
                : null,
            border: InputBorder.none,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onChanged: (v) {
            if (mounted) setState(() => _search = v);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool noCoursesAtAll) => ExamEmpty(
    icon: Icons.school_outlined,
    text: noCoursesAtAll
        ? '${'no_courses_yet'.tr}\n${'add_course_first_hint'.tr}'
        : 'no_search_results'.tr,
  );
}

// ── Course Analytics Card ────────────────────────────────────────────────────

class _CourseAnalyticsCard extends StatelessWidget {
  final TeacherCourse course;

  const _CourseAnalyticsCard({required this.course});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = _courseTitle(course);

    return ExamCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconTile(Icons.menu_book_rounded, c.primary, size: 50),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: examT(15, w: FontWeight.w800, c: c.textDark, h: 1.4)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    ExamChip(Icons.people_rounded,
                        '${course.studentsCount} ${'student'.tr}', Colors.teal),
                    ExamChip(Icons.video_library_outlined,
                        '${course.sessionsCount} ${'session'.tr}', kViolet),
                  ]),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: ParentComponent(
                featureKey: 'analytics_hub.attendance',
                child: _ActionButton(
                  icon: Icons.fact_check_rounded,
                  label: 'analytics_btn_attendance'.tr,
                  sublabel: 'analytics_btn_attendance_sub'.tr,
                  color: c.success,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TeacherAttendanceScreen(
                        courseId: course.id,
                        courseTitle: title,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ParentComponent(
                featureKey: 'analytics_hub.exams',
                child: _ActionButton(
                  icon: Icons.quiz_rounded,
                  label: 'analytics_btn_exams'.tr,
                  sublabel: 'analytics_btn_exams_sub'.tr,
                  color: c.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TeacherExamHubScreen(
                        courseId: course.id,
                        courseTitle: title,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          ParentComponent(
            featureKey: 'analytics_hub.read_flags',
            child: _ActionButton(
              icon: Icons.flag_rounded,
              label: 'tflag_btn'.tr,
              sublabel: 'tflag_btn_sub'.tr,
              color: kDanger,
              wide: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TeacherReadFlagsScreen(
                    courseId: course.id,
                    courseTitle: title,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final Color color;
  final bool wide;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: wide ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              color.withValues(alpha: 0.14),
              color.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: examT(13, w: FontWeight.w800, c: color)),
                const SizedBox(height: 1),
                Text(sublabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: examT(10.5, c: context.colors.textMedium)),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 12, color: color.withValues(alpha: 0.6)),
        ]),
      ),
    ),
  );
}