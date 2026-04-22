library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart'
    show TeacherCourseStatus, TeacherCourse;
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/app_bar.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../home/teacher_provider.dart';
import '../schedules/schedules_screen.dart';
import '../sessions/sessions_screen.dart';
import 'add_course_screen.dart';

class TeacherCoursesScreen extends StatefulWidget {
  const TeacherCoursesScreen({super.key});

  @override
  State<TeacherCoursesScreen> createState() =>
      _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
            (_) => context.read<TeacherProvider>().fetchMyCourses());
  }

  @override
  Widget build(BuildContext context) {
    final isWide = context.showSidebar;
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              if (!isWide)
                ScreenAppBar(title: 'الكورسات',
                    actions: [_AddBtn()])
              else
                _WebHeader(),

              const SizedBox(height: 8),
              const _FilterTabs(),
              const SizedBox(height: 14),
              const Expanded(child: _CourseList()),
            ],
          ),
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
      color: AppTheme.cardBg,
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 8,
            offset: const Offset(0, 2)),
      ],
    ),
    child: Row(children: [
      Text('كورساتي', style: AppTheme.h2.copyWith(fontSize: 16)),
      const Spacer(),
      GestureDetector(
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddCourseScreen())),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: AppTheme.primary.withValues(alpha:0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: const Row(children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text('إضافة كورس',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Cairo')),
          ]),
        ),
      ),
    ]),
  );
}

class _AddBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddCourseScreen())),
    child: Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: AppTheme.primaryShadow),
      child:
      const Icon(Icons.add_rounded, color: Colors.white, size: 22),
    ),
  );
}

// ── Filter tabs ───────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  const _FilterTabs();

  static  const _tabs = [
    (TeacherCourseStatus.all, 'الكل', Icons.apps_rounded),
    (TeacherCourseStatus.published, 'منشورة', Icons.public_rounded),
    (TeacherCourseStatus.draft, 'مسودات', Icons.drafts_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherProvider>();
    return ContentBox(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha:0.05),
                blurRadius: 10,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: _tabs.map((t) {
            final (status, label, icon) = t;
            final active = p.activeFilter == status;
            return Expanded(
              child: GestureDetector(
                onTap: () =>
                    context.read<TeacherProvider>().setFilter(status),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    gradient: active ? AppTheme.primaryGradient : null,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: active
                        ? [
                      BoxShadow(
                          color: AppTheme.primary.withValues(alpha:0.28),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ]
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon,
                            size: 13,
                            color: active
                                ? Colors.white
                                : AppTheme.textLight),
                        const SizedBox(width: 5),
                        Text(label,
                            style: AppTheme.label.copyWith(
                              color: active
                                  ? Colors.white
                                  : AppTheme.textLight,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 12,
                            )),
                      ],
                    ),
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
    final p = context.watch<TeacherProvider>();
    final isWide = context.showSidebar;

    if (p.isLoading && p.filteredCourses.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppTheme.primary),
              strokeWidth: 2.5));
    }

    final courses = p.filteredCourses;

    if (courses.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withValues(alpha:0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.school_outlined,
                size: 38, color: AppTheme.primary),
          ),
          const SizedBox(height: 14),
          const Text('لا توجد كورسات في هذا القسم',
              style: AppTheme.body),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AddCourseScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: AppTheme.primaryShadow),
              child: const Text('إضافة دورة جديدة',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo')),
            ),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () => p.fetchMyCourses(),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
          const BoxConstraints(maxWidth: Breakpoints.contentMax),
          child: isWide
              ? GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            physics: const BouncingScrollPhysics(),
            gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.5,
            ),
            itemCount: courses.length,
            itemBuilder: (_, i) => _CourseCard(course: courses[i]),
          )
              : ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: courses.length,
            separatorBuilder: (_, __) =>
            const SizedBox(height: 14),
            itemBuilder: (_, i) => _CourseCard(course: courses[i]),
          ),
        ),
      ),
    );
  }
}

// ── Course card ───────────────────────────────────────────────────────────────

class _CourseCard extends StatefulWidget {
  final TeacherCourse course;
  const _CourseCard({required this.course});

