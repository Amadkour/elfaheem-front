// lib/features/profile/public_profile/public_profile_view.dart
//
// The ONE profile page's content (D-074, D-850 – D-855), plain values only so the layout harness can pump it. The
// owner, a signed-in visitor and a guest with the shared link all see this same body; only the slots differ.
//
//   PublicProfileView(result:, onOpenCourse:, onOpenCourseId:, onRetry:, onBack:, ownerPanel:, joinCard:)
//     result == null                 loading skeleton
//     found + teacher                hero (photo · name · @username · chips · students / rating / courses), the
//                                    owner panel, "About", "In numbers" (the server's aggregates, D-852), "Growth"
//                                    (AppBarChart, 12 months), "Most joined" courses, the public course cards, the
//                                    guest's join card
//     found + student                the same hero (streak / completed / certificates when shown), the owner panel,
//                                    "About", "Learning" (opt-in, D-851), the finished courses, the join card
//     found + any other kind         the same hero, nothing else (a minimal card)
//     notFound / disabled / failed   a calm empty state (retry only on failed)
// A young teacher reads "New" instead of a misleading 0 (`is_new`); a figure the server could not say (completion
// rate, reply time) or that is still 0 is left out rather than shown as 0.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppReveal, AppTilt;
import 'package:flutter_education_app/features/profile/profile_hero.dart' show ProfileAvatar;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/home/student/models.dart' show CourseModel;
import 'package:flutter_education_app/features/courses/course_row.dart' show CourseCard;
import 'package:flutter_education_app/features/profile/public_profile/public_profile.dart';

class PublicProfileView extends StatelessWidget {
  const PublicProfileView({
    super.key,
    required this.result,
    required this.onOpenCourse,
    this.onOpenCourseId,
    this.onRetry,
    this.onBack,
    this.ownerPanel,
    this.joinCard,
  });

  /// null while loading.
  final PublicProfileResult? result;
  final void Function(CourseModel course) onOpenCourse;

  /// Opens a course named only by its id (a teacher's most joined, a student's finished course); null = not tappable.
  final void Function(int courseId)? onOpenCourseId;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  /// The owner's who-sees-what and actions, right under the hero (null for visitors).
  final Widget? ownerPanel;

  /// The guest's soft "join NextBrain" card at the end of the page (null when signed in).
  final Widget? joinCard;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) return const _ProfileSkeleton();
    final p = r.profile;
    if (r.status == PublicProfileStatus.found && p != null) {
      return _ProfileBody(
        profile: p,
        onOpenCourse: onOpenCourse,
        onOpenCourseId: onOpenCourseId,
        ownerPanel: ownerPanel,
        joinCard: joinCard,
      );
    }
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
  const _ProfileBody({
    required this.profile,
    required this.onOpenCourse,
    this.onOpenCourseId,
    this.ownerPanel,
    this.joinCard,
  });

  final PublicProfile profile;
  final void Function(CourseModel course) onOpenCourse;
  final void Function(int courseId)? onOpenCourseId;
  final Widget? ownerPanel, joinCard;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    final side = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    final st = p.stats;
    final growth = p.growth.any((g) => g.students > 0) ? p.growth : const <PublicGrowthPoint>[];
    final learning = p.learning;
    final sections = <Widget>[
      _ProfileHero(profile: p),
      ?ownerPanel,
      if (p.bio != null && (p.isTeacher || p.isStudent))
        AppSection(
          title: t('نبذة', 'About'),
          child: AppCard(child: Text(p.bio!, style: AppType.body(context).copyWith(height: 1.6))),
        ),
      if (p.isTeacher && st != null) _NumbersSection(stats: st),
      if (p.isTeacher && growth.isNotEmpty) _GrowthSection(growth: growth),
      if (p.isTeacher && st != null && st.topCourses.any((x) => x.students > 0))
        AppSection(
          title: t('الأكثر انضماماً', 'Most joined'),
          subtitle: t('كورسات يختارها الطلاب أكثر من غيرها', 'The courses students pick most'),
          child: _CourseRanking(courses: st.topCourses, onOpen: onOpenCourseId),
        ),
      if (p.isTeacher && p.sections['courses'] != false)
        AppSection(
          title: t('الكورسات', 'Courses'),
          subtitle: p.coursesCount == 0
              ? null
              : countText(p.coursesCount,
                  ar1: 'كورس منشور واحد',
                  ar2: 'كورسان منشوران',
                  arFew: '${p.coursesCount} كورسات منشورة',
                  arMany: '${p.coursesCount} كورساً منشوراً',
                  en1: '1 published course',
                  en: '${p.coursesCount} published courses'),
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
      if (p.isStudent && learning != null) _LearningSection(learning: learning),
      if (p.isStudent && p.completedCourses.isNotEmpty)
        AppSection(
          title: t('كورسات أكملها', 'Courses completed'),
          child: _CourseRanking(courses: p.completedCourses, onOpen: onOpenCourseId, done: true),
        ),
      if (joinCard != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xl), child: joinCard),
    ];
    // ONE entrance (system.md §6): the hero block leads, the sections follow it once
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, AppSpace.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < sections.length; i++)
              AppReveal(index: math.min(i, 6), group: 'public_profile', child: sections[i]),
          ]),
        ),
      ),
    );
  }
}

