// lib/features/self_learning/sl_widgets.dart — the self-learning cards over plain values (D-1601..D-1604), checked by
// test/ui/self_learning_test.dart through the layout harness:
//
//   SlProgressRing(progress:)           a ring of learned / (learned + due) with the three numbers beside it
//   SlLessonCard(item:, onGotIt:)       today's lesson: subject, title, the short body, "Got it" (one entrance)
//   SlReviewCard(item:, picked:, …)     one review question: options, instant right / wrong, the explanation, a light
//                                       celebration on a right answer, ONE action (Next / Done)
//   SlSubjectBars(progress:, subjects:) per-subject progress bars
//   SlSettingsCard(...)                 the student's on / off and subjects (nothing when the student may not toggle)
//   SlOffState()                        "Daily lessons are switched off" (the admin's switch)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart' show keptOnDeviceText;
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';

import 'sl_models.dart';
import 'sl_motion.dart';

final _arabic = RegExp(r'[؀-ۿ]');

/// The text's own direction: Arabic content (the subjects are Arabic) reads right to left in either app language.
TextDirection slTextDirection(String s) => _arabic.hasMatch(s) ? TextDirection.rtl : TextDirection.ltr;

String slDaysText(int n) => countText(n,
    ar1: 'يوم واحد', ar2: 'يومان', arFew: '$n أيام', arMany: '$n يوماً', en1: '1 day', en: '$n days', ar0: '0 يوم', en0: '0 days');

/// The marks of a single-pick question: [picked] and, once [checked], right / wrong / missed against [answer].
List<LearnMark> slPickMarks(int count, int? picked, int answer, bool checked) => [
      for (var i = 0; i < count; i++)
        !checked
            ? (i == picked ? LearnMark.selected : LearnMark.idle)
            : i == answer
                ? (picked == answer ? LearnMark.correct : LearnMark.missed)
                : (i == picked ? LearnMark.wrong : LearnMark.idle),
    ];

// ── the ring ─────────────────────────────────────────────────────────────────

/// Learned / due / streak: a ring filled to learned / (learned + due), the learned count inside, the three numbers
/// beside it. [compact] = a smaller ring for a tab's section.
class SlProgressRing extends StatelessWidget {
  const SlProgressRing({super.key, required this.progress, this.compact = false});

  final SlProgress progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = progress;
    final all = p.learned + p.due;
    final v = all <= 0 ? 0.0 : p.learned / all;
    final size = compact ? AppDashSize.disc : AppDashSize.ring;
    final gold = appToneColor(context, AppTone.gold);
    final label = t('تعلّمت ${p.learned}، للمراجعة ${p.due}، أيام متتالية ${p.streakDays}',
        'Learned ${p.learned}, due ${p.due}, streak ${p.streakDays} days');
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Row(children: [
        SizedBox.square(
          dimension: size,
          child: AppFill(
            value: v,
            builder: (context, f) => CustomPaint(
              painter: _RingPainter(value: f, track: c.inputBg, fill: c.success, width: compact ? AppSpace.xxs + 2 : AppSpace.xs),
              child: Center(
                child: Text('${p.learned}',
                    style: AppType.figure(context).copyWith(color: c.textDark, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _StatLine(icon: Icons.check_circle_rounded, color: c.success, text: t('تعلّمت ${p.learned}', 'Learned ${p.learned}')),
            _StatLine(icon: Icons.replay_rounded, color: c.primary, text: t('للمراجعة ${p.due}', 'Due ${p.due}')),
            _StatLine(
                icon: Icons.local_fire_department_rounded,
                color: gold,
                text: t('متتالية: ${slDaysText(p.streakDays)}', 'Streak: ${slDaysText(p.streakDays)}')),
          ]),
        ),
      ]),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs / 2),
        child: Row(children: [
          Icon(icon, size: AppIconSize.sm, color: appInk(context, color)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: context.colors.textDark))),
        ]),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.track, required this.fill, required this.width});

  final double value;
  final Color track;
  final Color fill;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (math.min(size.width, size.height) - width) / 2;
    final center = size.center(Offset.zero);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = track;
    canvas.drawCircle(center, r, base);
    final v = value.clamp(0.0, 1.0);
    if (v <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = fill;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2, 2 * math.pi * v, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.track != track || old.fill != fill || old.width != width;
}