  @override
  State<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<_CourseCard> {
  bool _expanded = false;

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.cardBg,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('حذف الدورة',
              style: TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
          content: Text('هل تريد حذف "${widget.course.title}"؟',
              style: const TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: AppTheme.textMedium))),
            Container(
              decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(10)),
              child: TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      final deleted = await context
          .read<TeacherProvider>()
          .deleteCourse(widget.course.id);
      if (mounted && deleted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('تم حذف الدورة',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _togglePublish() async {
    final p = context.read<TeacherProvider>();
    await (widget.course.isPublished
        ? p.unpublishCourse(widget.course.id)
        : p.publishCourse(widget.course.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    final isDraft = !c.isPublished;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha:0.06),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // ── Main info ────────────────────────────────────────────────
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TeacherSessionsScreen(course: c)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              // Thumbnail
              Stack(children: [
                AppNetworkImage(
                    url: c.imageUrl,
                    width: 88,
                    height: 88,
                    borderRadius: BorderRadius.circular(14)),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDraft
                          ? AppTheme.accent
                          : AppTheme.accent2,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(isDraft ? 'مسودة' : 'منشورة',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Cairo')),
                  ),
                ),
              ]),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.title,
                          style: AppTheme.h3.copyWith(
                              fontSize: 14, fontWeight: FontWeight.w800),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 7),
                      Wrap(spacing: 10, runSpacing: 6, children: [
                        _Chip(Icons.people_alt_rounded,
                            '${c.studentsCount} طالب',
                            AppTheme.primary),
                        _Chip(Icons.video_library_rounded,
                            '${c.sessionsCount} محاضرة',
                            const Color(0xFF185FA5)),
                        _Chip(Icons.access_time_rounded,
                            '${c.totalHours.toStringAsFixed(0)}س',
                            const Color(0xFFBA7517)),
                        _Chip(Icons.star_rounded,
                            c.averageRating.toStringAsFixed(1),
                            AppTheme.accent),
                      ]),
                    ]),
              ),

              // Actions
              Column(children: [
                _ActionBtn(
                    icon: Icons.edit_rounded,
                    color: AppTheme.primary,
                    onTap: () {}),
                const SizedBox(height: 8),
                _ActionBtn(
                    icon: Icons.delete_rounded,
                    color: AppTheme.danger,
                    onTap: _confirmDelete),
                const SizedBox(height: 8),
                _ActionBtn(
                  icon: _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.textMedium,
                  onTap: () =>
                      setState(() => _expanded = !_expanded),
                ),
              ]),
            ]),
          ),
        ),

        // ── Expandable extras ─────────────────────────────────────────
        if (_expanded) ...[
          Divider(height: 0.5, color: Colors.black.withValues(alpha:0.07)),
          _ExtrasPanel(course: c),
        ],

        // ── Publish / unpublish ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: GestureDetector(
            onTap: _togglePublish,
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                gradient: isDraft
                    ? AppTheme.primaryGradient
                    : const LinearGradient(colors: [
                  Color(0xFF6B7280),
                  Color(0xFF9CA3AF)
                ]),
                borderRadius: BorderRadius.circular(22),
                boxShadow: isDraft
                    ? [
                  BoxShadow(
                      color: AppTheme.primary.withValues(alpha:0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]
                    : null,
              ),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        isDraft
                            ? Icons.upload_rounded
                            : Icons.visibility_off_rounded,
                        color: Colors.white,
                        size: 17),
                    const SizedBox(width: 7),
                    Text(isDraft ? 'نشر الدورة' : 'إيقاف النشر',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            fontFamily: 'Cairo')),
                  ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, size: 11, color: color),
      ),
      const SizedBox(width: 4),
      Text(label, style: AppTheme.caption.copyWith(fontSize: 11)),
    ],
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
          color: color.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha:0.2))),
      child: Icon(icon, color: color, size: 17),
    ),
  );
}

class _ExtrasPanel extends StatelessWidget {
  final TeacherCourse course;
  const _ExtrasPanel({required this.course});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (course.schedules.isNotEmpty)
          _ExtRow(
            Icons.calendar_month_rounded,
            'الجدول الأسبوعي',
            course.schedules
                .map((s) =>
            '${s.dayLabel}  ${s.startTime} – ${s.endTime}')
                .toList(),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    TeacherSchedulesScreen(course: course))),
          ),
        if (course.certificates.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ExtRow(
            Icons.workspace_premium_rounded,
            'الشهادات',
            course.certificates.map((c) => c.title).toList(),
          ),
        ],
        if (course.tools.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ExtRow(
            Icons.build_rounded,
            'الأدوات المطلوبة',
            course.tools.map((t) => t.name).toList(),
          ),
        ],
        if (course.prerequisites.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ExtRow(
            Icons.checklist_rounded,
            'المتطلبات السابقة',
            course.prerequisites.map((p) => p.title).toList(),
          ),
        ],
        if (course.schedules.isEmpty &&
            course.certificates.isEmpty &&
            course.tools.isEmpty &&
            course.prerequisites.isEmpty)
          Text('لا توجد تفاصيل إضافية',
              style: AppTheme.caption
                  .copyWith(color: AppTheme.textLight)),
        const SizedBox(height: 8),
      ],
    ),
  );
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
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 13, color: AppTheme.primary),
        ),
        const SizedBox(width: 7),
        Text(label,
            style: AppTheme.label
                .copyWith(color: AppTheme.primary, fontSize: 12)),
        if (onTap != null) ...[
          const Spacer(),
          const Icon(Icons.chevron_left_rounded,
              size: 16, color: AppTheme.primary),
        ],
      ]),
      const SizedBox(height: 5),
      ...items.map((item) => Padding(
        padding: const EdgeInsets.only(right: 29, bottom: 3),
        child: Row(children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
                color: AppTheme.textLight,
                shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(child: Text(item, style: AppTheme.caption)),
        ]),
      )),
    ]),
  );
}