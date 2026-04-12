/// ─────────────────────────────────────────────────────────────────────────────
/// teacher_courses_screen.dart  —  API v3.2.0
///
/// Changes:
///   • Course card now shows sessions_count
///   • Course card shows average_rating (from API) instead of hardcoded 5.0
///   • Schedule / Certificates / Tools / Prerequisites shown in expand panel
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart' show TeacherCourseStatus, TeacherCourse;
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/app_bar.dart';
import '../home/teacher_provider.dart';
import '../schedules/schedules_screen.dart';
import '../sessions/sessions_screen.dart';
import 'add_course_screen.dart';

class TeacherCoursesScreen extends StatefulWidget {
  const TeacherCoursesScreen({super.key});

  @override
  State<TeacherCoursesScreen> createState() => _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen>{

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeacherProvider>().fetchMyCourses();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: const Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              ScreenAppBar(title: 'الكورسات'),
              SizedBox(height: 8),
              _FilterTabs(),
              SizedBox(height: 16),
              Expanded(child: _CourseList()),
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
    (TeacherCourseStatus.all, 'الكل'),
    (TeacherCourseStatus.published, 'منشورة'),
    (TeacherCourseStatus.draft, 'مسودات'),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: _tabs.map((t) {
          final (status, label) = t;
          final isActive = provider.activeFilter == status;
          return Expanded(
            child: GestureDetector(
              onTap: () => context.read<TeacherProvider>().setFilter(status),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                    color: isActive ? AppTheme.primary : Colors.transparent,
                    width: 2.5,
                  )),
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
    final provider = context.watch<TeacherProvider>();

    if (provider.isLoading && provider.filteredCourses.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppTheme.primary)));
    }

    final courses = provider.filteredCourses;

    if (courses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school_outlined,
                size: 64, color: AppTheme.textLight),
            const SizedBox(height: 12),
            const Text('لا توجد كورسات في هذا القسم', style: AppTheme.body),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddCourseScreen())),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('إضافة دورة جديدة',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo')),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () => provider.fetchMyCourses(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const BouncingScrollPhysics(),
        itemCount: courses.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) => _CourseCard(course: courses[i]),
      ),
    );
  }
}

// ── Course Card ───────────────────────────────────────────────────────────────

class _CourseCard extends StatefulWidget {
  final TeacherCourse course;

  const _CourseCard({required this.course});

  @override
  State<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<_CourseCard> {
  bool _expanded = false;

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
          title: const Text('حذف الدورة',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: Text('هل تريد حذف "${widget.course.title}"؟',
              style: const TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء',
                  style: TextStyle(
                      fontFamily: 'Cairo', color: AppTheme.textMedium)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      final ok =
          await context.read<TeacherProvider>().deleteCourse(widget.course.id);
      if (mounted && ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('تم حذف الدورة',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _togglePublish() async {
    final provider = context.read<TeacherProvider>();
    final ok = widget.course.isPublished
        ? await provider.unpublishCourse(widget.course.id)
        : await provider.publishCourse(widget.course.id);

    if (mounted && ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            widget.course.isPublished ? 'تم إيقاف نشر الدورة' : 'تم نشر الدورة',
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    final isDraft = !course.isPublished;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: AppTheme.cardShadow,
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TeacherSessionsScreen(course: course)),
          );
        },
        child: Column(
          children: [
            // ── Main row ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  AppNetworkImage(
                    url: course.imageUrl,
                    width: 90,
                    height: 90,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(course.title,
                            style: AppTheme.h3,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            _Meta(Icons.people_rounded,
                                '${course.studentsCount} طالب'),
                            _Meta(Icons.video_library_rounded,
                                '${course.sessionsCount} محاضرة'),
                            _Meta(Icons.access_time_rounded,
                                '${course.totalHours.toStringAsFixed(0)} ساعه'),
                            _Meta(Icons.star_rounded,
                                course.averageRating.toStringAsFixed(1),
                                color: AppTheme.accent),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _StatusBadge(isPublished: course.isPublished),
                      ],
                    ),
                  ),
                  Column(children: [
                    _IconBtn(
                        icon: Icons.delete_rounded,
                        color: AppTheme.danger,
                        bg: AppTheme.danger.withValues(alpha: 0.1),
                        onTap: _confirmDelete),
                    const SizedBox(height: 8),
                    _IconBtn(
                        icon: Icons.edit_rounded,
                        color: AppTheme.primary,
                        bg: AppTheme.primary.withValues(alpha: 0.1),
                        onTap: () {}),
                    const SizedBox(height: 8),
                    // Expand / collapse extras
                    _IconBtn(
                      icon: _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.textMedium,
                      bg: AppTheme.divider,
                      onTap: () => setState(() => _expanded = !_expanded),
                    ),
                  ]),
                ],
              ),
            ),

            // ── Extras (expandable) ─────────────────────────────────────────────
            if (_expanded) ...[
              const Divider(height: 1),
              _ExtrasPanel(course: course),
            ],

            // ── Publish button ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: GestureDetector(
                onTap: _togglePublish,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: isDraft
                        ? AppTheme.primaryGradient
                        : const LinearGradient(
                            colors: [Color(0xFF6B7280), Color(0xFF9CA3AF)]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: isDraft ? AppTheme.primaryShadow : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                          isDraft
                              ? Icons.upload_rounded
                              : Icons.visibility_off_rounded,
                          color: Colors.white,
                          size: 18),
                      const SizedBox(width: 8),
                      Text(isDraft ? 'نشر الدورة' : 'إيقاف النشر',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              fontFamily: 'Cairo')),
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

// ── Extras Panel ──────────────────────────────────────────────────────────────

class _ExtrasPanel extends StatelessWidget {
  final TeacherCourse course;

