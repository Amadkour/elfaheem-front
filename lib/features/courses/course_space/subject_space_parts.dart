// lib/features/courses/course_space/subject_space_parts.dart
//
// The pieces of the student's subject page (SubjectProfile, S-B): the spiral book of the hero, the teacher's
// avatar, the live and next-class cards, one step of "مسارك في المادة" and the tool rows. Plain values only.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart' show CourseSpaceAction;

// ═════════════════════════════════════════════════════════════════════════════
// Sizes (the reference's book: 290 × 400 from 700 px, 100 × 138 in a phone hero, 160 × 220 opened in a sheet)
// ═════════════════════════════════════════════════════════════════════════════

const Size kSubjectBookWide = Size(290, 400);
const Size kSubjectBookPhone = Size(100, 138);
const Size kSubjectBookSheet = Size(160, 220);

/// The coil's rings, the ribbon's width, the spread's gap.
const double _kCoilRing = 10;
const double _kRibbon = 14;
const double _kAvatarRing = 3;

// ═════════════════════════════════════════════════════════════════════════════
// Plain values
// ═════════════════════════════════════════════════════════════════════════════

enum SubjectStepKind { lesson, live, exam }

enum SubjectStepState { done, live, current, todo, locked }

/// One step of the path: a درس (recorded), a حصة (live) or an اختبار.
class SubjectStep {
  const SubjectStep({
    required this.id,
    required this.number,
    required this.title,
    required this.meta,
    this.kind = SubjectStepKind.lesson,
    this.state = SubjectStepState.todo,
    this.chip,
    this.onTap,
    this.onJoin,
  });

  /// A stable key ("s12", "e4").
  final String id;
  final int number;
  final String title, meta;
  final SubjectStepKind kind;
  final SubjectStepState state;

  /// A short word at the end (a day: "الخميس").
  final String? chip;
  final VoidCallback? onTap;

  /// A live step's "ادخل الحصة" (the lessons page draws it under the row).
  final VoidCallback? onJoin;
}

/// One fact on the open book's inside page (lessons, minutes a class, hours, rating). Never a student count.
class SubjectFact {
  const SubjectFact({required this.icon, required this.value, required this.label, this.accent = AppAccent.sun});

  final IconData icon;
  final String value, label;
  final AppAccent accent;
}

/// A row of the tools card ("اسأل المساعد الذكي", "دفتر المادة" …).
class SubjectTool {
  const SubjectTool({required this.icon, required this.label, required this.onTap, this.note, this.accent, this.featureKey});

  final IconData icon;
  final String label;
  final String? note;
  final VoidCallback onTap;
  final AppAccent? accent;
  final String? featureKey;
}

String sbDigits(Object n) => appDigits('$n');

String sbFill(String key, Map<String, Object> values) {
  var s = key.tr;
  values.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// "٥ دقايق", "دقيقة", "دقيقتين".
String sbMinutes(int n) => appDigits(countText(n,
    ar1: 'دقيقة', ar2: 'دقيقتين', arFew: '{n} دقايق', arMany: '{n} دقيقة', en1: '1 minute', en: '{n} minutes'));

/// "١٠ أسئلة", "سؤال".
String sbQuestions(int n) => appDigits(countText(n,
    ar1: 'سؤال', ar2: 'سؤالين', arFew: '{n} أسئلة', arMany: '{n} سؤال', en1: '1 question', en: '{n} questions'));

/// "٢٤ درس".
String sbLessons(int n) => appDigits(countText(n,
    ar1: 'درس', ar2: 'درسين', arFew: '{n} دروس', arMany: '{n} درس', en1: '1 lesson', en: '{n} lessons'));

// ═════════════════════════════════════════════════════════════════════════════
// Avatar
// ═════════════════════════════════════════════════════════════════════════════

/// The teacher's round avatar: the photo when there is one, else the initial on the area's button gradient.
class SubjectAvatar extends StatelessWidget {
  const SubjectAvatar({super.key, required this.name, this.imageUrl, this.size = AppDashSize.ringSm, this.ring});

  final String name;
  final String? imageUrl;
  final double size;

  /// A ring around it (the live card's coral ring, the hero's glass ring).
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final initial = sbInitial(name);
    final url = imageUrl ?? '';
    Widget face = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: set.button,
        image: url.startsWith('http') ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
      ),
      child: url.startsWith('http')
          ? null
          : Text(initial, style: AppType.section(context).copyWith(color: set.btnFg, fontSize: size * .4, height: 1)),
    );
    if (ring != null) {
      face = Container(
        padding: const EdgeInsets.all(_kAvatarRing),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: AppBorder.focus), color: c.cardBg),
        child: face,
      );
    }
    return ExcludeSemantics(child: face);
  }
}

