// Open-answer auto-grading in the review screens (D-688): plain-value widgets (no provider, no API), pumped by the
// layout harness (test/ui/autograde_layout_test.dart). The online review card (exam_review_screen.dart), the paper
// review's short answer (paper/review/omr_review_written.dart) and the essay run's answer card
// (hub/grade/essay_run_widgets.dart) draw these over the same AutoGrade:
//
//   AutoTierLine      the tier that decided the proposal, the answer kind, "settled" or "your call"
//   AutoAnswerText    the student's answer with the sentence of every covered point highlighted (success role),
//                     a contradicted one in the danger role
//   AutoPointsList    the points covered, then the points missing (warning role) and contradicted (danger role)
//   Nb2CharsView      an NB2 character-box reading: one box per character, the doubtful ones marked with the
//                     reader's runner-up
//   ScanCropView      the part of a scanned page that holds the answer (the question's region of the page image)
//   AnswerMemoryList  a question's remembered decisions, each with Forget
//   AnswerMemorySheet the sheet over AnswerMemoryList (loads and forgets through AnswerMemoryApi)
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_autograde.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/exams/exam_taking.dart' show examCodeText;

/// The colour role of a point state: covered = success, partial = warning tint of success, missing = warning,
/// contradicted = danger.
Color autoPointColor(BuildContext context, String state) {
  final c = context.colors;
  return switch (state) {
    'matched' => c.success,
    'partial' => c.success,
    'contradicted' => c.danger,
    _ => c.warning,
  };
}

String _kindText(String? k) => switch (k) {
      'word' => t('كلمة', 'One word'),
      'short' => t('إجابة قصيرة', 'Short answer'),
      'long' => t('إجابة طويلة', 'Long answer'),
      _ => '',
    };

/// The tier that decided, the kind, and whether it is settled.
class AutoTierLine extends StatelessWidget {
  const AutoTierLine({super.key, required this.auto});
  final AutoGrade auto;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = auto;
    final hint = autoTierHint(a);
    final kind = _kindText(a.kind);
    return Column(key: const ValueKey('auto.tier'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AppBadgePill('${t('حسمها', 'Decided by')}: ${autoTierText(a.tier)}', color: a.decided ? c.success : c.warning,
            icon: a.tier == 'memory' ? Icons.history_rounded : Icons.auto_awesome_rounded),
        if (kind.isNotEmpty) AppBadgePill(kind, color: c.textMedium, icon: Icons.short_text_rounded),
      ]),
      if (hint.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(hint, style: AppType.meta(context)),
      ],
    ]);
  }
}

/// The student's answer with the covered points' sentences highlighted.
class AutoAnswerText extends StatelessWidget {
  const AutoAnswerText({super.key, required this.text, required this.auto, this.lang});
  final String text;
  final AutoGrade auto;
  final String? lang;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (text.trim().isEmpty) return Text(t('— لا توجد إجابة —', '— no answer —'), style: appText(13.5, c: c.textLight));
    final (dir, align) = lang == 'ar'
        ? (TextDirection.rtl, TextAlign.start)
        : lang == 'en'
            ? (TextDirection.ltr, TextAlign.start)
            : autoDirOf(context, text);
    return SelectableText.rich(
      TextSpan(style: appText(14, c: c.textDark, h: 1.6), children: [
        for (final (s, state) in autoPointRuns(text, auto.points))
          TextSpan(
            text: s,
            style: state == null
                ? null
                : TextStyle(
                    backgroundColor: autoPointColor(context, state).withValues(alpha: state == 'partial' || state == 'unsure' ? .10 : .20),
                    fontWeight: FontWeight.w700,
                    decoration: state == 'contradicted' ? TextDecoration.lineThrough : null,
                    decorationColor: c.danger,
                  ),
          ),
      ]),
      key: const ValueKey('auto.answer'),
      textDirection: dir,
      textAlign: align,
    );
  }
}

