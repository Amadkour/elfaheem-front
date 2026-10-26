// features/student/courses/details/components/student_course_hero.dart
//
// Premium hero for the STUDENT course profile (mobile + web).
//  • sizes itself to the width it is given (LayoutBuilder) so the cover image
//    always fills its container: full-bleed on phones, a rounded card on web
//  • image fades in over a branded gradient (no flash, no layout jump)
//  • glass top bar (end-aligned): refresh (web only) · share · favourite
//  • category + private pills, title, teacher chip
//  • glass stats strip: students · lessons · hours (+ progress ring if enrolled)
//
// Facts shown here (students / lessons / hours / progress / category) are NOT
// repeated anywhere else on the screen.
import 'dart:ui';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/shared/course/topbar.dart';

import '../../../../../utils/helpers.dart';
import '../../../../shared/course/private_flag.dart';
import '../../../../teacher/sessions/components/course_reel_player.dart';
import '../../../models.dart';
import '../../../../shared/attendance/attendance_course_entry.dart';
// NOTE: add the same import your other screens use for the `.tr` String extension.

class StudentCourseHero extends StatelessWidget {
  const StudentCourseHero({
    super.key,
    required this.course,
    this.onBack, // kept so existing call sites still compile; the back button was removed
    required this.onRefresh,
    this.onLike,
    this.onShare,
    this.reelUrl,
    this.rounded = false,
    this.showRefresh = false,
  });

  final CourseModel course;
  final VoidCallback? onBack;
  final Future<void> Function() onRefresh;
  final VoidCallback? onLike;
  final VoidCallback? onShare;
  final String? reelUrl;

  /// true  → all four corners rounded (web card)
  /// false → full-bleed with rounded bottom corners (phone)
  final bool rounded;

  /// Pull-to-refresh doesn't exist with a mouse, so web shows a button.
  final bool showRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final String description=(ar? course.descriptionAr:course.descriptionEn)??'';
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite
            ? box.maxWidth
            : MediaQuery.of(context).size.width;
        final wide = w >= 800;
        final h = ((wide ? w * 0.48 : w * 1.0)
                .clamp(wide ? 300.0 : 330.0, wide ? 420.0 : 430.0)
                .toDouble()) +
            (_showAttendance ? 62.0 : 0.0); // room for the attendance entry
        final pad = wide ? 24.0 : 16.0;

        final pills = <Widget>[
          if (course.category != null)
            ParentComponent(
              featureKey: 'course_hero.category',
              child: _Pill(
                text: ar ? course.category!.nameAr : course.category!.nameEn,
                color: c.primary.withValues(alpha: 0.92),
              ),
            ),
          if (course.isPrivate)
            ParentComponent(
              featureKey: 'course_hero.private',
              child: PrivateFlag(label: 'course_hero_private'.tr),
            ),
        ];

