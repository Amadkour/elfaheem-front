import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/courses/my_courses/my_courses_provider.dart';
import 'package:flutter_education_app/features/student/models.dart'
    show CourseModel;
import 'package:provider/provider.dart';

import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../courses/details/course_detail_screen.dart';
import '../../courses/list/courses_provider.dart';

class MyCoursesRow extends StatelessWidget {
  const MyCoursesRow({super.key, required this.showMyCourses});
  final bool showMyCourses;
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CoursesProvider>();
    final isWide = MediaQuery.of(context).size.width >= 680;

    if (provider.isLoading) {
      return  SizedBox(
        height: 270,
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(context.colors.primary),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (showMyCourses && provider.explorHomecourses.isEmpty ||provider.myCourses.isEmpty  ) {
      return  SizedBox(
        height: 100,
        child: Center(child: Text('لا توجد كورسات', style: context.colors.body)),
      );
    }

    final display = showMyCourses? provider.myCourses.take(6).toList():provider.explorHomecourses.take(6).toList();

    // ── Wide: 3-column grid ─────────────────────────────────────────────────
    if (isWide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.68,
          ),
          itemCount: display.length,
          itemBuilder: (_, i) => _CourseCard(course: display[i],showMyCourses: showMyCourses,),
        ),
      );
    }

    // ── Mobile: horizontal scroll ───────────────────────────────────────────
    return SizedBox(
      height: 296,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: display.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) =>
            _CourseCard(course: display[i], fixedWidth: 188,showMyCourses: showMyCourses,),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Course Card — full data display
// ────────────────────────────────────────────────────────────────────────────
class _CourseCard extends StatelessWidget {
  final CourseModel course;
  final double? fixedWidth;
  final bool showMyCourses;

  const _CourseCard({required this.course, this.fixedWidth, required this.showMyCourses});

  Color? get _accentColor {
    final name = course.categoryName?.toLowerCase() ?? '';
    if (name.contains('برمج') || name.contains('تقن')) return const Color(0xFF5B4FCF);
    if (name.contains('رياض') || name.contains('علوم')) return const Color(0xFF0F6E56);
    if (name.contains('لغ')) return const Color(0xFFD85A30);
    if (name.contains('تصم') || name.contains('فن')) return const Color(0xFFD4537E);
    return null;
  }

  bool get _isLive => course.type == 'live';
  bool get _hasProgress => course.progress >= 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CourseDetailScreen(course: course)),
      ),
      child: Container(
        width: fixedWidth,
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.07),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Thumbnail(course: course, isLive: _isLive),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    course.title,
                    style: context.colors.h3.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  // Teacher
                  if (course.instructorName.isNotEmpty)
                    _TeacherRow(
                      name: course.instructorName,
                      accentColor: _accentColor??context.colors.primary,
                      accentLight: (_accentColor??context.colors.primary).withValues(alpha:0.12),
                    ),

                  const _CardDivider(),

                  // Rating + students
                  _StatsRow(course: course),
                  const SizedBox(height: 6),

                  // Lectures + hours
                  _MetaRow(course: course),
                  const SizedBox(height: 8),

                  // Category pill + price
                  _BottomRow(
                    course: course,
                    accentColor: _accentColor??context.colors.primary,
                    accentLight: (_accentColor??context.colors.primary)..withValues(alpha:0.12),
                  ),
// Progress bar — only when enrolled
                  if (_hasProgress && showMyCourses) ...[
                    const SizedBox(height: 9),
                    _ProgressBar(progress: course.progress),
                  ],
                  //],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Thumbnail ────────────────────────────────────────────────────────────────
class _Thumbnail extends StatelessWidget {
  final CourseModel course;
  final bool isLive;