/// "New" — what a young account shows instead of a misleading 0.
String _newLabel() => t('جديد', 'New');

/// A reply time in words: under an hour, about N hours, about N days.
String profileReplyTime(double hours) {
  if (hours < 1) return t('أقل من ساعة', '< 1 hour');
  if (hours < 24) {
    final h = hours.round();
    return countText(h, ar1: 'ساعة', ar2: 'ساعتان', arFew: '$h ساعات', arMany: '$h ساعة', en1: '1 hour', en: '$h hours');
  }
  final d = (hours / 24).round();
  return countText(d, ar1: 'يوم', ar2: 'يومان', arFew: '$d أيام', arMany: '$d يوماً', en1: '1 day', en: '$d days');
}

/// Hours of content: "< 1", "12", "1.2K".
String _hoursValue(double h) => h <= 0 ? '0' : (h < 1 ? '< 1' : appCompactNumber(h.round()));

/// The hero block (D-622, D-713): the person's one tinted surface — the identity tone (a soft primary gradient) for
/// everyone — with the editorial name, the @username, the identity chips on paper and up to three figures, which
/// count up once (the reader hears the final value). A masthead row from [_wideFrom], a centred stack below.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.profile});

  final PublicProfile profile;

  static const double _wideFrom = 640;

  /// How much of the block's ink the hairlines between the figures carry.
  static const double _ruleInk = 0.16;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AppTilt(
        radius: AppRadius.block,
        maxTilt: 2.5,
        glare: true,
        child: AppBlock(
          tone: AppBlockTone.identity,
          hero: true,
          child: LayoutBuilder(builder: (context, box) => _body(context, box.maxWidth >= _wideFrom)),
        ),
      ),
    );
  }

  List<Widget> _figures() {
    final p = profile;
    final key = 'pp.${p.id}';
    if (p.isTeacher) {
      final st = p.stats;
      final students = st?.studentsTaught ?? p.courses.fold<int>(0, (s, x) => s + x.studentsCount);
      final isNew = st?.isNew ?? false;
      return [
        if (students > 0)
          _Figure(value: appCompactNumber(students), label: t('طالب درّسهم', 'Students taught'), memoryKey: '$key.students')
        else if (isNew)
          _Figure(value: _newLabel(), label: t('على NextBrain', 'On NextBrain'), memoryKey: '$key.new'),
        if (st?.rating != null)
          _Figure(value: st!.rating!.toStringAsFixed(1), label: t('التقييم', 'Rating'), memoryKey: '$key.rating', star: true)
        else if (p.experienceYears > 0)
          _Figure(value: '${p.experienceYears}', label: t('سنوات خبرة', 'Years'), memoryKey: '$key.years'),
        _Figure(value: '${st?.courses ?? p.coursesCount}', label: t('كورسات', 'Courses'), memoryKey: '$key.courses'),
      ];
    }
    final l = p.learning;
    if (p.isStudent && l != null) {
      return [
        _Figure(value: '${l.streakDays}', label: t('أيام متتالية', 'Day streak'), memoryKey: '$key.streak'),
        _Figure(value: '${l.coursesCompleted}', label: t('كورسات مكتملة', 'Completed'), memoryKey: '$key.done'),
        _Figure(value: '${l.certificates}', label: t('شهادات', 'Certificates'), memoryKey: '$key.certs'),
      ];
    }
    return const [];
  }

  Widget _body(BuildContext context, bool wide) {
    final b = AppBlock.colorsOf(context);
    final p = profile;
    final spec = p.isTeacher ? p.specialization(AppConfig.lang) : null;
    final since = p.stats?.since ?? p.learning?.since;
    final stats = _figures();
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
    final chipList = <Widget>[
      if (p.isTeacher) _PaperChip(icon: Icons.verified_rounded, label: t('معلم', 'Teacher')),
      if (p.isStudent) _PaperChip(icon: Icons.auto_stories_rounded, label: t('متعلّم', 'Learner')),
      if (spec != null) _PaperChip(icon: Icons.category_rounded, label: spec),
      if (since != null) _PaperChip(icon: Icons.event_available_rounded, label: t('على NextBrain منذ $since', 'On NextBrain since $since')),
    ];
    final chips = chipList.isEmpty
        ? null
        : Wrap(
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: chipList,
          );
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

/// One of the figures on the hero block: the number in the figure face (counting up once), its label under it.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, required this.memoryKey, this.star = false});

  final String value, label, memoryKey;

  /// A rating: a small gold star before the number.
  final bool star;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    final c = context.colors;
    final number = AppCountUp(value, memoryKey: memoryKey, style: AppType.figureLarge(context).copyWith(color: b.ink));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: star
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.star_rounded, size: AppIconSize.md, color: b.accentInk(c.accent2)),
                const SizedBox(width: AppSpace.xxs),
                number,
              ])
            : number,
      ),
      const SizedBox(height: AppSpace.xxs),
      Text(label,
          maxLines: 2,
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

/// One figure tile of "In numbers" / "Learning".
@immutable
class _Stat {
  const _Stat(this.icon, this.value, this.label, this.color, {this.note});
  final IconData icon;
  final String value, label;
  final Color color;
  final String? note;
}

/// A responsive grid of figure tiles: 2 columns on phones, 3 from 520 px, 4 from 820 px.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final List<_Stat> stats;

  /// Three tiles a row from this width, four from [_fourFrom].
  static const double _threeFrom = 520, _fourFrom = 820;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final cols = w >= _fourFrom ? 4 : (w >= _threeFrom ? 3 : 2);
        const gap = AppSpace.sm;
        final cell = math.max(1.0, (w - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final s in stats) SizedBox(width: cell, child: _StatTile(stat: s)),
        ]);
      });
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stat;
    final tint = Color.alphaBlend(s.color.withValues(alpha: c.isDark ? 0.22 : 0.12), c.cardBg);
    return Semantics(
      label: '${s.value} ${s.label}${s.note == null ? '' : ', ${s.note}'}',
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: AppIconSize.xl,
            height: AppIconSize.xl,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(s.icon, size: AppIconSize.sm, color: c.blockAccentInk(s.color, tint)),
          ),
          const SizedBox(height: AppSpace.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(s.value, maxLines: 1, style: AppType.figure(context).copyWith(color: c.textDark)),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(s.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
          if (s.note != null)
            Text(s.note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
        ]),
      ),
    );
  }
}