/// The first letter of a name, skipping a title ("أ. ماجد" → "م", "Mr Majed" → "M").
String sbInitial(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty && !p.endsWith('.')).toList();
  final w = parts.isEmpty ? name.trim() : parts.first;
  return w.isEmpty ? '' : w.characters.first.toUpperCase();
}

// ═════════════════════════════════════════════════════════════════════════════
// The spiral book
// ═════════════════════════════════════════════════════════════════════════════

/// The subject's book: a cover in the subject's colour with a gold ribbon and a coil on the spine (the start edge).
/// [open] shows the spread: the inside page (the facts and the schedule note) at the spine, the cover's back (the
/// progress ring and the first lessons) beside it.
class SubjectBook extends StatelessWidget {
  const SubjectBook({
    super.key,
    required this.title,
    required this.subject,
    this.grade,
    this.teacher,
    this.facts = const [],
    this.note,
    this.progress,
    this.progressLabel,
    this.toc = const [],
    this.open = false,
    this.size = kSubjectBookWide,
    this.showOpenChip = true,
  });

  final String title;

  /// The server's subject (slug or name): the cover's colour (`subjectColors`).
  final String? subject;
  final String? grade, teacher;
  final List<SubjectFact> facts;
  final String? note;
  final double? progress;
  final String? progressLabel;
  final List<String> toc;
  final bool open;
  final Size size;
  final bool showOpenChip;

