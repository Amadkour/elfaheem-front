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
import '../../../design/app_motion_kit.dart' show AppCountUp, AppReveal, AppTilt;
import '../profile/profile_hero.dart' show ProfileAvatar;
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
    final c = context.colors;
    final p = profile;
    final side = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    // ONE entrance (system.md §6): the hero block leads, the about card and the courses follow it once
    Widget enter(int i, Widget w) => AppReveal(index: i, group: 'public_profile', child: w);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, AppSpace.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            enter(0, _ProfileHero(profile: p)),
            if (p.isTeacher && p.bio != null)
              enter(
                1,
                AppSection(
                  title: t('نبذة', 'About'),
                  child: AppCard(
                    child: Text(p.bio!, style: AppType.body(context).copyWith(height: 1.6)),
                  ),
                ),
              ),
            if (p.isTeacher)
              enter(
                2,
                AppSection(
                  title: t('الكورسات', 'Courses'),
                  subtitle: p.coursesCount == 0
                      ? null
                      : t('${p.coursesCount} كورس منشور', '${p.coursesCount} published course${p.coursesCount == 1 ? '' : 's'}'),
                  child: p.courses.isEmpty
                      ? AppCard(
                          child: Row(children: [
                            Icon(Icons.school_rounded, size: AppIconSize.md, color: c.textLight),
                            const SizedBox(width: AppSpace.sm),
                            Expanded(
                              child: Text(t('لا توجد كورسات عامة بعد', 'No public courses yet'), style: AppType.body(context)),
                            ),
                          ]),
                        )
                      : _CourseGrid(courses: p.courses, onOpen: onOpenCourse),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The hero block (D-622): the person's one tinted surface — sky for a teacher (instructors wear sky), peach for
/// anyone else — with the editorial name, the @username, the identity chips on paper and the teacher's figures,
/// which count up once (the reader hears the final value). A masthead row from [_wideFrom], a centred stack below.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.profile});

  final PublicProfile profile;

  static const double _wideFrom = 640;

  /// How much of the block's ink the hairlines between the figures carry.
  static const double _ruleInk = 0.16;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return RepaintBoundary(
      child: AppTilt(
        radius: AppRadius.block,
        maxTilt: 2.5,
        glare: true,
        child: AppBlock(
          tone: p.isTeacher ? AppBlockTone.sky : AppBlockTone.peach,
          hero: true,
          child: LayoutBuilder(builder: (context, box) => _body(context, box.maxWidth >= _wideFrom)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, bool wide) {
    final b = AppBlock.colorsOf(context);
    final p = profile;
    final spec = p.specialization(AppConfig.lang);
    final students = p.courses.fold<int>(0, (s, x) => s + x.studentsCount);
    final stats = <Widget>[
      if (p.isTeacher) _Figure(value: '${p.coursesCount}', label: t('كورسات', 'Courses'), memoryKey: 'pp.${p.id}.courses'),
      if (p.isTeacher && p.experienceYears > 0)
        _Figure(value: '${p.experienceYears}', label: t('سنوات خبرة', 'Years'), memoryKey: 'pp.${p.id}.years'),
      if (p.isTeacher && students > 0)
        _Figure(value: appCompactNumber(students), label: t('طلاب', 'Students'), memoryKey: 'pp.${p.id}.students'),
    ];
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final name = Text(
      p.name,
      textAlign: wide ? TextAlign.start : TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: (wide ? AppType.display(context) : AppType.headline(context)).copyWith(color: b.ink),
    );
    // a username is always left to right, also in Arabic
    final handle = Text(
      '@${p.username}',
      textDirection: TextDirection.ltr,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppType.label(context).copyWith(color: b.muted),
    );
    final chips = p.isTeacher
        ? Wrap(
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              _PaperChip(icon: Icons.verified_rounded, label: t('معلم', 'Teacher')),
              if (spec != null) _PaperChip(icon: Icons.category_rounded, label: spec),
            ],
          )
        : null;
    final who = Column(crossAxisAlignment: align, mainAxisSize: MainAxisSize.min, children: [
      Semantics(header: true, child: name),
      const SizedBox(height: AppSpace.xxs),
      handle,
      if (chips != null) ...[const SizedBox(height: AppSpace.sm), chips],
    ]);
    final face = ProfileAvatar(name: p.name, imageUrl: p.imageUrl ?? '', heroTag: 'public-profile-${p.id}');
    // the rules between the figures: a quiet share of the block's ink, never a hard line
    final rule = Color.lerp(b.surface, b.ink, _ruleInk)!;
    final figures = stats.isEmpty
        ? null
        : Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: AppSpace.lg),
            Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: rule),
            const SizedBox(height: AppSpace.md),
            IntrinsicHeight(
              child: Row(children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) VerticalDivider(width: AppSpace.lg, thickness: AppBorder.hairline, color: rule),
                  Expanded(child: stats[i]),
                ],
              ]),
            ),
          ]);
    if (wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [face, const SizedBox(width: AppSpace.lg), Expanded(child: who)]),
        ?figures,
      ]);
    }
    return Column(children: [
      face,
      const SizedBox(height: AppSpace.md),
      who,
      ?figures,
    ]);
  }
}

/// One of the teacher's figures on the hero block: the number in the figure face (counting up once), its label
/// under it.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, required this.memoryKey});

  final String value, label, memoryKey;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: AppCountUp(value, memoryKey: memoryKey, style: AppType.figureLarge(context).copyWith(color: b.ink)),
      ),
      const SizedBox(height: AppSpace.xxs),
      Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppType.meta(context).copyWith(color: b.muted)),
    ]);
  }
}

/// An identity chip on the block: paper with a warm hairline, the label flexes instead of clipping.
class _PaperChip extends StatelessWidget {
  const _PaperChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: AppIconSize.xl),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.sm, color: c.textMedium),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark)),
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
        const gap = AppSpace.sm;
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
          // the teacher's showcase: each card leans a little under the pointer, presses in on touch (D-620)
          itemBuilder: (_, i) => AppTilt.subtle(
            radius: AppRadius.card,
            child: CourseCard(
              course: courses[i],
              isTeacher: false,
              fullScreen: true,
              pageName: 'public_profile',
              onTap: onOpen,
            ),
          ),
        );
      });
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  /// The bones' heights: the hero block, the about card, a course card.
  static const double _hero = 230, _about = 90, _course = 200;

  @override
  Widget build(BuildContext context) {
    final side = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, AppSpace.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
          child: AppShimmer(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const AppSkeletonBox(height: _hero, radius: AppRadius.block),
              const SizedBox(height: AppSpace.xl),
              const AppSkeletonBox(height: _about, radius: AppRadius.card),
              const SizedBox(height: AppSpace.xl),
              Row(children: const [
                Expanded(child: AppSkeletonBox(height: _course, radius: AppRadius.card)),
                SizedBox(width: AppSpace.sm),
                Expanded(child: AppSkeletonBox(height: _course, radius: AppRadius.card)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