/// "In numbers": a teacher's aggregates (D-852). Zeros and unknowns are left out; an account with nothing to show
/// yet gets one calm "New on NextBrain" card instead of a row of zeros.
class _NumbersSection extends StatelessWidget {
  const _NumbersSection({required this.stats});

  final PublicTeacherStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stats;
    final ratings = s.ratingsCount;
    final tiles = <_Stat>[
      if (s.studentsTaught > 0)
        _Stat(Icons.groups_rounded, appCompactNumber(s.studentsTaught), t('طالب درّسهم', 'Students taught'), c.primary),
      if (s.activeLearners > 0)
        _Stat(Icons.bolt_rounded, appCompactNumber(s.activeLearners), t('متعلّم نشط هذا الشهر', 'Active this month'), c.accent),
      if (s.rating != null)
        _Stat(Icons.star_rounded, s.rating!.toStringAsFixed(1), t('متوسط التقييم', 'Average rating'), c.accent2,
            note: countText(ratings,
                ar1: 'تقييم واحد', ar2: 'تقييمان', arFew: '$ratings تقييمات', arMany: '$ratings تقييماً',
                en1: '1 rating', en: '$ratings ratings')),
      if (s.completionRate != null)
        _Stat(Icons.flag_rounded, '${s.completionRate}%', t('نسبة إكمال الكورسات', 'Completion rate'), c.accent3),
      if (s.lessons > 0) _Stat(Icons.play_lesson_rounded, appCompactNumber(s.lessons), t('درس', 'Lessons'), c.primary),
      if (s.hours > 0) _Stat(Icons.schedule_rounded, _hoursValue(s.hours), t('ساعة محتوى', 'Hours of content'), c.accent3),
      if (s.liveSessions > 0)
        _Stat(Icons.videocam_rounded, appCompactNumber(s.liveSessions), t('جلسة مباشرة', 'Live sessions held'), c.accent),
      if (s.certificates > 0)
        _Stat(Icons.workspace_premium_rounded, appCompactNumber(s.certificates), t('شهادة صادرة', 'Certificates issued'),
            c.accent2),
      if (s.responseHours != null)
        _Stat(Icons.forum_rounded, profileReplyTime(s.responseHours!), t('متوسط وقت الرد', 'Typical reply time'), c.primary),
    ];
    final Widget body;
    if (tiles.isEmpty) {
      body = AppCard(
        child: Row(children: [
          Icon(Icons.auto_awesome_rounded, size: AppIconSize.md, color: c.accent2),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              t('معلم جديد على NextBrain — كن من أوائل طلابه.', 'New on NextBrain — be one of the first students.'),
              style: AppType.body(context),
            ),
          ),
        ]),
      );
    } else {
      body = _StatGrid(stats: tiles);
    }
    return AppSection(
      title: t('بالأرقام', 'In numbers'),
      subtitle: t('أرقام مجمّعة تُحدَّث تلقائياً', 'Aggregate figures, updated automatically'),
      child: body,
    );
  }
}