  bool get _small => size.width < kSubjectBookSheet.width;

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    final spread = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.fromSize(size: size, child: _InsidePage(facts: facts, note: note, small: _small)),
        SizedBox.fromSize(
          size: size,
          child: _CoverBack(progress: progress, label: progressLabel, toc: toc, small: _small),
        ),
      ],
    );
    final cover = SizedBox.fromSize(
      size: size,
      child: _Cover(
        title: title,
        subject: subject,
        grade: grade,
        teacher: teacher,
        small: _small,
        showOpenChip: showOpenChip,
      ),
    );
    return AnimatedSwitcher(
      duration: motion.slow,
      switchInCurve: AppEase.out,
      switchOutCurve: AppEase.out,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween<double>(begin: .94, end: 1).animate(a), child: child),
      ),
      child: KeyedSubtree(key: ValueKey(open), child: open ? spread : cover),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.title,
    required this.subject,
    required this.small,
    required this.showOpenChip,
    this.grade,
    this.teacher,
  });

  final String title;
  final String? subject, grade, teacher;
  final bool small, showOpenChip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = subjectColors(context, subject);
    final tone = s.tone;
    final light = Color.lerp(tone.color, c.onHero, .28)!;
    final dark = Color.lerp(tone.color, c.kit.deep, .22)!;
    final fg = s.fg;
    final pad = small ? AppSpace.xs : AppSpace.lg;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // the pages under the cover
        PositionedDirectional(
          start: AppSpace.xxs,
          top: AppSpace.xxs,
          end: -AppSpace.xxs,
          bottom: -AppSpace.xxs,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: const BorderRadiusDirectional.horizontal(
                start: Radius.circular(AppSpace.xxs),
                end: Radius.circular(AppRadius.tile),
              ),
              boxShadow: AppShadow.card(context),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [light, tone.color, dark],
                stops: const [0, .55, 1],
              ),
              borderRadius: const BorderRadiusDirectional.horizontal(
                start: Radius.circular(AppSpace.xxs),
                end: Radius.circular(AppRadius.tile),
              ),
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(pad + AppSpace.xs, pad, pad, pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text('sb_subj_kicker'.tr,
                      style: (small ? AppType.overline(context) : AppType.label(context))
                          .copyWith(color: c.kit.warmOnDark, fontWeight: FontWeight.w600)),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: (small ? AppType.label(context) : AppType.headline(context))
                        .copyWith(color: fg, fontWeight: FontWeight.w600),
                  ),
                  if (!small && grade != null && grade!.isNotEmpty)
                    Text(grade!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppType.meta(context).copyWith(color: fg.withValues(alpha: .85))),
                  if (!small) ...[
                    const SizedBox(height: AppSpace.md),
                    Divider(height: AppBorder.hairline, color: fg.withValues(alpha: .3)),
                    const SizedBox(height: AppSpace.sm),
                    Row(
                      children: [
                        Expanded(
                          child: Text(teacher ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: AppType.label(context).copyWith(color: fg, fontWeight: FontWeight.w600)),
                        ),
                        if (showOpenChip)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                            decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('sb_subj_open'.tr,
                                  style: AppType.overline(context).copyWith(color: tone.ink, fontWeight: FontWeight.w600)),
                              Icon(Icons.chevron_right_rounded, size: AppIconSize.xs, color: tone.ink),
                            ]),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // the ribbon
        PositionedDirectional(
          start: small ? AppSpace.md : AppSpace.xl,
          top: 0,
          child: Container(
            width: small ? _kRibbon / 2 : _kRibbon,
            height: small ? AppSpace.lg : AppSpace.xxl,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.kit.warmOnDark, c.kit.warm]),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppSpace.xxs)),
            ),
          ),
        ),
        // the coil on the spine
        PositionedDirectional(
          start: -_kCoilRing / 2,
          top: AppSpace.xs,
          bottom: AppSpace.xs,
          child: _Coil(small: small),
        ),
      ],
    );
  }
}

class _Coil extends StatelessWidget {
  const _Coil({required this.small});

  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ring = small ? _kCoilRing * .6 : _kCoilRing;
    return LayoutBuilder(builder: (context, box) {
      final n = (box.maxHeight / (ring * 2)).floor().clamp(3, 20);
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < n; i++)
            Container(
              width: ring * 1.6,
              height: ring * .8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: c.kit.line, width: AppBorder.strong),
                color: c.cardBg.withValues(alpha: .6),
              ),
            ),
        ],
      );
    });
  }
}

/// The ruled inside page: the facts (2 × 2) and the schedule note.
class _InsidePage extends StatelessWidget {
  const _InsidePage({required this.facts, required this.note, required this.small});

  final List<SubjectFact> facts;
  final String? note;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pad = small ? AppSpace.xs : AppSpace.lg;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: c.kit.warmTone.tint,
        borderRadius: const BorderRadiusDirectional.horizontal(
          start: Radius.circular(AppSpace.xxs),
          end: Radius.circular(AppRadius.tile),
        ),
        boxShadow: AppShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: small ? AppSpace.xxs : AppSpace.xs,
              crossAxisSpacing: small ? AppSpace.xxs : AppSpace.xs,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: small ? .95 : 1,
              children: [
                for (final (i, f) in facts.take(4).indexed)
                  AppPop(delay: Duration(milliseconds: 100 * i), child: _FactTile(fact: f, small: small)),
              ],
            ),
          ),
          if (note != null && note!.isNotEmpty) ...[
            SizedBox(height: small ? AppSpace.xxs : AppSpace.xs),
            Text(note!, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.fact, required this.small});

  final SubjectFact fact;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final tone = context.colors.kit.accent(fact.accent);
    return Container(
      padding: EdgeInsets.all(small ? AppSpace.xxs : AppSpace.sm),
      decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
      // a fixed-shape tile: large text scales the content down instead of spilling out
      child: LayoutBuilder(
        builder: (context, box) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: box.maxWidth, child: _content(context, tone)),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, KitTone tone) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(fact.icon, size: small ? AppIconSize.xs : AppIconSize.sm, color: tone.ink),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(fact.value,
                style: (small ? AppType.figure(context) : AppType.figureLarge(context)).copyWith(color: tone.ink)),
          ),
          Text(fact.label, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
        ],
      );
}

