// features/student/courses/details/components/student_course_hero.dart
//
// Premium hero for the STUDENT course profile (mobile + web).
//  • sizes itself to the width it is given (LayoutBuilder) so the cover image
//    always fills its container: full-bleed on phones, a rounded card on web
//  • image fades in over a branded gradient (no flash, no layout jump)
//  • glass top bar: back · refresh (web only) · share · favourite
//  • category + private pills, title, teacher chip
//  • glass stats strip: students · lessons · hours (+ progress ring if enrolled)
//
// Facts shown here (students / lessons / hours / progress / category) are NOT
// repeated anywhere else on the screen.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../../../teacher/sessions/components/course_reel_player.dart';
import '../../../models.dart';
import '../growth_tr.dart';

class StudentCourseHero extends StatelessWidget {
  const StudentCourseHero({
    super.key,
    required this.course,
    required this.onBack,
    required this.onRefresh,
    this.onLike,
    this.onShare,
    this.reelUrl,
    this.rounded = false,
    this.showRefresh = false,
  });

  final CourseModel course;
  final VoidCallback onBack;
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

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite
          ? box.maxWidth
          : MediaQuery.of(context).size.width;
      final wide = w >= 560;
      final h = (wide ? w * 0.48 : w * 1.0).clamp(wide ? 300.0 : 330.0, wide ? 420.0 : 430.0).toDouble();
      final pad = wide ? 24.0 : 16.0;

      final pills = <Widget>[
        if (course.category != null)
          _Pill(
            text: ar ? course.category!.nameAr : course.category!.nameEn,
            color: c.primary.withValues(alpha: 0.92),
          ),
        if (course.isPrivate)
          _Pill(
            icon: Icons.lock_rounded,
            text: gt('كورس خاص', 'Private'),
            color: const Color(0xFFC9A84C),
            dark: true,
          ),
      ];

      return SizedBox(
        height: h,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: rounded
              ? BorderRadius.circular(24)
              : const BorderRadius.vertical(bottom: Radius.circular(28)),
          child: Stack(fit: StackFit.expand, children: [
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _topBar(),
                  const Spacer(),
                  if (pills.isNotEmpty) ...[
                    Wrap(spacing: 8, runSpacing: 6, children: pills),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    course.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: wide ? 30 : 23,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      color: Colors.white,
                      shadows: const [Shadow(color: Colors.black54, blurRadius: 12)],
                    ),
                  ),
                  if (course.teacher != null) ...[
                    const SizedBox(height: 10),
                    _TeacherChip(
                      name: course.teacher!.name,
                      imageUrl: course.teacher!.imageUrl,
                    ),
                  ],
                  const SizedBox(height: 14),
                  _statsStrip(),
                ]),
              ),
            ),
          ]),
        ),
      );
    });
  }

  // ── Background ────────────────────────────────────────────────────────────

  Widget _background(dynamic c) {
    final reel = reelUrl;
    if (reel != null && reel.isNotEmpty) {
      return CourseReelPlayer(
        key: ValueKey(reel),
        url: reel,
        posterUrl: course.imageUrl.isNotEmpty ? course.imageUrl : null,
      );
    }
    if (course.imageUrl.isNotEmpty) {
      // Gradient sits underneath, the photo fades in on top of it.
      return Stack(fit: StackFit.expand, children: [
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
      ]);
    }
    return _fallback(c);
  }

  Widget _fallback(dynamic c) => DecoratedBox(
    decoration: BoxDecoration(gradient: c.accentGradient),
    child: Center(
      child: Icon(Icons.school_rounded, size: 84, color: Colors.white.withValues(alpha: 0.14)),
    ),
  );

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _topBar() => Row(children: [
    _GlassBtn(
      icon: Icons.arrow_back_ios_new_rounded,
      tooltip: gt('رجوع', 'Back'),
      onTap: onBack,
    ),
    const Spacer(),
    if (showRefresh) ...[
      _GlassBtn(
        icon: Icons.refresh_rounded,
        tooltip: gt('تحديث', 'Refresh'),
        onTap: () => onRefresh(),
      ),
      const SizedBox(width: 8),
    ],
    if (onShare != null)
      _GlassBtn(
        icon: Icons.ios_share_rounded,
        tooltip: gt('مشاركة', 'Share'),
        onTap: onShare!,
      ),
    if (onLike != null) ...[
      const SizedBox(width: 8),
      _GlassBtn(
        icon: course.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        iconColor: course.isFavorite ? const Color(0xFFFF5A7A) : Colors.white,
        tooltip: gt('المفضلة', 'Favourite'),
        onTap: onLike!,
      ),
    ],
  ]);

  // ── Stats strip ───────────────────────────────────────────────────────────

  Widget _statsStrip() {
    final items = <_Stat>[
      _Stat(Icons.groups_rounded, '${course.studentsCount}', gt('طالب', 'Students')),
      _Stat(Icons.play_circle_outline_rounded, '${course.sessionsCount}', gt('درس', 'Lessons')),
      _Stat(
        Icons.schedule_rounded,
        course.totalHours.toStringAsFixed(course.totalHours % 1 == 0 ? 0 : 1),
        gt('ساعة', 'Hours'),
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
          child: Row(children: [
            for (var i = 0; i < items.length; i++) ...[
              Expanded(child: items[i]),
              if (i != items.length - 1)
                Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.2)),
            ],
            if (course.isEnrolled) ...[
              Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(width: 12),
              _ProgressRing(percent: course.progress.clamp(0, 100) / 100),
            ],
          ]),
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
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 15, color: Colors.white70),
      const SizedBox(width: 5),
      Text(value,
          style: const TextStyle(
              fontFamily: 'tajawal', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
    ]),
    const SizedBox(height: 2),
    Text(label,
        style: const TextStyle(fontFamily: 'tajawal', fontSize: 10.5, color: Colors.white70)),
  ]);
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.percent});
  final double percent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 38,
    height: 38,
    child: Stack(alignment: Alignment.center, children: [
      CircularProgressIndicator(
        value: percent,
        strokeWidth: 3.5,
        backgroundColor: Colors.white24,
        valueColor: const AlwaysStoppedAnimation(Color(0xFF5CE0A8)),
      ),
      Text('${(percent * 100).round()}%',
          style: const TextStyle(
              fontFamily: 'tajawal', fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white)),
    ]),
  );
}

class _TeacherChip extends StatelessWidget {
  const _TeacherChip({required this.name, this.imageUrl});
  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    CircleAvatar(
      radius: 13,
      backgroundColor: Colors.white24,
      backgroundImage:
      (imageUrl != null && imageUrl!.isNotEmpty) ? NetworkImage(imageUrl!) : null,
      child: (imageUrl == null || imageUrl!.isEmpty)
          ? Text(name.isNotEmpty ? name[0] : '?',
          style: const TextStyle(color: Colors.white, fontSize: 12))
          : null,
    ),
    const SizedBox(width: 8),
    Flexible(
      child: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontFamily: 'tajawal', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
    ),
  ]);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, this.icon, this.dark = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? const Color(0xFF1A1405) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
        Text(text,
            style: TextStyle(fontFamily: 'tajawal', fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
      ]),
    );
  }
}

class _GlassBtn extends StatelessWidget {
  const _GlassBtn({
    required this.icon,
    required this.onTap,
    this.iconColor = Colors.white,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.black.withValues(alpha: 0.32),
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
          ),
        ),
      ),
    ),
  );
}