/// "Growth": new students per month (AppBarChart, D-063). Phones show the last 6 months, wider pages all 12.
class _GrowthSection extends StatelessWidget {
  const _GrowthSection({required this.growth});

  final List<PublicGrowthPoint> growth;

  /// From this card width all 12 months fit; below it the last 6.
  static const double _allMonthsFrom = 480;

  static String _month(PublicGrowthPoint g) {
    final d = g.date;
    return d == null ? g.month : AppTime.date(d, pattern: 'MMM');
  }

  @override
  Widget build(BuildContext context) {
    final total = growth.fold<int>(0, (s, g) => s + g.students);
    final title = t('طلاب جدد كل شهر', 'New students each month');
    return AppSection(
      title: t('النمو', 'Growth'),
      subtitle: countText(total,
          ar1: 'طالب جديد واحد خلال 12 شهراً',
          ar2: 'طالبان جديدان خلال 12 شهراً',
          arFew: '$total طلاب جدد خلال 12 شهراً',
          arMany: '$total طالباً جديداً خلال 12 شهراً',
          en1: '1 new student in 12 months',
          en: '$total new students in 12 months'),
      child: AppCard(
        child: LayoutBuilder(builder: (context, box) {
          final shown = box.maxWidth < _allMonthsFrom && growth.length > 6 ? growth.sublist(growth.length - 6) : growth;
          return AppBarChart(
            title: title,
            integerAxis: true,
            labels: [for (final g in shown) _month(g)],
            series: [AppChartSeries(title, [for (final g in shown) g.students.toDouble()])],
          );
        }),
      ),
    );
  }
}

/// Ranked course rows: a teacher's most joined (with a bar for its share of students) or a student's finished
/// courses (a check). Names only — never who joined.
class _CourseRanking extends StatelessWidget {
  const _CourseRanking({required this.courses, this.onOpen, this.done = false});