/// The cover's back: the progress ring and the first lessons.
class _CoverBack extends StatelessWidget {
  const _CoverBack({required this.progress, required this.label, required this.toc, required this.small});

  final double? progress;
  final String? label;
  final List<String> toc;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final pad = small ? AppSpace.xs : AppSpace.lg;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: set.tint,
        borderRadius: const BorderRadiusDirectional.horizontal(
          start: Radius.circular(AppRadius.tile),
          end: Radius.circular(AppSpace.xxs),
        ),
        boxShadow: AppShadow.card(context),
      ),
      // a fixed-shape page: large text scales the content down instead of spilling out
      child: LayoutBuilder(
        builder: (context, box) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(
            width: box.maxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (progress != null)
                  Row(children: [
                    AppProgressRing(value: progress!, size: small ? AppDashSize.ringSm : AppDashSize.disc),
                    const SizedBox(width: AppSpace.xs),
                    if (label != null)
                      Expanded(
                        child: Text(label!, maxLines: 3, overflow: TextOverflow.ellipsis,
                            style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
                      ),
                  ]),
                SizedBox(height: small ? AppSpace.xs : AppSpace.md),
                for (final (i, t) in toc.take(small ? 2 : 4).indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${sbDigits(i + 1)}. ', style: AppType.label(context).copyWith(color: set.ink, fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Text(t, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The glass pill under a wide book: a hand and "اضغط على الكتاب".
class SubjectBookHint extends StatelessWidget {
  const SubjectBookHint({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppPop(
      delay: const Duration(milliseconds: 600),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: c.heroGlass,
          border: Border.all(color: c.heroGlassBorder),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.touch_app_outlined, size: AppIconSize.sm, color: c.onHero),
          const SizedBox(width: AppSpace.xxs),
          Text('sb_subj_tap_book'.tr, style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Hero pills
// ═════════════════════════════════════════════════════════════════════════════

/// A pill on the hero: glass with on-hero ink, or [tone] for the "مشترك" badge.
class SubjectHeroPill extends StatelessWidget {
  const SubjectHeroPill({super.key, required this.label, this.icon, this.tone, this.warm = false});

  final String label;
  final IconData? icon;
  final KitTone? tone;

  /// The mode pill ("مجموعة، عن بعد"): the warm tint.
  final bool warm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = tone ?? (warm ? c.kit.warmTone : null);
    final fg = t?.ink ?? c.onHero;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: t?.tint ?? c.heroGlass,
        border: Border.all(color: t == null ? c.heroGlassBorder : t.color.withValues(alpha: .6), width: AppBorder.hairline),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: fg), const SizedBox(width: AppSpace.xxs)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(color: fg, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Cards
// ═════════════════════════════════════════════════════════════════════════════

/// "مباشر الحين": the class is on. The one forward button of the page.
class SubjectLiveCard extends StatelessWidget {
  const SubjectLiveCard({
    super.key,
    required this.title,
    required this.teacher,
    required this.onJoin,
    this.teacherImageUrl,
    this.startedAgo,
  });

  final String title, teacher;
  final String? teacherImageUrl;

  /// "بدأت قبل ٥ دقايق" (already formatted).
  final String? startedAgo;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      variant: AppCardVariant.tint,
      tone: c.kit.live,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AppLiveTag(label: 'sb_subj_live_now'.tr),
            if (startedAgo != null) Text(startedAgo!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
          const SizedBox(height: AppSpace.md),
          Row(children: [
            SubjectAvatar(name: teacher, imageUrl: teacherImageUrl, size: AppDashSize.disc, ring: c.kit.live.color),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                const SizedBox(height: AppSpace.xxs),
                Text(sbFill('sb_subj_explaining', {'teacher': teacher}), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppType.meta(context)),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.md),
          AppBreathe(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: AppButton.hot(
              label: 'sb_subj_join'.tr,
              trailingIcon: Icons.arrow_forward_rounded,
              size: AppButtonSize.lg,
              expand: true,
              onPressed: onJoin,
            ),
          ),
        ],
      ),
    );
  }
}

/// "حصتك الجاية": the date, the countdown, and a quiet join that opens ten minutes before.
class SubjectNextCard extends StatelessWidget {
  const SubjectNextCard({super.key, required this.when, this.title, this.until, this.onJoin, this.note});

  /// "الثلاثاء ١ ديسمبر، ٧:٣٠ إلى ٨:٢٠ م" (already formatted by AppTime).
  final String when;
  final String? title;
  final DateTime? until;

  /// Null until the room opens.
  final VoidCallback? onJoin;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final live = c.kit.live;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: AppSpace.xs,
              height: AppSpace.xs,
              decoration: BoxDecoration(color: live.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpace.xs),
            Text('sb_subj_next'.tr, style: AppType.label(context).copyWith(color: live.ink, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: AppSpace.xs),
          if (title != null && title!.isNotEmpty) Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          Text(when, style: AppType.section(context)),
          if (until != null && until!.isAfter(DateTime.now().toUtc())) ...[
            const SizedBox(height: AppSpace.sm),
            AppCountdown(until: until!),
          ],
          const SizedBox(height: AppSpace.md),
          SizedBox(
            width: double.infinity,
            child: AppButton.secondary(label: 'sb_subj_join'.tr, onPressed: onJoin, expand: true),
          ),
          const SizedBox(height: AppSpace.xs),
          Center(child: Text(note ?? 'sb_subj_opens_before'.tr, textAlign: TextAlign.center, style: AppType.meta(context))),
        ],
      ),
    );
  }
}

/// One step of the path: the number circle, the title and its meta, and the chip at the end.
class SubjectStepRow extends StatelessWidget {
  const SubjectStepRow({super.key, required this.step, this.showJoin = false});

  final SubjectStep step;

  /// Draw a live step's "ادخل الحصة" under it (the lessons page).
  final bool showJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final s = step.state;
    final tone = switch (s) {
      SubjectStepState.live => c.kit.live,
      SubjectStepState.done => c.kit.ok,
      _ => step.kind == SubjectStepKind.exam ? c.kit.accent(AppAccent.grape) : set.tone,
    };
    final hot = s == SubjectStepState.live || s == SubjectStepState.current;
    final num = Container(
      width: AppDashSize.ringSm,
      height: AppDashSize.ringSm,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hot ? null : tone.tint,
        gradient: s == SubjectStepState.live
            ? LinearGradient(colors: [c.kit.liveFill, c.kit.live.color])
            : s == SubjectStepState.current
            ? set.button
            : null,
      ),
      child: Text(sbDigits(step.number),
          style: AppType.label(context).copyWith(
            color: s == SubjectStepState.live ? c.onHero : (s == SubjectStepState.current ? set.btnFg : tone.ink),
            fontWeight: FontWeight.w600,
          )),
    );
    final Widget? chip = switch (s) {
      SubjectStepState.done => AppStatusBadge(label: 'sb_subj_done'.tr, tone: AppTone.success, icon: Icons.check_rounded),
      SubjectStepState.live => AppStatusBadge(label: 'sb_subj_live'.tr, tone: AppTone.danger, dot: true),
      SubjectStepState.current => _GoChip(label: (step.kind == SubjectStepKind.lesson && step.number > 1)
          ? 'sb_subj_continue'.tr
          : 'sb_subj_start_here'.tr),
      _ => step.chip == null ? null : AppStatusBadge(label: step.chip!, tone: AppTone.warning),
    };
    final tile = AppTile(
      leading: s == SubjectStepState.locked ? null : num,
      icon: s == SubjectStepState.locked ? Icons.lock_outline_rounded : null,
      tone: tone,
      title: step.title,
      subtitle: step.meta,
      trailing: chip,
      selected: hot,
      locked: s == SubjectStepState.locked,
      onTap: step.onTap,
    );
    if (!(showJoin && s == SubjectStepState.live && step.onJoin != null)) return tile;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: c.kit.live.color.withValues(alpha: .5), width: AppBorder.strong),
        gradient: LinearGradient(colors: [c.cardBg, c.kit.live.tint]),
      ),
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        tile,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          child: AppBreathe(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: AppButton.hot(
              label: 'sb_subj_join'.tr,
              trailingIcon: Icons.arrow_forward_rounded,
              expand: true,
              onPressed: step.onJoin,
            ),
          ),
        ),
      ]),
    );
  }
}

