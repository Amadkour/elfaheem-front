// Grade Papers, essay path (D-662): the plain-value widgets the screens are built from (no provider, no API), so the
// layout harness pumps them at every size and language.
//
//   EssayQuestionEditor  one question: prompt, mark, model answer — or rubric criteria with their marks
//   EssayRunSummary      the run's counts (students, to check, being read, done) over one primary action
//   EssayStudentCard     a student: what is left, the total once done
//   EssayAnswerCard      one answer: the photo, what was read, the suggestion and why, one-tap Accept / Edit
//   EssayPageAssign      which question each page answers, before a paper is sent
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_autograde_widgets.dart' show AutoAnswerText, AutoPointsList, AutoTierLine;
import 'package:flutter_education_app/features/exams/hub/grade/essay_run.dart';

/// The tallest an answer's photo is drawn in its card (the full page opens on tap).
const kEssayCropMaxHeight = 280.0;

TextDirection _dirOf(String s) => s.runes.any((r) => r >= 0x0600 && r <= 0x06FF) ? TextDirection.rtl : TextDirection.ltr;

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String _numText(double? v) => v == null ? '' : essayNum(v);

/// One question of the setup. Holds its own text controllers; every change is written into [draft] and reported.
class EssayQuestionEditor extends StatefulWidget {
  const EssayQuestionEditor({super.key, required this.n, required this.draft, required this.onChanged, this.onRemove});
  final int n;
  final EssayQuestionDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  State<EssayQuestionEditor> createState() => _EssayQuestionEditorState();
}

class _EssayQuestionEditorState extends State<EssayQuestionEditor> {
  late final _prompt = TextEditingController(text: widget.draft.prompt);
  late final _points = TextEditingController(text: _numText(widget.draft.points));
  late final _model = TextEditingController(text: widget.draft.modelAnswer);
  final _crit = <(TextEditingController, TextEditingController, TextEditingController)>[];

  @override
  void initState() {
    super.initState();
    for (final c in widget.draft.criteria) {
      _crit.add(_criterionControllers(c));
    }
  }

  (TextEditingController, TextEditingController, TextEditingController) _criterionControllers(EssayCriterionDraft c) =>
      (TextEditingController(text: c.criterion), TextEditingController(text: _numText(c.points)), TextEditingController(text: c.model));

  @override
  void dispose() {
    _prompt.dispose();
    _points.dispose();
    _model.dispose();
    for (final (a, b, c) in _crit) {
      a.dispose();
      b.dispose();
      c.dispose();
    }
    super.dispose();
  }

  void _sync() {
    final d = widget.draft;
    d.prompt = _prompt.text;
    d.points = _num(_points.text);
    d.modelAnswer = _model.text;
    for (var i = 0; i < _crit.length && i < d.criteria.length; i++) {
      d.criteria[i]
        ..criterion = _crit[i].$1.text
        ..points = _num(_crit[i].$2.text)
        ..model = _crit[i].$3.text;
    }
    widget.onChanged();
  }

  void _addCriterion() {
    final c = EssayCriterionDraft();
    setState(() {
      widget.draft.criteria.add(c);
      _crit.add(_criterionControllers(c));
    });
    widget.onChanged();
  }