// ── the lesson ───────────────────────────────────────────────────────────────

/// Today's lesson. [short] cuts the body to a few lines (a tab's section). One entrance per route (AppReveal).
class SlLessonCard extends StatelessWidget {
  const SlLessonCard({super.key, required this.item, this.onGotIt, this.busy = false, this.short = false, this.index = 0});

  final SlItem item;
  final VoidCallback? onGotIt;
  final bool busy;
  final bool short;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = item.plainBody;
    return AppReveal(
      group: 'sl.lesson',
      index: index,
      child: AppCard(
        key: ValueKey('sl.lesson.${item.id}'),
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.auto_stories_rounded, size: AppIconSize.md, color: c.primary),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(t('درس اليوم', "Today's lesson"),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
            ),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: AppStatusBadge(label: slSubjectLabel(item.subject), tone: AppTone.brand, dense: true)),
          ]),
          AppSpace.gapSm,
          Text(item.title, textDirection: slTextDirection(item.title), style: AppType.section(context)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              body,
              textDirection: slTextDirection(body),
              maxLines: short ? 4 : null,
              overflow: short ? TextOverflow.ellipsis : null,
              style: AppType.body(context).copyWith(color: c.textDark, height: 1.7),
            ),
          ],
          if (onGotIt != null) ...[
            AppSpace.gapMd,
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AppButton.tonal(
                key: ValueKey('sl.gotit.${item.id}'),
                label: t('فهمت', 'Got it'),
                icon: Icons.check_rounded,
                busy: busy,
                onPressed: busy ? null : onGotIt,
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── the review question ──────────────────────────────────────────────────────

class SlReviewCard extends StatelessWidget {
  const SlReviewCard({
    super.key,
    required this.item,
    this.picked,
    this.right,
    this.explanation = '',
    this.queued = false,
    this.error,
    this.onPick,
    this.onNext,
    this.nextLabel,
    this.index = 0,
    this.total = 1,
  });

  final SlItem item;
  final int? picked;

  /// null = not answered yet.
  final bool? right;
  final String explanation;
  final bool queued;
  final String? error;
  final ValueChanged<int>? onPick;
  final VoidCallback? onNext;
  final String? nextLabel;

  /// 0-based, of [total] (a progress strip shows when there are several).
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = item.question;
    if (q == null) return const SizedBox.shrink();
    final checked = right != null;
    return AppCard(
      key: ValueKey('sl.review.${item.id}'),
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (total > 1) ...[
          LearnProgressHeader(
            current: index + 1,
            total: total,
            label: t('مراجعة ${index + 1} من $total', 'Review ${index + 1} of $total'),
          ),
          AppSpace.gapSm,
        ] else ...[
          Row(children: [
            Icon(Icons.replay_rounded, size: AppIconSize.md, color: c.primary),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(t('سؤال مراجعة', 'Review question'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
            ),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: AppStatusBadge(label: slSubjectLabel(item.subject), tone: AppTone.brand, dense: true)),
          ]),
          AppSpace.gapSm,
        ],
        Directionality(
          textDirection: slTextDirection(q.prompt),
          child: LearnPrompt(text: q.prompt.isEmpty ? item.title : q.prompt, icon: Icons.help_outline_rounded),
        ),
        AppSpace.gapSm,
        LearnOptionList(
          options: q.options,
          marks: slPickMarks(q.options.length, picked, q.answer, checked),
          onSelect: checked || onPick == null ? null : onPick,
        ),
        if (checked) ...[
          AppSpace.gapMd,
          SlFeedbackIn(
            key: ValueKey('sl.feedback.${item.id}'),
            child: Stack(clipBehavior: Clip.none, children: [
              LearnFeedback(
                correct: right!,
                explanation: explanation,
                actionLabel: nextLabel ?? t('التالي', 'Next'),
                onAction: onNext,
              ),
              if (right!) const Positioned.fill(child: SlCelebration()),
            ]),
          ),
          if (queued) ...[
            const SizedBox(height: AppSpace.xs),
            Row(children: [
              Icon(Icons.cloud_off_rounded, size: AppIconSize.sm, color: c.textMedium),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(keptOnDeviceText(), style: AppType.meta(context))),
            ]),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpace.xs),
            Semantics(liveRegion: true, child: Text(error!, style: AppType.meta(context).copyWith(color: appInk(context, c.danger)))),
          ],
        ],
      ]),
    );
  }
}