class _GoChip extends StatelessWidget {
  const _GoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final set = AppAreaScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      decoration: BoxDecoration(gradient: set.button, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(label, style: AppType.label(context).copyWith(color: set.btnFg, fontWeight: FontWeight.w600)),
    );
  }
}

/// The teacher card: avatar, name, years, the short bio, and "راسل المعلم".
class SubjectTeacherCard extends StatelessWidget {
  const SubjectTeacherCard({super.key, required this.name, this.imageUrl, this.years, this.bio, this.onChat, this.onOpen});

  final String name;
  final String? imageUrl;
  final int? years;
  final String? bio;
  final VoidCallback? onChat;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            SubjectAvatar(name: name, imageUrl: imageUrl, size: AppDashSize.avatarSm),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
                if (years != null && years! > 0)
                  Text(appDigits(countText(years!, ar1: 'سنة خبرة', ar2: 'سنتين خبرة', arFew: '{n} سنوات خبرة',
                      arMany: '{n} سنة خبرة', en1: '1 year of experience', en: '{n} years of experience')),
                      style: AppType.meta(context)),
              ]),
            ),
          ]),
          if (bio != null && bio!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(bio!.trim(), maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
          ],
          if (onChat != null) ...[
            const SizedBox(height: AppSpace.md),
            AppButton.secondary(label: 'sb_subj_message_teacher'.tr, onPressed: onChat, expand: true),
          ],
        ],
      ),
    );
  }
}