  void _removeCriterion(int i) {
    setState(() {
      widget.draft.criteria.removeAt(i);
      final (a, b, c) = _crit.removeAt(i);
      a.dispose();
      b.dispose();
      c.dispose();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = widget.draft;
    final total = d.rubricTotal;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t('السؤال ${widget.n}', 'Question ${widget.n}'), style: AppType.section(context))),
          if (d.usesRubric)
            AppBadgePill(t('الدرجة ${_numText(total)}', 'Mark ${total == null ? '—' : _numText(total)}'), icon: Icons.functions_rounded),
          if (widget.onRemove != null)
            IconButton(tooltip: t('حذف السؤال', 'Remove the question'), onPressed: widget.onRemove, icon: Icon(Icons.delete_outline_rounded, color: c.textLight)),
        ]),
        const SizedBox(height: AppSpace.xs),
        AppField(controller: _prompt, label: t('نص السؤال (اختياري)', 'Question text (optional)'), maxLines: 3, onChanged: (_) => _sync()),
        const SizedBox(height: AppSpace.sm),
        if (!d.usesRubric) ...[
          AppNumberField(controller: _points, label: t('الدرجة', 'Mark'), min: 0.5, max: 1000, step: 0.5, decimals: 1, onChanged: (_) => _sync()),
          const SizedBox(height: AppSpace.sm),
          AppField(controller: _model, label: t('الإجابة النموذجية', 'Model answer'), maxLines: 5, onChanged: (_) => _sync()),
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(label: t('استخدم معايير تصحيح بدلًا من ذلك', 'Use rubric criteria instead'), icon: Icons.checklist_rounded, onPressed: _addCriterion),
          ),
        ] else ...[
          AppField(controller: _model, label: t('الإجابة النموذجية (اختياري)', 'Model answer (optional)'), maxLines: 3, onChanged: (_) => _sync()),
          const SizedBox(height: AppSpace.sm),
          for (var i = 0; i < _crit.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(color: c.primaryWash, borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(t('المعيار ${i + 1}', 'Criterion ${i + 1}'), style: AppType.label(context))),
                    IconButton(tooltip: t('حذف المعيار', 'Remove the criterion'), onPressed: () => _removeCriterion(i), icon: Icon(Icons.close_rounded, color: c.textLight)),
                  ]),
                  AppField(controller: _crit[i].$1, label: t('ما يجب أن تذكره الإجابة', 'What the answer must say'), maxLines: 2, onChanged: (_) => _sync()),
                  const SizedBox(height: AppSpace.xs),
                  AppNumberField(controller: _crit[i].$2, label: t('درجة المعيار', 'Criterion mark'), min: 0.5, max: 1000, step: 0.5, decimals: 1, onChanged: (_) => _sync()),
                  const SizedBox(height: AppSpace.xs),
                  AppField(controller: _crit[i].$3, label: t('جملة نموذجية (اختياري)', 'A model sentence (optional)'), maxLines: 2, onChanged: (_) => _sync()),
                ]),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(label: t('إضافة معيار', 'Add a criterion'), icon: Icons.add_rounded, onPressed: d.criteria.length >= kEssayMaxCriteria ? null : _addCriterion),
          ),
        ],
      ]),
    );
  }
}

/// The run's counts and its main actions.
class EssayRunSummary extends StatelessWidget {
  const EssayRunSummary({super.key, required this.run, required this.onAddPaper, required this.onResults, this.busy = false});
  final EssayRun run;
  final VoidCallback onAddPaper;
  final VoidCallback? onResults;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppGrid(minTile: 150, children: [
        // D-1081: the soft-wash counts; "to check" turns gold while there is some
        AppStatCard(icon: Icons.people_alt_rounded, label: t('طلاب', 'Students'), value: '${run.students.length}', tone: AppBlockTone.sky),
        AppStatCard(icon: Icons.rate_review_rounded, label: t('للمراجعة', 'To check'), value: '${run.open}', tone: run.open > 0 ? AppBlockTone.gold : AppBlockTone.peach),
        AppStatCard(icon: Icons.hourglass_top_rounded, label: t('تُقرأ الآن', 'Being read'), value: '${run.waiting}', tone: AppBlockTone.peach),
        AppStatCard(icon: Icons.task_alt_rounded, label: t('اكتمل', 'Done'), value: '${run.done}', tone: AppBlockTone.emerald),
      ]),
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(label: t('إضافة ورقة طالب', 'Add a student\'s paper'), icon: Icons.add_a_photo_rounded, onPressed: busy ? null : onAddPaper),
      const SizedBox(height: AppSpace.xs),
      AppButton.secondary(label: t('النتائج والتصدير', 'Results and export'), icon: Icons.leaderboard_rounded, onPressed: onResults, expand: true),
    ]);
  }
}

class EssayStudentCard extends StatelessWidget {
  const EssayStudentCard({super.key, required this.student, required this.onTap});
  final EssayStudent student;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = student;
    final tone = s.open > 0 ? c.warning : (s.waiting > 0 ? c.primary : c.success);
    return AppCard(
      onTap: onTap,
      child: Row(children: [
        Icon(s.open > 0 ? Icons.rate_review_rounded : (s.waiting > 0 ? Icons.hourglass_top_rounded : Icons.task_alt_rounded), color: tone),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(essayStudentLine(s), style: AppType.meta(context).copyWith(color: c.textLight)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        const Icon(Icons.chevron_right_rounded),
      ]),
    );
  }
}