  const _ExtrasPanel({required this.course});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Schedule
          if (course.schedules.isNotEmpty) ...[
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TeacherSchedulesScreen(course: course),
                  ),
                );
              },
              child: _ExtrasRow(
                icon: Icons.calendar_month_rounded,
                label: 'الجدول الأسبوعي',
                items: course.schedules
                    .map((s) => '${s.dayLabel}  ${s.startTime} – ${s.endTime}')
                    .toList(),
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Certificates
          if (course.certificates.isNotEmpty) ...[
            _ExtrasRow(
              icon: Icons.workspace_premium_rounded,
              label: 'الشهادات',
              items: course.certificates.map((c) => c.title).toList(),
            ),
            const SizedBox(height: 10),
          ],
          // Tools
          if (course.tools.isNotEmpty) ...[
            _ExtrasRow(
              icon: Icons.build_rounded,
              label: 'الأدوات المطلوبة',
              items: course.tools.map((t) => t.name).toList(),
            ),
            const SizedBox(height: 10),
          ],
          // Prerequisites
          if (course.prerequisites.isNotEmpty) ...[
            _ExtrasRow(
              icon: Icons.checklist_rounded,
              label: 'المتطلبات السابقة',
              items: course.prerequisites.map((p) => p.title).toList(),
            ),
          ],
          if (course.schedules.isEmpty &&
              course.certificates.isEmpty &&
              course.tools.isEmpty &&
              course.prerequisites.isEmpty)
            Text('لا توجد تفاصيل إضافية — أضفها من شاشة إضافة الدورة',
                style: AppTheme.caption.copyWith(color: AppTheme.textLight)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ExtrasRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> items;

  const _ExtrasRow(
      {required this.icon, required this.label, required this.items});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(label,
                style: AppTheme.label
                    .copyWith(color: AppTheme.primary, fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(right: 20, bottom: 3),
                child: Row(children: [
                  const Icon(Icons.circle, size: 5, color: AppTheme.textLight),
                  const SizedBox(width: 6),
                  Expanded(child: Text(item, style: AppTheme.caption)),
                ]),
              )),
        ],
      );
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Meta(this.icon, this.label, {this.color = AppTheme.textLight});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: AppTheme.caption),
        ],
      );
}

class _StatusBadge extends StatelessWidget {
  final bool isPublished;

  const _StatusBadge({required this.isPublished});

  @override
  Widget build(BuildContext context) {
    final color = isPublished ? AppTheme.success : AppTheme.accent;
    final label = isPublished ? 'منشورة' : 'مسودة';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: AppTheme.caption
              .copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  const _IconBtn(
      {required this.icon,
      required this.color,
      required this.bg,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
      );
}