        return SizedBox(
          height: h,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: rounded
                ? BorderRadius.circular(24)
                : const BorderRadius.vertical(bottom: Radius.circular(28)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _background(c),
                // cinematic scrim: dark top (buttons) + strong bottom (text)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.28, 0.55, 1],
                      colors: [
                        Color(0x99000000),
                        Color(0x00000000),
                        Color(0x33000000),
                        Color(0xF0080814),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 10, pad, wide ? 20 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ParentComponent(
                            featureKey: 'course_hero.topbar',
                            child: CourseDetailsTopBar(
                              onRefresh: onRefresh,
                              onLike: onLike,
                              onBack: () => Navigator.pop(context),
                              onShare: onShare,
                              showRefresh: true,
                              isFavorite: course.isFavorite,
                            )),
                        const Spacer(),
                        Directionality(
                          textDirection: Helpers.textDirOf(
                            description,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (pills.isNotEmpty) ...[
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: pills,
                                ),
                                const SizedBox(height: 10),
                              ],
                              Text(
                                (AppConfig.lang=='ar'? course.titleAr:course.titleEn)??'',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'tajawal',
                                  fontSize: wide ? 30 : 23,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                  color: Colors.white,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                ParentComponent(
                                    featureKey: 'course_hero.description',
                                    child: Text(
                                      description,
                                      style: TextStyle(
                                        fontFamily: 'tajawal',
                                        fontSize: 12,
                                        color: Colors.white.withValues(alpha: 0.80),
                                        height: 1.45,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    )),
                              ],
                              if (course.teacher != null) ...[
                                const SizedBox(height: 10),
                                ParentComponent(
                                  featureKey: 'course_hero.teacher',
                                  child: _TeacherChip(
                                    name: course.teacher!.name,
                                    imageUrl: course.teacher!.imageUrl,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              ParentComponent(featureKey: 'course_hero.stats', child: _statsStrip()),
                              if (_showAttendance) ...[
                                const SizedBox(height: 10),
                                ParentComponent(
                                    featureKey: 'course_hero.attendance',
                                    child: _attendanceButton(context)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Attendance ────────────────────────────────────────────────────────────

  int? get _courseId => int.tryParse(course.id.toString());
  bool get _showAttendance => course.isEnrolled && _courseId != null;

  Widget _attendanceButton(BuildContext context) => AttendanceCourseEntry(
      courseId: _courseId!, title: (ar ? course.titleAr : course.titleEn) ?? '');

  bool get ar => AppConfig.lang == 'ar';

  // ── Background ────────────────────────────────────────────────────────────

  Widget _background(dynamic c) {
    final reel = reelUrl;
    if (reel != null &&
        reel.isNotEmpty &&
        !AppConfig.disableList.contains('course_hero.reel')) {
      return CourseReelPlayer(
        key: ValueKey(reel),
        url: reel,
        posterUrl: course.imageUrl.isNotEmpty ? course.imageUrl : null,
      );
    }
    if (course.imageUrl.isNotEmpty) {
      // Gradient sits underneath, the photo fades in on top of it.
      return Stack(
        fit: StackFit.expand,
        children: [
          _fallback(c),
          Image.network(
            course.imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            frameBuilder: (_, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 350),
              child: child,
            ),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ],
      );
    }
    return _fallback(c);
  }

  Widget _fallback(dynamic c) => DecoratedBox(
    decoration: BoxDecoration(gradient: c.accentGradient),
    child: Center(
      child: Icon(
        Icons.school_rounded,
        size: 84,
        color: Colors.white.withValues(alpha: 0.14),
      ),
    ),
  );

  // ── Stats strip ───────────────────────────────────────────────────────────

  Widget _statsStrip() {
    final items = <_Stat>[
      _Stat(
        Icons.groups_rounded,
        '${course.studentsCount}',
        'course_hero_students'.tr,
      ),
      _Stat(
        Icons.play_circle_outline_rounded,
        '${course.sessionsCount}',
        'course_hero_lessons'.tr,
      ),
      _Stat(
        Icons.schedule_rounded,
        course.totalHours.toStringAsFixed(course.totalHours % 1 == 0 ? 0 : 1),
        'course_hero_hours'.tr,
      ),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                Expanded(child: items[i]),
                if (i != items.length - 1)
                  Container(
                    width: 1,
                    height: 28,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
              ],
              if (course.isEnrolled) ...[
                Container(
                  width: 1,
                  height: 28,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 12),
                ParentComponent(
                  featureKey: 'course_hero.progress',
                  child: _ProgressRing(percent: course.progress.clamp(0, 100) / 100),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label);

  final IconData icon;
  final String value, label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: Colors.white70),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'tajawal',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(
          fontFamily: 'tajawal',
          fontSize: 10.5,
          color: Colors.white70,
        ),
      ),
    ],
  );
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 38,
    height: 38,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CircularProgressIndicator(
          value: percent,
          strokeWidth: 3.5,
          backgroundColor: Colors.white24,
          valueColor: const AlwaysStoppedAnimation(Color(0xFF5CE0A8)),
        ),
        Text(
          '${(percent * 100).round()}%',
          style: const TextStyle(
            fontFamily: 'tajawal',
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

class _TeacherChip extends StatelessWidget {
  const _TeacherChip({required this.name, this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(
        radius: 13,
        backgroundColor: Colors.white24,
        backgroundImage: (imageUrl != null && imageUrl!.isNotEmpty)
            ? NetworkImage(imageUrl!)
            : null,
        child: (imageUrl == null || imageUrl!.isEmpty)
            ? Text(
          name.isNotEmpty ? name[0] : '?',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        )
            : null,
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'tajawal',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.color,
  });
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const fg = Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}