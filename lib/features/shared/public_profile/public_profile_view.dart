// lib/features/shared/public_profile/public_profile_view.dart
//
// The public profile page's content (D-074), plain values only so the layout harness can pump it:
//
//   PublicProfileView(result:, onOpenCourse:, onRetry:, onBack:)
//     result == null                 loading skeleton
//     found + teacher                hero (photo · name · @username · specialization · courses / years / students),
//                                    "About" card, the public course cards (tap → the course page)
//     found + any other kind         the same hero, nothing else (a minimal card)
//     notFound / disabled / failed   a calm empty state (retry only on failed)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_responsive.dart' show Breakpoints;
import '../../../core/display/app_fonts.dart';
import '../../admin/admin_common.dart' show t;
import '../../student/models.dart' show CourseModel;
import '../course/course_row.dart' show CourseCard;
import 'public_profile.dart';

class PublicProfileView extends StatelessWidget {
  const PublicProfileView({
    super.key,
    required this.result,
    required this.onOpenCourse,
    this.onRetry,
    this.onBack,
  });

  /// null while loading.
  final PublicProfileResult? result;
  final void Function(CourseModel course) onOpenCourse;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) return const _ProfileSkeleton();
    final p = r.profile;
    if (r.status == PublicProfileStatus.found && p != null) return _ProfileBody(profile: p, onOpenCourse: onOpenCourse);
    return switch (r.status) {
      PublicProfileStatus.disabled => AppEmpty(
          icon: Icons.link_off_rounded,
          title: t('روابط الملفات الشخصية غير متاحة حالياً', 'Profile links are not available right now'),
          actionLabel: onBack == null ? null : t('رجوع', 'Back'),
          onAction: onBack,
        ),
      PublicProfileStatus.failed => AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: t('تعذّر فتح الملف الشخصي', 'Could not open the profile'),
          message: r.message,
          actionLabel: onRetry == null ? null : t('إعادة المحاولة', 'Retry'),
          onAction: onRetry,
        ),
      _ => AppEmpty(
          icon: Icons.person_search_rounded,
          title: t('الملف الشخصي غير موجود', 'Profile not found'),
          message: t('لا يوجد ملف عام بهذا الاسم، أو أن صاحبه لم يجعله عاماً.',
              'There is no public profile with this username, or its owner has not made it public.'),
          actionLabel: onBack == null ? null : t('رجوع', 'Back'),
          onAction: onBack,
        ),
    };
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.profile, required this.onOpenCourse});

  final PublicProfile profile;
  final void Function(CourseModel course) onOpenCourse;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _ProfileHero(profile: p),
            if (p.isTeacher && p.bio != null) ...[
              const SizedBox(height: 16),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: context.colors.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t('نبذة', 'About'), style: appText(14, w: FontWeight.w800, c: context.colors.textDark))),
                  ]),
                  const SizedBox(height: 8),
                  Text(p.bio!, style: appText(13, c: context.colors.textMedium, h: 1.6)),
                ]),
              ),
            ],
            if (p.isTeacher) ...[
              const SizedBox(height: 8),
              AppSectionTitle(
                t('الكورسات', 'Courses'),
                subtitle: p.coursesCount == 0
                    ? null
                    : t('${p.coursesCount} كورس منشور', '${p.coursesCount} published course${p.coursesCount == 1 ? '' : 's'}'),
              ),
              if (p.courses.isEmpty)
                AppCard(
                  child: Row(children: [
                    Icon(Icons.school_outlined, color: context.colors.textLight),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(t('لا توجد كورسات عامة بعد', 'No public courses yet'),
                          style: appText(13, c: context.colors.textMedium)),
                    ),
                  ]),
                )
              else
                _CourseGrid(courses: p.courses, onOpen: onOpenCourse),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.profile});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    final spec = p.specialization(AppConfig.lang);
    final students = p.courses.fold<int>(0, (s, x) => s + x.studentsCount);
    final stats = <Widget>[
      if (p.isTeacher) AppHeroStat(icon: Icons.menu_book_rounded, value: '${p.coursesCount}', label: t('كورسات', 'Courses')),
      if (p.isTeacher && p.experienceYears > 0)
        AppHeroStat(icon: Icons.workspace_premium_rounded, value: '${p.experienceYears}', label: t('سنوات خبرة', 'Years')),
      if (p.isTeacher && students > 0)
        AppHeroStat(icon: Icons.groups_rounded, value: appCompactNumber(students), label: t('طلاب', 'Students')),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge),
        gradient: LinearGradient(
          colors: [c.primary, c.primaryDark],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: c.primaryShadow,
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.heroGlassBorder, width: 2)),
          child: AppAvatar(name: p.name, url: p.imageUrl, size: 84),
        ),
        const SizedBox(height: 12),
        Text(
          p.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: appText(20, w: FontWeight.w800, c: c.onHero),
        ),
        const SizedBox(height: 4),
        // a username is always left to right, also in Arabic
        Text(
          '@${p.username}',
          textDirection: TextDirection.ltr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.family,
            fontFamilyFallback: AppFonts.fallback,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: c.onHeroMuted,
          ),
        ),
        if (p.isTeacher) ...[
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            _GlassChip(icon: Icons.verified_rounded, label: t('معلم', 'Teacher')),
            if (spec != null) _GlassChip(icon: Icons.category_rounded, label: spec),
          ]),
        ],
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: stats[i]),
            ],
          ]),
        ],
      ]),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.heroGlassBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: c.onHero),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w700, c: c.onHero)),
        ),
      ]),
    );
  }
}

class _CourseGrid extends StatelessWidget {
  const _CourseGrid({required this.courses, required this.onOpen});

  final List<CourseModel> courses;
  final void Function(CourseModel course) onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final cols = w >= 640 ? 3 : 2;
        const gap = 12.0;
        final cellW = math.max(1.0, (w - gap * (cols - 1)) / cols);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: courses.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: CourseCard.cellHeight(context, cellW),
          ),
          itemBuilder: (_, i) => CourseCard(
            course: courses[i],
            isTeacher: false,
            fullScreen: true,
            pageName: 'public_profile',
            onTap: onOpen,
          ),
        );
      });
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            child: AppShimmer(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const AppSkeletonBox(height: 230, radius: 24),
                const SizedBox(height: 16),
                const AppSkeletonBox(height: 90, radius: 18),
                const SizedBox(height: 20),
                Row(children: const [
                  Expanded(child: AppSkeletonBox(height: 200, radius: 18)),
                  SizedBox(width: 12),
                  Expanded(child: AppSkeletonBox(height: 200, radius: 18)),
                ]),
              ]),
            ),
          ),
        ),
      );
}