/// The points covered, then the points missing / contradicted; keywords for a word / short answer.
class AutoPointsList extends StatelessWidget {
  const AutoPointsList({super.key, required this.auto});
  final AutoGrade auto;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = auto;
    Widget row(AutoPoint p) {
      final color = autoPointColor(context, p.state);
      final icon = switch (p.state) {
        'matched' => Icons.check_circle_rounded,
        'partial' => Icons.adjust_rounded,
        'contradicted' => Icons.cancel_rounded,
        _ => Icons.radio_button_unchecked_rounded,
      };
      return Padding(
        key: ValueKey('auto.point.${p.idx}.${p.state}'),
        padding: const EdgeInsets.only(top: AppSpace.xxs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: AppIconSize.sm, color: color),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AutoDirText(p.text, style: AppType.body(context)),
              if (p.state != 'matched') Text(autoPointStateText(p.state), style: AppType.meta(context).copyWith(color: appInk(context, color))),
            ]),
          ),
        ]),
      );
    }

    final covered = a.coveredPoints, missing = a.missingPoints, contra = a.contradictedPoints;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (covered.isNotEmpty) ...[
        Text(t('النقاط المذكورة', 'Points covered'), style: AppType.label(context)),
        for (final p in covered) row(p),
      ],
      if (missing.isNotEmpty || contra.isNotEmpty) ...[
        if (covered.isNotEmpty) const SizedBox(height: AppSpace.xs),
        Text(t('النقاط الناقصة', 'Points missing'), key: const ValueKey('auto.missing'), style: AppType.label(context)),
        for (final p in contra) row(p),
        for (final p in missing) row(p),
      ],
      if (a.points.isEmpty && (a.found.isNotEmpty || a.missing.isNotEmpty)) ...[
        Text(t('الكلمات المفتاحية', 'Keywords'), style: AppType.label(context)),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
          for (final k in a.found) AppBadgePill(k, color: c.success, icon: Icons.check_rounded),
          for (final k in a.missing) AppBadgePill(k, color: c.warning, icon: Icons.remove_rounded),
        ]),
      ],
    ]);
  }
}

/// An NB2 character-box reading: one box per character, a doubtful box marked (warning) with its runner-up.
class Nb2CharsView extends StatelessWidget {
  const Nb2CharsView({super.key, required this.reading});
  final Nb2Chars reading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = reading;
    final low = r.lowCount;
    return Column(key: const ValueKey('auto.nb2'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('ما قرأناه', 'What we read'), style: AppType.label(context)),
      const SizedBox(height: AppSpace.xxs),
      if (r.chars.isEmpty)
        Text(r.read, style: AppType.bodyStrong(context))
      else
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
          for (final (i, ch) in r.chars.indexed)
            Semantics(
              label: ch.low ? t('حرف غير مؤكد ${ch.ch}', 'Uncertain character ${ch.ch}') : ch.ch,
              excludeSemantics: true,
              child: Container(
                key: ValueKey('auto.nb2.$i${ch.low ? '.low' : ''}'),
                constraints: const BoxConstraints(minWidth: 30, minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                decoration: BoxDecoration(
                  color: ch.low ? c.warning.withValues(alpha: .14) : c.inputBg,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: ch.low ? c.warning : c.divider, width: ch.low ? 2 : 1),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(ch.ch.isEmpty ? '·' : ch.ch, style: appText(16, w: FontWeight.w800, c: c.textDark)),
                  if (ch.low && (ch.alt ?? '').isNotEmpty) Text('${t('أو', 'or')} ${ch.alt}', style: appText(10.5, c: appInk(context, c.warning))),
                ]),
              ),
            ),
        ]),
      if (low > 0 || r.nearMissFrom != null) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(
          [
            if (low > 0) t('المربعات الملوّنة غير مؤكدة: قارنها بالصورة', 'The marked boxes are uncertain: compare them with the image'),
            if (r.nearMissFrom != null) t('قُرئت «${r.nearMissFrom}» وصُحّحت لأقرب إجابة', 'Read as "${r.nearMissFrom}", corrected to the nearest answer'),
          ].join(' · '),
          style: AppType.meta(context),
        ),
      ],
    ]);
  }
}