// ── per subject ──────────────────────────────────────────────────────────────

class SlSubjectBars extends StatelessWidget {
  const SlSubjectBars({super.key, required this.progress, required this.subjects});

  final SlProgress progress;
  final List<String> subjects;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[];
    for (final s in subjects) {
      final p = progress.perSubject[s] ?? const SlSubjectProgress();
      if (rows.isNotEmpty) rows.add(AppSpace.gapSm);
      final pct = (p.fraction * 100).round();
      rows.add(Semantics(
        container: true,
        label: t('${slSubjectLabel(s)}: تعلّمت ${p.learned}، للمراجعة ${p.due}', '${slSubjectLabel(s)}: learned ${p.learned}, due ${p.due}'),
        value: '$pct%',
        excludeSemantics: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(slSubjectLabel(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
            const SizedBox(width: AppSpace.xs),
            Text(t('${p.learned} · للمراجعة ${p.due}', '${p.learned} · ${p.due} due'),
                style: AppType.meta(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: AppSpace.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: AppSpace.xs,
              child: AppFill(
                value: p.fraction,
                builder: (context, f) => Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: c.inputBg),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: f.clamp(0.0, 1.0),
                    child: ColoredBox(color: c.success),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

// ── the student's control ────────────────────────────────────────────────────

class SlSettingsCard extends StatelessWidget {
  const SlSettingsCard({
    super.key,
    required this.enabled,
    required this.subjects,
    required this.canToggle,
    this.busy = false,
    this.onEnabled,
    this.onSubjects,
  });

  final bool enabled;
  final List<String> subjects;
  final bool canToggle;
  final bool busy;
  final ValueChanged<bool>? onEnabled;
  final ValueChanged<List<String>>? onSubjects;

  @override
  Widget build(BuildContext context) {
    if (!canToggle) return const SizedBox.shrink();
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSwitchTile(
          key: const ValueKey('sl.enabled'),
          title: t('الدروس اليومية', 'Daily lessons'),
          subtitle: t('درس قصير أو سؤال مراجعة بضع مرات في اليوم', 'A short lesson or a review question a few times a day'),
          value: enabled,
          onChanged: busy || onEnabled == null ? null : onEnabled!,
        ),
        if (enabled) ...[
          AppSpace.gapSm,
          Text(t('المواد', 'Subjects'), style: AppType.label(context).copyWith(color: context.colors.textMedium)),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final s in kSlSubjects)
              AppChoiceChip(
                key: ValueKey('sl.subject.$s'),
                label: slSubjectLabel(s),
                selected: subjects.contains(s),
                onTap: () {
                  if (busy || onSubjects == null) return;
                  final next = subjects.contains(s) ? [for (final x in subjects) if (x != s) x] : [...subjects, s];
                  // at least one subject stays on (switch the lessons off to stop them all)
                  if (next.isNotEmpty) onSubjects!([for (final x in kSlSubjects) if (next.contains(x)) x]);
                },
              ),
          ]),
        ],
      ]),
    );
  }
}

/// The admin has self-learning off: a plain, calm empty state.
class SlOffState extends StatelessWidget {
  const SlOffState({super.key});

  @override
  Widget build(BuildContext context) => AppEmpty(
        key: const ValueKey('sl.off'),
        icon: Icons.notifications_paused_rounded,
        title: t('الدروس اليومية متوقفة', 'Daily lessons are switched off'),
        message: t('أوقفتها إدارة المنصة أو مدرستك. ستظهر هنا عند تشغيلها.',
            'The platform or your school has paused them. They show here when they are switched on.'),
      );
}
