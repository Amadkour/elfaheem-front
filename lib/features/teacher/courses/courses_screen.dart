// ignore_for_file: depend_on_referenced_packages, use_build_context_synchronously
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/courses/update_course_screen.dart';
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
import 'course_form_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  TeacherCoursesScreen
// ═══════════════════════════════════════════════════════════════════════════════

class TeacherCoursesScreen extends StatefulWidget {
  const TeacherCoursesScreen({super.key});

  @override
  State<TeacherCoursesScreen> createState() => _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<TeacherProvider>().fetchMyCourses(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = context.showSidebar;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        floatingActionButton: isWide ? null : _FloatingAddBtn(),
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              isWide
                  ? const _WebHeader()
                  : ScreenAppBar(title: 'my_courses'.tr),
              const SizedBox(height: 4),
              const _FilterTabs(),
              const SizedBox(height: 10),
              const Expanded(child: _CourseList()),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Header variants
// ═══════════════════════════════════════════════════════════════════════════════

class _WebHeader extends StatelessWidget {
  const _WebHeader();

  @override
  Widget build(BuildContext context) => Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Text('my_courses'.tr, style: AppTheme.h2.copyWith(fontSize: 17)),
            const Spacer(),
            _AddCourseButton(compact: false),
          ],
        ),
      );
}

class _FloatingAddBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CourseFormScreen()),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: AppTheme.primaryShadow,
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
        ),
      );
}

class _AddCourseButton extends StatelessWidget {
  final bool compact;

  const _AddCourseButton({required this.compact});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CourseFormScreen()),
        ),
        child: Container(
          height: 38,
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                compact ? 'add'.tr : 'add_course'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Filter tabs
// ═══════════════════════════════════════════════════════════════════════════════

class _FilterTabs extends StatelessWidget {
  const _FilterTabs();

  static const _tabs = [
    (TeacherCourseStatus.all, 'filter_all', Icons.apps_rounded),
    (TeacherCourseStatus.published, 'filter_published', Icons.public_rounded),
    (TeacherCourseStatus.draft, 'filter_drafts', Icons.drafts_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 46,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(14),
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
            final (status, labelKey, icon) = t;
            final active = p.activeFilter == status;
            return Expanded(
              child: GestureDetector(
                onTap: () => context.read<TeacherProvider>().setFilter(status),
                child: Container(
                  //  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    // gradient: active ? AppTheme.primaryGradient : null,
                    border: active
                        ? Border(
                            bottom: BorderSide(
                              color: AppTheme.primaryBlue,
                              width: 1,
                            ),
                          )
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon,
                            size: 13,
                            color: active
                                ? AppTheme.primaryBlue
                                : AppTheme.textLight),
                        const SizedBox(width: 5),
                        Text(
                          labelKey.tr,
                          style: AppTheme.label.copyWith(
                            color: active
                                ? AppTheme.primaryBlue
                                : AppTheme.textLight,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
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

// ═══════════════════════════════════════════════════════════════════════════════
//  Course list
//  Web → _TwoColumnMasonry (self-sizing, no childAspectRatio)
//  Mobile → plain ListView
// ═══════════════════════════════════════════════════════════════════════════════

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
          strokeWidth: 2.5,
        ),
      );
    }

    final courses = p.filteredCourses;
    if (courses.isEmpty) return const _EmptyState();

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () => p.fetchMyCourses(),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
          child: isWide
              ? _TwoColumnMasonry(courses: courses)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  physics: const BouncingScrollPhysics(),
                  itemCount: courses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => _CourseCard(course: courses[i]),
                ),
        ),
      ),
    );
  }
}

/// Two-column masonry: splits courses into left/right lists so each card
/// sizes itself naturally — no fixed childAspectRatio, no overflow.
class _TwoColumnMasonry extends StatelessWidget {
  final List<TeacherCourse> courses;

  const _TwoColumnMasonry({required this.courses});