/// The part of a scanned page that holds one answer: [box] = normalised x, y, w, h (the whole page when null or
/// out of range), drawn at most [maxHeight] tall. [bytes] null = still loading ([loading]) or not available.
class ScanCropView extends StatelessWidget {
  const ScanCropView({super.key, this.bytes, this.box, this.loading = false, this.maxHeight = 220, this.onTap});
  final Uint8List? bytes;
  final List<double>? box;
  final bool loading;
  final double maxHeight;
  final VoidCallback? onTap;

  /// The Align factors and alignment that show [box] of a child (null: the whole child).
  static (double, double, Alignment)? cropOf(List<double>? box) {
    if (box == null || box.length < 4) return null;
    final x = box[0].clamp(0.0, 1.0), y = box[1].clamp(0.0, 1.0);
    final w = box[2].clamp(0.0, 1.0 - x), h = box[3].clamp(0.0, 1.0 - y);
    if (w <= 0.01 || h <= 0.01 || (w >= .999 && h >= .999)) return null;
    double a(double p, double s) => s >= .999 ? 0 : (2 * p / (1 - s)) - 1;
    return (w, h, Alignment(a(x, w), a(y, h)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = bytes;
    Widget child;
    if (b != null) {
      final img = Image.memory(b, semanticLabel: t('صورة الإجابة من الورقة', 'The answer on the paper'));
      final cut = cropOf(box);
      child = FittedBox(
        fit: BoxFit.contain,
        child: cut == null ? img : ClipRect(child: Align(alignment: cut.$3, widthFactor: cut.$1, heightFactor: cut.$2, child: img)),
      );
    } else if (loading) {
      child = AppSkeletonBox(height: maxHeight / 2);
    } else {
      child = Padding(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.image_not_supported_rounded, color: c.textLight, size: AppIconSize.sm),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(t('صورة الورقة غير متاحة', 'The paper image is not available'), style: AppType.meta(context))),
        ]),
      );
    }
    return ClipRRect(
      key: const ValueKey('auto.crop'),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Material(
        color: c.inputBg,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight, minWidth: double.infinity), child: Center(child: child)),
        ),
      ),
    );
  }
}

/// The whole auto-grade block of one answer: tier, points / keywords. The highlighted answer is drawn by the caller
/// (it knows where the answer text sits).
class AutoGradePanel extends StatelessWidget {
  const AutoGradePanel({super.key, required this.auto});
  final AutoGrade auto;

  @override
  Widget build(BuildContext context) {
    final hasList = auto.points.isNotEmpty || auto.found.isNotEmpty || auto.missing.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AutoTierLine(auto: auto),
      if (hasList) ...[
        const SizedBox(height: AppSpace.xs),
        AutoPointsList(auto: auto),
      ],
    ]);
  }
}

// ── answer memory ────────────────────────────────────────────────────────────────────────────────────────────────