/// One answer: the photo of it, what was read, the suggestion with its evidence, and the teacher's decision.
class EssayAnswerCard extends StatelessWidget {
  const EssayAnswerCard({
    super.key,
    required this.answer,
    required this.question,
    this.crop,
    this.cropLoading = false,
    this.busy = false,
    this.onAccept,
    this.onEdit,
    this.onOpenPage,
    this.onMemory,
  });
  final EssayAnswer answer;
  final EssayQuestion? question;
  final Uint8List? crop;
  final bool cropLoading, busy;
  final VoidCallback? onAccept, onEdit, onOpenPage;

  /// The question's answer memory (D-688), offered when the tiers proposed the mark.
  final VoidCallback? onMemory;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = answer;
    final s = a.suggestion;
    final points = question?.points ?? 0;
    final read = (s?.readText.isNotEmpty ?? false) ? s!.readText : (a.text ?? '');
    final stateColor = switch (a.state) {
      EssayAnswerState.review => c.warning,
      EssayAnswerState.done => c.success,
      _ => c.textLight,
    };
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t('السؤال ${a.n}', 'Question ${a.n}'), style: AppType.section(context))),
          AppBadgePill(essayStateText(a.state), color: stateColor),
        ]),
        if ((question?.prompt ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(question!.prompt, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
        ],
        for (final q in a.quality) ...[
          const SizedBox(height: AppSpace.xs),
          AppBanner(icon: Icons.photo_camera_back_rounded, text: essayQualityText(q), color: c.warning),
        ],
        if (a.state != EssayAnswerState.missing) ...[
          const SizedBox(height: AppSpace.sm),
          _Crop(bytes: crop, loading: cropLoading, onTap: onOpenPage),
        ],
        if (read.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('ما قرأناه', 'What we read'), style: AppType.label(context)),
          const SizedBox(height: AppSpace.xxs),
          if (s?.auto != null && s!.auto!.points.isNotEmpty && !s.pending)
            AutoAnswerText(text: read, auto: s.auto!)
          else
            Text(read, textDirection: _dirOf(read), style: AppType.body(context)),
        ],
        if (s != null) ...[
          const SizedBox(height: AppSpace.sm),
          _Suggestion(s: s, points: points),
        ],
        if (a.state == EssayAnswerState.done) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('الدرجة: ${essayNum(a.finalScore)} من ${essayNum(points)}', 'Mark: ${essayNum(a.finalScore)} of ${essayNum(points)}'),
              style: AppType.bodyStrong(context).copyWith(color: c.success)),
        ],
        if (a.state == EssayAnswerState.review || a.state == EssayAnswerState.done) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (a.state == EssayAnswerState.review && s?.suggested != null && !(s?.pending ?? false))
              AppButton.primary(
                  label: t('اعتماد ${essayNum(s!.suggested)} / ${essayNum(points)}', 'Accept ${essayNum(s.suggested)} / ${essayNum(points)}'),
                  icon: Icons.check_rounded,
                  busy: busy,
                  onPressed: busy ? null : onAccept),
            if (a.state == EssayAnswerState.review)
              AppButton.secondary(label: t('تعديل الدرجة', 'Edit the mark'), icon: Icons.edit_rounded, onPressed: busy ? null : onEdit),
            if (onOpenPage != null) AppButton.ghost(label: t('الصفحة كاملة', 'Full page'), icon: Icons.open_in_full_rounded, onPressed: onOpenPage),
            if (onMemory != null)
              AppButton.ghost(key: const ValueKey('essay.memory'), label: t('ذاكرة الإجابات', 'Answer memory'), icon: Icons.history_rounded, onPressed: onMemory),
          ]),
        ],
      ]),
    );
  }
}