  const _Thumbnail({required this.course, required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AppNetworkImage(
          url: course.imageUrl,
          width: double.infinity,
          height: 118,
        ),
        // Bottom dark gradient for readability
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black.withValues(alpha:0.36)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // Type badge — top right
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha:0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isLive ? 'مباشر' : 'مسجّل',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ),

        // Favorite heart — top left
        Positioned(
          top: 8,
          left: 10,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.88),
              shape: BoxShape.circle,
            ),
            child: Icon(
              course.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              size: 15,
              color: course.isFavorite
                  ? const Color(0xFFE24B4A)
                  : Colors.grey.shade400,
            ),
          ),
        ),

        // Price badge — bottom right
        Positioned(
          bottom: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: course.price == 0
                  ? const Color(0xFF0F6E56)
                  : context.colors.primary,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: (course.price == 0
                      ? const Color(0xFF0F6E56)
                      : context.colors.primary)
                      .withValues(alpha:0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              course.price == 0
                  ? 'مجاني'
                  : '\$ ${course.price.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Teacher row ──────────────────────────────────────────────────────────────
class _TeacherRow extends StatelessWidget {
  final String name;
  final Color accentColor;
  final Color accentLight;

  const _TeacherRow({
    required this.name,
    required this.accentColor,
    required this.accentLight,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0] : '؟';
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: accentLight, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accentColor,
              fontFamily: 'Cairo',
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'أ. $name',
            style: context.colors.caption.copyWith(fontSize: 11, color: context.colors.textLight),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

// ── Thin divider ─────────────────────────────────────────────────────────────
class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: Colors.black.withValues(alpha:0.07),
      ),
    );
  }
}

// ── Rating + students ────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final CourseModel course;

  const _StatsRow({required this.course});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
         Icon(Icons.star_rounded, color: context.colors.accent, size: 13),
        const SizedBox(width: 3),
        Text(
          course.rate?.toStringAsFixed(1) ?? '–',
          style: context.colors.caption.copyWith(
            color: context.colors.textDark,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        _Dot(),
        Expanded(
          child: Text(
            '${course.studentsCount} طالب',
            style: context.colors.caption.copyWith(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Lectures + hours ─────────────────────────────────────────────────────────
class _MetaRow extends StatelessWidget {
  final CourseModel course;

  const _MetaRow({required this.course});

  @override
  Widget build(BuildContext context) {
    final hasLectures = course.sessions.isNotEmpty;
    final hasHours = course.hoursCount > 0;

    if (!hasLectures && !hasHours) return const SizedBox.shrink();

    return Row(
      children: [
        if (hasLectures) ...[
           Icon(Icons.play_circle_outline_rounded,
              size: 12, color: context.colors.textLight),
          const SizedBox(width: 3),
          Text(
            '${course.sessions.length} محاضرة',
            style: context.colors.caption.copyWith(fontSize: 10),
          ),
        ],
        if (hasLectures && hasHours) _Dot(),
        if (hasHours) ...[
           Icon(Icons.access_time_rounded,
              size: 12, color: context.colors.textLight),
          const SizedBox(width: 3),
          Text(
            '${course.hoursCount} ساعة',
            style: context.colors.caption.copyWith(fontSize: 10),
          ),
        ],
      ],
    );
  }
}

// ── Bottom row: category + price ─────────────────────────────────────────────
class _BottomRow extends StatelessWidget {
  final CourseModel course;
  final Color accentColor;
  final Color accentLight;

  const _BottomRow({
    required this.course,
    required this.accentColor,
    required this.accentLight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (course.categoryName != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: accentLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              course.categoryName!,
              style: context.colors.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        Text(
          course.price == 0
              ? 'مجاني'
              : '\$ ${course.price.toStringAsFixed(0)}',
          style: TextStyle(
            color: course.price == 0
                ? const Color(0xFF0F6E56)
                : context.colors.accent,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }
}

// ── Progress bar ─────────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final double progress;

  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('تقدمك', style: context.colors.caption.copyWith(fontSize: 10)),
            Text(
              '$pct%',
              style: context.colors.caption.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: context.colors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: context.colors.primaryLight,
            valueColor:  AlwaysStoppedAnimation(context.colors.primary),
          ),
        ),
      ],
    );
  }
}

// ── Dot separator ────────────────────────────────────────────────────────────
class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return  Padding(
      padding: EdgeInsets.symmetric(horizontal: 5),
      child: CircleAvatar(radius: 1.5, backgroundColor: context.colors.textLight),
    );
  }
}