/// A question's remembered decisions, each with Forget (plain values).
class AnswerMemoryList extends StatelessWidget {
  const AnswerMemoryList({super.key, required this.items, this.busy = const {}, this.onForget});
  final List<AnswerMemoryItem> items;
  final Set<int> busy;
  final ValueChanged<AnswerMemoryItem>? onForget;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (items.isEmpty) {
      return AppEmpty(icon: Icons.history_toggle_off_rounded, title: t('لا قرارات محفوظة لهذا السؤال بعد', 'No remembered decisions for this question yet'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final m in items)
        Container(
          key: ValueKey('memory.${m.id}'),
          margin: const EdgeInsets.only(bottom: AppSpace.xs),
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: c.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AutoDirText(m.text.isEmpty ? '—' : m.text, style: AppType.bodyStrong(context)),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppBadgePill(answerMemoryVerdictText(m.verdict),
                  color: switch (m.verdict) { 'right' => c.success, 'wrong' => c.danger, _ => c.warning }),
              AppBadgePill(m.decisions == 1 ? t('قرار واحد', '1 decision') : t('${m.decisions} قرارات', '${m.decisions} decisions'), color: c.textMedium),
              if (m.conflict) AppBadgePill(t('قرارات متعارضة', 'Conflicting decisions'), color: c.danger, icon: Icons.warning_amber_rounded),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.xs, children: [
              Text(answerMemorySourceText(m.source), style: AppType.meta(context)),
              if (onForget != null)
                AppButton.ghost(
                  key: ValueKey('memory.forget.${m.id}'),
                  label: t('انسَ هذا القرار', 'Forget'),
                  icon: Icons.delete_outline_rounded,
                  busy: busy.contains(m.id),
                  onPressed: busy.contains(m.id) ? null : () => onForget!(m),
                ),
            ]),
          ]),
        ),
    ]);
  }
}

/// "Answer memory" of one question, or of one picked among [questions] (id → prompt): what the grader reuses from
/// your earlier marks. Forgetting one asks first.
class AnswerMemorySheet extends StatefulWidget {
  const AnswerMemorySheet({super.key, required this.questions, this.initial, this.api});
  final Map<int, String> questions;
  final int? initial;
  final AnswerMemoryApi? api;

  @override
  State<AnswerMemorySheet> createState() => _AnswerMemorySheetState();
}

class _AnswerMemorySheetState extends State<AnswerMemorySheet> {
  late final AnswerMemoryApi _api = widget.api ?? AnswerMemoryApi();
  late int? _q = widget.initial ?? (widget.questions.isEmpty ? null : widget.questions.keys.first);
  List<AnswerMemoryItem>? _items;
  String? _error;
  final _busy = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = _q;
    if (q == null) return;
    setState(() {
      _items = null;
      _error = null;
    });
    final EngineResult r = await _api.list(q);
    if (!mounted || q != _q) return;
    setState(() {
      if (r.ok) {
        _items = answerMemoryOf(r.map);
      } else {
        _error = examCodeText(r.code ?? r.message);
      }
    });
  }

  Future<void> _forget(AnswerMemoryItem m) async {
    final q = _q;
    if (q == null) return;
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('انسَه', 'Forget'),
        message: t('نسيان هذا القرار؟ لن يُستخدم لتصحيح الإجابات المماثلة بعد الآن. الدرجات الموضوعة لا تتغير.',
            'Forget this decision? It will no longer mark answers like it. Marks already given do not change.'));
    if (!ok || !mounted) return;
    setState(() => _busy.add(m.id));
    final r = await _api.forget(q, m.id);
    if (!mounted) return;
    setState(() => _busy.remove(m.id));
    if (!r.ok && r.code != 'memory_not_found') {
      showAppNotice(examCodeText(r.code ?? r.message), error: true);
      return;
    }
    setState(() => _items = [for (final x in _items ?? const <AnswerMemoryItem>[]) if (x.id != m.id) x]);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('ذاكرة الإجابات', 'Answer memory'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xxs),
        Text(t('إجابات صحّحتها من قبل: يعيد المصحح الآلي استخدام قرارك عندما تتكرر الإجابة نفسها.',
                'Answers you marked before: the grader reuses your decision when the same answer comes again.'),
            style: AppType.meta(context)),
        const SizedBox(height: AppSpace.sm),
        if (widget.questions.length > 1) ...[
          AppDropdown<int>(
            value: _q,
            isExpanded: true,
            decoration: InputDecoration(labelText: t('السؤال', 'Question')),
            items: [
              for (final e in widget.questions.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value.isEmpty ? '#${e.key}' : e.value, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              setState(() => _q = v);
              _load();
            },
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        if (_error != null)
          AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: context.colors.danger)
        else if (items == null)
          const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero)
        else
          AnswerMemoryList(items: items, busy: _busy, onForget: _forget),
      ]),
    );
  }
}