class _Crop extends StatelessWidget {
  const _Crop({required this.bytes, required this.loading, this.onTap});
  final Uint8List? bytes;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = bytes;
    final Widget child;
    if (b != null) {
      child = Image.memory(b, fit: BoxFit.contain, semanticLabel: t('صورة الإجابة', 'Photo of the answer'));
    } else if (loading) {
      child = const AppSkeletonBox(height: kEssayCropMaxHeight / 2);
    } else {
      child = Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.image_not_supported_rounded, color: c.textLight),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(t('الصورة غير متاحة الآن', 'The photo is not available yet'), style: AppType.meta(context).copyWith(color: c.textLight))),
        ]),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Material(
        color: c.primaryWash,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: kEssayCropMaxHeight), child: Center(child: child)),
        ),
      ),
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.s, required this.points});
  final EssaySuggestion s;
  final double points;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bandColor = switch (s.band) {
      'full' => c.success,
      'zero' || 'empty' => c.danger,
      _ => c.warning,
    };
    final auto = s.pending ? null : s.auto;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.primaryWash, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(
              s.suggested == null
                  ? t('لا توجد درجة مقترحة', 'No suggested mark')
                  : t('المقترح: ${essayNum(s.suggested)} من ${essayNum(points)}', 'Suggested: ${essayNum(s.suggested)} of ${essayNum(points)}'),
              style: AppType.bodyStrong(context)),
          AppBadgePill(essayBandText(s.band), color: bandColor),
        ]),
        if (auto != null) ...[
          const SizedBox(height: AppSpace.xs),
          AutoTierLine(auto: auto),
          if (auto.points.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            AutoPointsList(auto: auto),
          ],
        ],
        if (auto == null || auto.points.isEmpty)
        for (final p in s.rubric) ...[
          const SizedBox(height: AppSpace.xs),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(p.band == 'full' ? Icons.check_circle_rounded : (p.band == 'zero' ? Icons.cancel_rounded : Icons.adjust_rounded),
                size: AppIconSize.sm, color: p.band == 'full' ? c.success : (p.band == 'zero' ? c.danger : c.warning)),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(p.criterion, textDirection: _dirOf(p.criterion), style: AppType.body(context))),
            const SizedBox(width: AppSpace.xs),
            Text('${essayNum(p.suggested)} / ${essayNum(p.points)}', style: AppType.label(context)),
          ]),
        ],
        if (s.found.isNotEmpty || s.missing.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
            for (final k in s.found) AppBadgePill(k, color: c.success, icon: Icons.check_rounded),
            for (final k in s.missing) AppBadgePill(k, color: c.danger, icon: Icons.remove_rounded),
          ]),
        ],
        for (final r in s.reasons.where((r) => r != 'rubric')) ...[
          const SizedBox(height: AppSpace.xs),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: AppIconSize.sm, color: c.textLight),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(essayReasonText(r), style: AppType.meta(context).copyWith(color: c.textLight))),
          ]),
        ],
        if (s.decision != null && s.decidedScore != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(t('قرارك: ${essayNum(s.decidedScore)}', 'Your decision: ${essayNum(s.decidedScore)}'), style: AppType.meta(context)),
        ],
      ]),
    );
  }
}

/// Which question each page answers (one row per page, in the order they were picked).
class EssayPageAssign extends StatelessWidget {
  const EssayPageAssign({super.key, required this.names, required this.numbers, required this.questions, required this.onChanged, this.problem});
  final List<String> names;
  final List<int> numbers;
  final int questions;
  final void Function(int page, int question) onChanged;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('كل صفحة تجيب عن أي سؤال؟ صفحات السؤال نفسه تُجمع في صورة واحدة.', 'Which question does each page answer? Pages of the same answer are joined into one image.'),
          style: AppType.meta(context).copyWith(color: c.textLight)),
      const SizedBox(height: AppSpace.sm),
      for (var i = 0; i < numbers.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppDashSize.courseTile),
              child: Text(t('صفحة ${i + 1}', 'Page ${i + 1}') + (i < names.length ? ' · ${names[i]}' : ''),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
            ),
            for (var q = 1; q <= questions; q++)
              ChoiceChip(label: Text(t('س$q', 'Q$q')), selected: numbers[i] == q, onSelected: (_) => onChanged(i, q)),
          ]),
        ),
      if (problem != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.error_outline_rounded, text: problem!, color: c.danger),
      ],
    ]);
  }
}