/// The tools card: one tile per tool.
class SubjectToolsCard extends StatelessWidget {
  const SubjectToolsCard({super.key, required this.tools});

  final List<SubjectTool> tools;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final t in tools)
        if (t.featureKey == null || !AppConfig.disableList.contains(t.featureKey)) t,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, t) in shown.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpace.xs),
            AppTile(
              dense: true,
              icon: t.icon,
              tone: t.accent == null ? null : c.kit.accent(t.accent!),
              title: t.label,
              trailing: t.note == null
                  ? Icon(Icons.chevron_right_rounded, color: c.textLight)
                  : Text(t.note!, style: AppType.meta(context)),
              onTap: t.onTap,
            ),
          ],
        ],
      ),
    );
  }
}

/// "المزيد": every entry of the course the design does not draw (exams list, announcements, progress, the archive,
/// the path, about, support …), each behind its own kill switch.
class SubjectMoreCard extends StatelessWidget {
  const SubjectMoreCard({super.key, required this.items});

  final List<CourseSpaceAction> items;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final a in items)
        if (a.featureKey == null || !AppConfig.disableList.contains(a.featureKey)) a,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return AppCard(
      title: 'sb_subj_more'.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, a) in shown.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpace.xs),
            AppTile(
              dense: true,
              icon: a.icon,
              title: a.label,
              subtitle: a.caption,
              trailing: a.badge == null
                  ? Icon(Icons.chevron_right_rounded, color: c.textLight)
                  : AppCountBadge(count: int.tryParse(a.badge!) ?? 0),
              onTap: a.onTap,
            ),
          ],
        ],
      ),
    );
  }
}
