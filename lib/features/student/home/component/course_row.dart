import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart'
    show CourseModel;
import '../../../../config/app_config.dart';
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../../shared/profile/course_instractor_profile.dart';
import '../../courses/details/course_detail_screen.dart';

class CoursesRow extends StatelessWidget {
  final List<CourseModel> courses;
  const CoursesRow({super.key, required this.courses});

  @override
  Widget build(BuildContext context) {
    final ScrollController controller=ScrollController();

    if (courses.isEmpty) {
      return SizedBox(
        height: 100,
        child:
            Center(child: Text('no_courses_yet'.tr, style: context.colors.body)),
      );
    }
    // ── Mobile: horizontal scroll ───────────────────────────────────────────
    Widget list= SizedBox(
      height: context.height/2 >300?300:context.height/4,
      child: ListView.separated(
        controller: controller,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: courses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _CourseCard(course: courses[i], fixedWidth: 188),
      ),
    );
    if (!kIsWeb) return list;
    return Scrollbar(
      controller: controller,
      thumbVisibility: true, // This keeps the 'cursor' visible
      trackVisibility: true, // Optional: shows the path of the scrollbar
      child: list,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Course Card — full data display
// ────────────────────────────────────────────────────────────────────────────
class _CourseCard extends StatelessWidget {
  final CourseModel course;
  final double? fixedWidth;

  const _CourseCard({required this.course, this.fixedWidth});

  bool get _isLive => course.type == 'live';

  bool get _hasProgress => course.progress > 0;

  @override
  Widget build(BuildContext context) {
    final hasLectures = course.sessions.isNotEmpty;
    final hasHours = course.hoursCount > 0;
    final hasCertificate = course.certificates.isNotEmpty;
    final hasStudents = course.studentsCount > 0;
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
              color: Colors.black.withValues(alpha: 0.07),
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
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
                       // if (course.rate != null)
                          _StatsRow(course: course),
                      ],
                    ),


                    if (course.categoryName != null &&
                        course.categoryName!.isNotEmpty)

                      Text(
                          course.categoryName!,
                          style: context.colors.caption.copyWith(
                            color: context.colors.textLight,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),


                    Divider(),
                    // Teacher
                    if (course.teacher != Null)
                      InstructorAvatar(
                        teacher: course.teacher!,
                        size: 30,
                        canOpen: true,
                        showTitle: true,
                      ),

                    const _CardDivider(),

                    // Rating + students
                    Spacer(flex: 1),
                    if (hasStudents || hasCertificate)
                      _StudentRow(
                          course: course,
                          hasStudents: hasStudents,
                          hasCertificate: hasCertificate),
                    Spacer(),

                    // Lectures + hours
                    if (hasHours || hasLectures)
                      _MetaRow(
                        course: course,
                        hasHours: hasHours,
                        hasLectures: hasLectures,
                      ),
                    Spacer(
                      flex: 2,
                    ),


                    // Progress bar — only when enrolled
                   if ( course.isEnrolled) ...[
                      const SizedBox(height: 9),
                      _ProgressBar(progress: course.progress),
                   // ],
                    Spacer(
                      flex: 2,
                    ),
                  ],
                ]),
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
          height: context.height/6>150?150:context.height/8,
          heroTag: "course-row-card-${course.id}",
        ),
        // Bottom dark gradient for readability
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.36)
                ],
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
              color: Colors.black.withValues(alpha: 0.45),
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
              color: Colors.white.withValues(alpha: 0.88),
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
                      .withValues(alpha: 0.35),
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


class IconColored extends StatelessWidget{
  final Color color;
  final IconData icon;

  const IconColored({super.key, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) {
   return  Container(
     width: 20,
     height: 20,
     decoration: BoxDecoration(
       color: color.withValues(alpha: 0.12),
       borderRadius: BorderRadius.circular(5),
     ),
     child: Icon(icon, size: 13, color: color),
   );
  }

}
// ── Thin divider ─────────────────────────────────────────────────────────────
class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: Colors.black.withValues(alpha: 0.07),
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
      ],
    );
  }
}

// ── Lectures + hours ─────────────────────────────────────────────────────────
class _MetaRow extends StatelessWidget {
  final CourseModel course;
  final bool hasLectures, hasHours;

  const _MetaRow(
      {required this.course,
      required this.hasLectures,
      required this.hasHours});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasLectures) ...[
          IconColored(color: context.colors.primary, icon: Icons.play_circle_outline_rounded,),
          const SizedBox(width: 3),
          Text(
            '${course.sessions.length} ${'session'.tr}',
            style: context.colors.caption.copyWith(fontSize: 10),
          ),
        ],
        if (hasLectures && hasHours) Spacer(),
        if (hasHours) ...[
          IconColored(color: context.colors.accent, icon: Icons.access_time_rounded,),
          const SizedBox(width: 3),
          Text(
            '${course.hoursCount} ساعة',
            style: context.colors.caption.copyWith(fontSize: 10),
          ),
        ],
        Spacer(),
      ],
    );
  }
}

// ── Lectures + hours ─────────────────────────────────────────────────────────
class _StudentRow extends StatelessWidget {
  final CourseModel course;
  final bool hasStudents, hasCertificate;

  const _StudentRow(
      {required this.course,
      required this.hasStudents,
      required this.hasCertificate});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasCertificate) ...[
          IconColored(color: context.colors.success, icon:Icons.workspace_premium_rounded),

          const SizedBox(width: 3),
          Text(
            course.certificates.first.title,
            style: context.colors.caption.copyWith(fontSize: 10),
          ),
        ],
        if (hasStudents && hasCertificate) Spacer(),

        if (hasStudents) ...[
          IconColored(color: context.colors.accent2, icon:CupertinoIcons.group),

          const SizedBox(width: 3),
          Text(
            '${course.studentsCount} ${'student'.tr}',
            style: context.colors.caption.copyWith(fontSize: 10),
          ),
        ],
        Spacer(),
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
            valueColor: AlwaysStoppedAnimation(context.colors.primary),
          ),
        ),
      ],
    );
  }
}