  final List<PublicCourseBrief> courses;
  final void Function(int courseId)? onOpen;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = courses.fold<int>(0, (m, x) => math.max(m, x.students));
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Column(children: [
        for (var i = 0; i < courses.length; i++) ...[
          if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
          _rankRow(context, i, courses[i], top),
        ],
      ]),
    );
  }

  Widget _rankRow(BuildContext context, int i, PublicCourseBrief x, int top) {
    final c = context.colors;
    final share = top <= 0 ? 0.0 : x.students / top;
    final tint = Color.alphaBlend(c.primary.withValues(alpha: c.isDark ? 0.25 : 0.10), c.cardBg);
    final lead = Container(
      width: AppIconSize.xl,
      height: AppIconSize.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
      child: done
          ? Icon(Icons.check_rounded, size: AppIconSize.sm, color: c.blockAccentInk(c.primary, tint))
          : Text('${i + 1}', style: AppType.label(context).copyWith(color: c.blockAccentInk(c.primary, tint))),
    );
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(x.name(AppConfig.lang),
          maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
      if (!done) ...[
        const SizedBox(height: AppSpace.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: share,
            minHeight: AppSpace.xs,
            backgroundColor: c.divider,
            valueColor: AlwaysStoppedAnimation(c.primary),
          ),
        ),
        const SizedBox(height: AppSpace.xxs),
        Text(
          countText(x.students,
              ar1: 'طالب واحد', ar2: 'طالبان', arFew: '${x.students} طلاب', arMany: '${appCompactNumber(x.students)} طالباً',
              en1: '1 student', en: '${appCompactNumber(x.students)} students'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta(context).copyWith(color: c.textMedium),
        ),
      ],
    ]);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Row(children: [
        lead,
        const SizedBox(width: AppSpace.sm),
        Expanded(child: body),
        if (onOpen != null) ...[
          const SizedBox(width: AppSpace.xs),
          Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
        ],
      ]),
    );
    final open = onOpen;
    if (open == null) return row;
    return Semantics(
      button: true,
      child: InkWell(onTap: () => open(x.id), child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: row,
      )),
    );
  }
}

/// "Learning": a student's opt-in summary (D-851).
class _LearningSection extends StatelessWidget {
  const _LearningSection({required this.learning});

  final PublicLearning learning;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = learning;
    final streak = l.streakDays;
    return AppSection(
      title: t('رحلة التعلّم', 'Learning'),
      child: _StatGrid(stats: [
        _Stat(Icons.local_fire_department_rounded, '$streak',
            countText(streak,
                ar0: 'لا أيام متتالية بعد', ar1: 'يوم متتالٍ', ar2: 'يومان متتاليان', arFew: 'أيام متتالية',
                arMany: 'يوماً متتالياً', en1: 'day streak', en: 'day streak'),
            c.accent2),
        _Stat(Icons.task_alt_rounded, '${l.coursesCompleted}', t('كورسات مكتملة', 'Courses completed'), c.primary),
        _Stat(Icons.menu_book_rounded, '${l.coursesInProgress}', t('قيد الدراسة', 'In progress'), c.accent3),
        _Stat(Icons.workspace_premium_rounded, '${l.certificates}', t('شهادات', 'Certificates'), c.accent),
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

/// The guest's soft call to action (D-854): who this page belongs to, "Create a free account" and "Sign in". The
/// page itself never needs an account; the buttons only open the usual sign-up / sign-in pages.
class ProfileJoinCard extends StatelessWidget {
  const ProfileJoinCard({super.key, required this.name, required this.teacher, required this.onJoin, required this.onSignIn});

  final String name;
  final bool teacher;
  final VoidCallback onJoin, onSignIn;

  @override
  Widget build(BuildContext context) {
    return AppBlock(
      tone: AppBlockTone.sage,
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            teacher ? t('تعلّم مع $name على NextBrain', 'Learn with $name on NextBrain') : t('انضم إلى $name على NextBrain', 'Join $name on NextBrain'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.section(context).copyWith(color: b.ink),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            teacher
                ? t('أنشئ حساباً مجانياً لتشترك في كورساته وتتابع جديده.', 'Create a free account to join their courses and follow what is new.')
                : t('أنشئ حساباً مجانياً وابدأ رحلتك في التعلّم.', 'Create a free account and start your own learning journey.'),
            style: AppType.body(context).copyWith(color: b.muted),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            AppButton.primary(label: t('إنشاء حساب مجاني', 'Create a free account'), icon: Icons.person_add_alt_1_rounded, onPressed: onJoin),
            AppButton.secondary(label: t('تسجيل الدخول', 'Sign in'), onPressed: onSignIn),
          ]),
        ]);
      }),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  /// The bones' heights: the hero block, the about card, a figure tile, a course card.
  static const double _hero = 230, _about = 90, _tile = 110, _course = 200;

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
                Expanded(child: AppSkeletonBox(height: _tile, radius: AppRadius.card)),
                SizedBox(width: AppSpace.sm),
                Expanded(child: AppSkeletonBox(height: _tile, radius: AppRadius.card)),
              ]),
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