  @override
  Widget build(BuildContext context) {
    final left = <TeacherCourse>[];
    final right = <TeacherCourse>[];
    for (var i = 0; i < courses.length; i++) {
      (i.isEven ? left : right).add(courses[i]);
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: left
                  .map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _CourseCard(course: c),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              children: right
                  .map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _CourseCard(course: c),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Empty state
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryLight.withValues(alpha: 0.5),
                      AppTheme.primaryLight.withValues(alpha: 0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.school_outlined,
                    size: 40, color: AppTheme.primary),
              ),
              const SizedBox(height: 18),
              Text(
                'no_courses_section'.tr,
                style: AppTheme.body
                    .copyWith(fontWeight: FontWeight.w600, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'add_first_course_hint'.tr,
                style: AppTheme.caption.copyWith(color: AppTheme.textLight),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CourseFormScreen())),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.primaryShadow,
                  ),
                  child: Text(
                    'add_new_course'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo',
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Course card
// ═══════════════════════════════════════════════════════════════════════════════

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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'delete_course'.tr,
            style: const TextStyle(
                fontFamily: 'Cairo', fontWeight: FontWeight.w800),
          ),
          content: Text(
            '${'delete_course_confirm'.tr} "${widget.course.title}"؟',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr,
                  style: const TextStyle(
                      fontFamily: 'Cairo', color: AppTheme.textMedium)),
            ),
            Container(
              decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(10)),
              child: TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('delete'.tr,
                    style: const TextStyle(
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
      final deleted =
          await context.read<TeacherProvider>().deleteCourse(widget.course.id);
      if (mounted && deleted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('course_deleted'.tr,
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryBlue),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.09),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Full-width 16:9 thumbnail with overlaid actions ──────────
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: AppNetworkImage(
                  url: c.imageUrl,
                  width: double.infinity,
                  borderRadius: BorderRadius.zero,
                ),
              ),
              // Status badge — top right
              Positioned(
                top: 8,
                right: 8,
                child: _StatusBadge(isDraft: isDraft),
              ),
              // Edit / Delete overlay buttons — top left
              Positioned(
                top: 8,
                left: 8,
                child: Row(
                  children: [
                    _OverlayBtn(
                      icon: Icons.edit_rounded,
                      color: AppTheme.primary,
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CourseFormScreen(
                                  course: c,
                                )));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Title + stats ────────────────────────────────────────────
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TeacherSessionsScreen(course: c)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.title,
                    style: AppTheme.h3
                        .copyWith(fontSize: 14, fontWeight: FontWeight.w800),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // 2×2 stats grid — deterministic height, no Wrap
                  _StatsGrid(course: c),
                ],
              ),
            ),
          ),

          // ── Expand toggle ────────────────────────────────────────────

          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  Text(
                    _expanded ? 'hide_details'.tr : 'show_details'.tr,
                    style: AppTheme.label
                        .copyWith(color: AppTheme.primary, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: AppTheme.primary),
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable extras ────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            child: _expanded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Divider(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.07)),
                      _ExtrasPanel(course: c),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          // ── Publish / unpublish ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child:
                      _PublishButton(isDraft: isDraft, onTap: _togglePublish),
                ),
                Container(
                    height: 40,
                    width: 40,
                    margin: EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.all(Radius.circular(7)),
                    ),
                    child: IconButton(
                      onPressed: _confirmDelete,
                      icon: Icon(
                        Icons.delete,
                        color: Colors.white,
                        size: 20,
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Stats — 2×2 fixed grid so height is always deterministic
// ═══════════════════════════════════════════════════════════════════════════════

class _StatsGrid extends StatelessWidget {
  final TeacherCourse course;

  const _StatsGrid({required this.course});

  @override
  Widget build(BuildContext context) {
    final c = course;
    final rows = [
      [
        (
          Icons.people_alt_rounded,
          '${c.studentsCount} ${'student'.tr}',
          AppTheme.primary
        ),
        (
          Icons.video_library_rounded,
          '${c.sessionsCount} ${'session'.tr}',
          const Color(0xFF185FA5)
        ),
      ],
      [
        (
          Icons.access_time_rounded,
          '${c.totalHours.toStringAsFixed(0)}${'h'.tr}',
          const Color(0xFFBA7517)
        ),
        (
          Icons.star_rounded,
          c.averageRating.toStringAsFixed(1),
          AppTheme.accent
        ),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows.map((row) {
        final isLast = row == rows.last;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
          child: Row(
            children: row.map((item) {
              final (icon, label, color) = item;
              final isLastInRow = item == row.last;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: isLastInRow ? 0 : 4),
                  child: _StatCell(icon, label, color),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatCell(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: AppTheme.caption
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Status badge
// ═══════════════════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final bool isDraft;

  const _StatusBadge({required this.isDraft});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDraft ? const Color(0xFFf59e0b) : AppTheme.accent2,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          isDraft ? 'status_draft'.tr : 'status_published'.tr,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            fontFamily: 'Cairo',
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Overlay button (sits on top of the thumbnail image)
// ═══════════════════════════════════════════════════════════════════════════════

class _OverlayBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _OverlayBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 15),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Publish button
// ═══════════════════════════════════════════════════════════════════════════════

class _PublishButton extends StatelessWidget {
  final bool isDraft;
  final VoidCallback onTap;

  const _PublishButton({required this.isDraft, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color primaryColor = isDraft ? AppTheme.primary : AppTheme.danger;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: BoxBorder.all(color: primaryColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDraft ? Icons.upload_rounded : Icons.visibility_off_rounded,
              color: primaryColor,
              size: 16,
            ),
            const SizedBox(width: 7),
            Text(
              isDraft ? 'publish_course'.tr : 'unpublish_course'.tr,
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Extras panel
// ═══════════════════════════════════════════════════════════════════════════════

class _ExtrasPanel extends StatelessWidget {
  final TeacherCourse course;

  const _ExtrasPanel({required this.course});

  @override
  Widget build(BuildContext context) {
    final hasContent = course.schedules.isNotEmpty ||
        course.certificates.isNotEmpty ||
        course.tools.isNotEmpty ||
        course.prerequisites.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasContent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('no_extra_details'.tr,
                  style: AppTheme.caption.copyWith(color: AppTheme.textLight)),
            ),
          if (course.schedules.isNotEmpty)
            _ExtRow(
              Icons.calendar_month_rounded,
              'weekly_schedule'.tr,
              course.schedules
                  .map((s) => '${s.dayLabel}  ${s.startTime} – ${s.endTime}')
                  .toList(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => TeacherSchedulesScreen(course: course)),
              ),
            ),
          if (course.certificates.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtRow(
              Icons.workspace_premium_rounded,
              'certificates'.tr,
              course.certificates.map((c) => c.title).toList(),
            ),
          ],
          if (course.tools.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtRow(
              Icons.build_rounded,
              'required_tools'.tr,
              course.tools.map((t) => t.name).toList(),
            ),
          ],
          if (course.prerequisites.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtRow(
              Icons.checklist_rounded,
              'prerequisites'.tr,
              course.prerequisites.map((p) => p.title).toList(),
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 13, color: AppTheme.primary),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    style: AppTheme.label
                        .copyWith(color: AppTheme.primary, fontSize: 12),
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_left_rounded,
                      size: 16, color: AppTheme.primary),
              ],
            ),
            const SizedBox(height: 5),
            ...items.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(right: 29, bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: AppTheme.textLight,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(child: Text(item, style: AppTheme.caption)),
                      ],
                    ),
                  ),
                ),
            if (items.length > 3)
              Padding(
                padding: const EdgeInsets.only(right: 29, top: 2),
                child: Text(
                  '+ ${items.length - 3} ${'others'.tr}',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      );
}
