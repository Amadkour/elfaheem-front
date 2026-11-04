// Teacher review of Exam Engine answers (Phase 6, brief §7.4): lowest confidence first, the proposal with its
// per-criterion justification and the evidence highlighted in the student's own words, one-action accept or edit,
// bulk approval of high-confidence proposals, the grading policy. Scanned answers open the page side by side.
// Students are named (the exam's audience, `GET …/omr/students`, then the course roster for anyone not listed), never
// "#10"; answers read from a paper exam's scans (bubble marks, handwriting) lead to the OMR review page, where each
// one is shown next to its crop.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/page_return.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'exam_review.dart';
import 'exam_grade_log_screen.dart' show ExamGradeLogScreen;
import 'exam_authoring.dart' show ExamAuthoringApi, ExamView, examStatusLabel;
import 'exam_authoring_screen.dart' show ExamEditorScreen, QuestionBankScreen;
import 'exam_insights_screen.dart' show ExamAnalyticsScreen, ExamAppealsScreen;
import 'exam_scan_review.dart';
import 'offline/offline_exam_teacher.dart';
import 'exam_taking.dart' show examCodeText;
import 'exam_quick_screen.dart' show openQuickExam;
import 'exam_results_screen.dart' show ExamResultsScreen;
import 'paper/omr_counts.dart' show omrAttemptsText;
import 'paper/review/omr_review.dart' show OmrAudience, OmrReviewApi;
import 'paper/scan/omr_audience_picker.dart' show kOmrAudiencePage;
import 'paper/scan/omr_routes.dart' show OmrRoutes, openOmrReview;

String _pts(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(v * 2 == (v * 2).roundToDouble() ? 1 : 2);

/// Confidence as a coloured pill.
class ConfidencePill extends StatelessWidget {
  const ConfidencePill({super.key, required this.confidence, required this.threshold, this.abstain = false});
  final double? confidence;
  final double threshold;
  final bool abstain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final band = confidenceBand(confidence, threshold: threshold, abstain: abstain);
    final color = switch (band) { 'high' => c.success, 'medium' => c.warning, 'low' => c.danger, _ => c.textLight };
    final label = confidence == null ? t('بلا اقتراح', 'No proposal') : t('ثقة ${(confidence! * 100).round()}%', 'Confidence ${(confidence! * 100).round()}%');
    return AppBadgePill(abstain ? t('$label · غير متأكد', '$label · unsure') : label, color: color, icon: Icons.insights_rounded);
  }
}

/// The student's answer with the grader's evidence highlighted.
class EvidenceText extends StatelessWidget {
  const EvidenceText({super.key, required this.text, required this.spans});
  final String text;
  final List<EvidenceSpan> spans;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (text.trim().isEmpty) return Text(t('— لا توجد إجابة —', '— no answer —'), style: appText(13.5, c: c.textLight));
    // the student's own words in their own direction: an English answer in the Arabic page ends with its full stop on
    // the right side ("darkness.", not ". darkness")
    final (dir, align) = autoDirOf(context, text);
    return SelectableText.rich(
        TextSpan(style: appText(14, c: c.textDark, h: 1.5), children: [
          for (final (s, hi) in highlightRuns(text, spans))
            TextSpan(text: s, style: hi ? TextStyle(backgroundColor: c.primary.withValues(alpha: .16), fontWeight: FontWeight.w700) : null),
        ]),
        textDirection: dir,
        textAlign: align);
  }
}

/// "تم اعتماد 3 اقتراحات" / "Approved 3 proposals" (Arabic 1 / 2 / 3–10 / 11+ forms).
String approvedProposalsText(int n) => countText(n,
    ar0: 'لم يُعتمد أي اقتراح', ar1: 'تم اعتماد اقتراح واحد', ar2: 'تم اعتماد اقتراحين', arFew: 'تم اعتماد {n} اقتراحات', arMany: 'تم اعتماد {n} اقتراحًا',
    en0: 'No proposal was approved', en1: 'Approved 1 proposal', en: 'Approved {n} proposals');

/// The bulk-approval banner: how many high-confidence proposals can be approved at once.
String approvableProposalsText(int n) => countText(n,
    ar1: 'اقتراح واحد بثقة عالية يمكن اعتماده الآن',
    ar2: 'اقتراحان بثقة عالية يمكن اعتمادهما دفعة واحدة',
    arFew: '{n} اقتراحات بثقة عالية يمكن اعتمادها دفعة واحدة',
    arMany: '{n} اقتراحًا بثقة عالية يمكن اعتمادها دفعة واحدة',
    en1: '1 high-confidence proposal can be approved now',
    en: '{n} high-confidence proposals can be approved at once');

/// Who an answer belongs to, in words: the student's name, the pseudonym under anonymous marking, else "Student #n".
String reviewStudentText(ReviewItem item, Map<int, String> names) {
  final id = item.studentId;
  if (id == null) return item.studentLabel;
  final n = names[id]?.trim() ?? '';
  return n.isNotEmpty ? n : t('طالب #$id', 'Student #$id');
}

/// Plain-values card of one answer to review (under the layout harness).
class ReviewAnswerCard extends StatelessWidget {
  const ReviewAnswerCard({super.key, required this.item, required this.threshold, this.studentName, this.onAccept, this.onEdit, this.onScan, this.onSheet,
      this.busy = false});
  final ReviewItem item;
  final double threshold;

  /// The student in words ([reviewStudentText]); the item's own label when null.
  final String? studentName;
  final VoidCallback? onAccept, onEdit, onScan;

  /// An answer read from a paper exam's scan: its review next to the crop (the OMR review page).
  final VoidCallback? onSheet;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spans = [for (final cr in item.criteria) if (cr.evidence != null && (cr.fraction ?? 0) >= .3) cr.evidence!];
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppBadgePill(studentName ?? item.studentLabel, icon: Icons.person_outline_rounded, color: c.textMedium),
          AppBadgePill(reviewStateText(item.reviewState), color: item.isOpen ? c.warning : c.success),
          // "No proposal" only when there is none: a suggestion without a confidence figure shows no pill at all
          if (item.confidence != null || !item.hasProposal) ConfidencePill(confidence: item.confidence, threshold: threshold, abstain: item.abstain),
          if (item.fromScan || item.fromPaperReader) AppBadgePill(t('ورقي ممسوح', 'Scanned paper'), icon: Icons.document_scanner_outlined, color: c.primary),
        ]),
        const SizedBox(height: 10),
        AutoDirText(item.prompt, style: appText(14.5, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.divider)),
          child: EvidenceText(text: item.answerText, spans: spans),
        ),
        if (item.flags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final f in item.flags) AppBadgePill(flagText(f), color: c.danger, icon: Icons.flag_outlined)]),
        ],
        if (item.criteria.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final cr in item.criteria) _CriterionRow(cr: cr),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(
            item.proposedScore == null
                ? t('الدرجة من ${_pts(item.points)}', 'Score out of ${_pts(item.points)}')
                : t('الاقتراح ${_pts(item.proposedScore!)} من ${_pts(item.points)}', 'Proposed ${_pts(item.proposedScore!)} of ${_pts(item.points)}'),
            // the tone as readable ink (a yellow primary on a white card was about 1.6:1)
            style: appText(14, w: FontWeight.w800, c: appInk(context, c.primary)),
          ),
          if (item.finalScore != null)
            Text(t('النهائية ${_pts(item.finalScore!)}', 'Final ${_pts(item.finalScore!)}'), style: appText(13, w: FontWeight.w700, c: appInk(context, c.success))),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (item.hasProposal && item.isOpen)
            FilledButton.icon(onPressed: busy ? null : onAccept, icon: const Icon(Icons.check_rounded, size: 18), label: Text(t('قبول الاقتراح', 'Accept'))),
          OutlinedButton.icon(onPressed: busy ? null : onEdit, icon: const Icon(Icons.edit_note_rounded, size: 18), label: Text(t('تعديل الدرجة', 'Edit score'))),
          if (item.fromScan && item.scanPageId != null)
            TextButton.icon(onPressed: onScan, icon: const Icon(Icons.image_search_rounded, size: 18), label: Text(t('الورقة الأصلية', 'Original page'))),
          if (item.fromPaperReader && onSheet != null)
            TextButton.icon(
                key: ValueKey('review.sheet.${item.answerId}'),
                onPressed: onSheet,
                icon: const Icon(Icons.crop_rounded, size: 18),
                label: Text(t('راجعها على صورة الورقة', 'Review it on the paper image'))),
        ]),
      ]),
    );
  }
}

class _CriterionRow extends StatelessWidget {
  const _CriterionRow({required this.cr});
  final ReviewCriterion cr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final full = (cr.score ?? 0) >= cr.points - 1e-9;
    final none = (cr.score ?? 0) <= 1e-9;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(full ? Icons.check_circle_rounded : (none ? Icons.cancel_outlined : Icons.adjust_rounded), size: 18,
            color: full ? c.success : (none ? c.danger : c.warning)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AutoDirText(cr.criterion, style: appText(13, w: FontWeight.w700, c: c.textDark)),
            if (cr.justification.isNotEmpty) AutoDirText(cr.justification, style: appText(12.5, c: c.textMedium)),
          ]),
        ),
        const SizedBox(width: 8),
        Text('${_pts(cr.score ?? 0)}/${_pts(cr.points)}', style: appText(13, w: FontWeight.w800, c: c.textDark)),
      ]),
    );
  }
}

/// Edit a mark: one stepper per rubric criterion (half points) or a single score, and a comment.
class MarkEditor extends StatefulWidget {
  const MarkEditor({super.key, required this.item, required this.onSave});
  final ReviewItem item;
  final Future<bool> Function({double? score, Map<String, double>? criteria, String? comment}) onSave;

  @override
  State<MarkEditor> createState() => _MarkEditorState();
}

class _MarkEditorState extends State<MarkEditor> {
  late final Map<String, double> _crit = {
    for (final r in widget.item.rubric)
      r.id: widget.item.criteria.firstWhere((x) => x.id == r.id, orElse: () => ReviewCriterion(id: r.id, criterion: r.criterion, points: r.points, score: 0)).score ?? 0,
  };
  late final _score = TextEditingController(text: widget.item.proposedScore == null ? '' : _pts(widget.item.proposedScore!));
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _score.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rubric = widget.item.rubric.isNotEmpty;
    if (!rubric) {
      _error = scoreError(_score.text, widget.item.points);
      if (_error != null) return setState(() {});
    }
    setState(() => _busy = true);
    final ok = await widget.onSave(
      score: rubric ? null : double.parse(_score.text.trim().replaceAll('٫', '.').replaceAll(',', '.')),
      criteria: rubric ? Map.of(_crit) : null,
      comment: _comment.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final it = widget.item;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSectionTitle(t('تعديل الدرجة', 'Edit the mark'), subtitle: it.prompt),
        if (it.rubric.isNotEmpty) ...[
          for (final r in it.rubric)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Text(r.criterion, style: appText(13.5, c: c.textDark))),
                IconButton(onPressed: (_crit[r.id] ?? 0) <= 0 ? null : () => setState(() => _crit[r.id] = (_crit[r.id]! - .5).clamp(0, r.points)),
                    icon: const Icon(Icons.remove_circle_outline_rounded), tooltip: t('أقل', 'Less')),
                SizedBox(width: 56, child: Text('${_pts(_crit[r.id] ?? 0)}/${_pts(r.points)}', textAlign: TextAlign.center, style: appText(13.5, w: FontWeight.w800))),
                IconButton(onPressed: (_crit[r.id] ?? 0) >= r.points ? null : () => setState(() => _crit[r.id] = (_crit[r.id]! + .5).clamp(0, r.points)),
                    icon: const Icon(Icons.add_circle_outline_rounded), tooltip: t('أكثر', 'More')),
              ]),
            ),
          Text(t('المجموع ${_pts(criteriaTotal(_crit, it.scale))} من ${_pts(it.points)}', 'Total ${_pts(criteriaTotal(_crit, it.scale))} of ${_pts(it.points)}'),
              style: appText(14, w: FontWeight.w800, c: c.primary)),
        ] else
          AppField(controller: _score, label: t('الدرجة (من ${_pts(it.points)})', 'Score (of ${_pts(it.points)})'), keyboard: const TextInputType.numberWithOptions(decimal: true), ltr: true),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: appText(12.5, c: c.danger))),
        const SizedBox(height: 10),
        AppField(controller: _comment, label: t('تعليق للطالب (اختياري)', 'Comment for the student (optional)'), maxLines: 3),
        const SizedBox(height: 14),
        AppPrimaryButton(label: t('حفظ الدرجة', 'Save the mark'), onPressed: _busy ? null : _save, busy: _busy, icon: Icons.save_rounded),
      ]),
    );
  }
}

/// Grading policy of one exam.
class GradingPolicySheet extends StatefulWidget {
  const GradingPolicySheet({super.key, required this.examId, required this.policy, required this.api});
  final int examId;
  final Map<String, dynamic> policy;
  final ExamReviewApi api;

  @override
  State<GradingPolicySheet> createState() => _GradingPolicySheetState();
}

class _GradingPolicySheetState extends State<GradingPolicySheet> {
  late bool _auto = widget.policy['auto_accept'] == true;
  late bool _double = widget.policy['double_marking'] == true;
  late bool _feedback = widget.policy['show_feedback'] == true;
  late double? _threshold = (widget.policy['accept_threshold'] as num?)?.toDouble();
  late String _scanMode = '${widget.policy['scan_mode'] ?? 'handwritten'}';
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await widget.api.setPolicy(widget.examId, {
      'auto_accept': _auto, 'double_marking': _double, 'show_feedback': _feedback, 'scan_mode': _scanMode,
      'accept_threshold': ?_threshold,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return appToast(examCodeText(r.code ?? r.message), error: true);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          AppSectionTitle(t('سياسة التصحيح', 'Grading policy')),
          AppSwitchTile(title: t('قبول الاقتراحات الواثقة آلياً', 'Accept confident proposals automatically'),
              subtitle: t('لا يُطبَّق على الاختبارات المصيرية ولا مع التصحيح المزدوج', 'Never on high-stakes exams or with double marking'),
              value: _auto && !_double, onChanged: _double ? null : (v) => setState(() => _auto = v)),
          AppSwitchTile(title: t('تصحيح مزدوج', 'Double marking'), subtitle: t('مصححان مختلفان، ومشرف عند الخلاف', 'Two markers, a moderator when they disagree'),
              value: _double, onChanged: (v) => setState(() => _double = v)),
          AppSwitchTile(title: t('إظهار ملاحظات المعايير للطلاب', 'Show per-criterion feedback to students'), value: _feedback,
              onChanged: (v) => setState(() => _feedback = v)),
          const SizedBox(height: 6),
          AppDropdown<double?>(
            value: _threshold,
            items: [
              DropdownMenuItem(value: null, child: Text(t('حد القبول الافتراضي (من القياس)', 'Default threshold (from the benchmark)'))),
              for (final v in {0.9, 0.95, 0.98, ?_threshold}) DropdownMenuItem(value: v, child: Text(t('ثقة ≥ ${(v * 100).round()}%', 'Confidence ≥ ${(v * 100).round()}%'))),
            ],
            onChanged: (v) => setState(() => _threshold = v),
          ),
          const SizedBox(height: 10),
          AppDropdown<String>(
            value: _scanMode,
            items: [
              DropdownMenuItem(value: 'handwritten', child: Text(t('الأوراق مكتوبة بخط اليد', 'Answer sheets are handwritten'))),
              DropdownMenuItem(value: 'printed', child: Text(t('الأوراق مطبوعة', 'Answer sheets are printed'))),
            ],
            onChanged: (v) => setState(() => _scanMode = v ?? 'handwritten'),
          ),
          const SizedBox(height: 14),
          AppPrimaryButton(label: t('حفظ', 'Save'), onPressed: _busy ? null : _save, busy: _busy, icon: Icons.save_rounded),
        ]),
      );
}

class ExamReviewScreen extends StatefulWidget {
  const ExamReviewScreen({super.key, required this.examId, required this.examTitle, this.onOpenGradeReview});
  final int examId;
  final String examTitle;

  /// "Grade review by camera" (the marks sessions, agent FB2): the lead wires it at integration — either per screen
  /// here or once through [openGradeReviewHook]. The button shows only when one of them is set.
  final void Function(BuildContext context, int examId, String examTitle)? onOpenGradeReview;

  /// The app-wide opener (set once by the code that owns `marks/**`).
  static void Function(BuildContext context, int examId, String examTitle)? openGradeReviewHook;

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  final _api = ExamReviewApi();
  ReviewQueue? _queue;
  String _state = 'open';
  String? _error;
  final Set<int> _busy = {};

  /// student id → name (the exam's audience, then the course roster for anyone it did not list).
  final Map<int, String> _names = {};
  bool _audienceTried = false, _rosterTried = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadNames(List<ReviewItem> items) async {
    final want = {for (final it in items) ?it.studentId}..removeAll(_names.keys);
    if (want.isEmpty) return;
    if (!_audienceTried) {
      _audienceTried = true;
      final r = await OmrReviewApi().audience(widget.examId, '', limit: kOmrAudiencePage);
      if (r.ok) {
        for (final s in OmrAudience.fromJson(r.map).items) {
          if (s.name.trim().isNotEmpty) _names[s.id] = s.name;
        }
      }
      want.removeAll(_names.keys);
    }
    if (want.isNotEmpty && !_rosterTried) {
      // a class larger than one audience page: the course roster has everyone
      _rosterTried = true;
      final api = ExamAuthoringApi();
      final ex = await api.exam(widget.examId);
      final courseId = ex.ok ? ExamView.fromJson(ex.map).exam.courseId : null;
      if (courseId != null) {
        final r = await api.courseStudents(courseId);
        if (r.ok) {
          final list = r.map['value'] is List ? asMapList(r.map['value']) : asMapList(r.map['items']);
          for (final s in list) {
            final name = '${s['name'] ?? ''}'.trim();
            if (name.isNotEmpty) _names.putIfAbsent(asInt(s['id']), () => name);
          }
        }
      }
    }
    if (mounted) setState(() {});
  }

  bool get _omrReview => OmrRoutes.review != null;

  /// The OMR review page, on [it]'s own item when given (the answer the teacher clicked, not the queue's first).
  Future<void> _openSheetReview([ReviewItem? it]) async {
    await openOmrReview(context, widget.examId,
        focus: it == null ? null : (attemptId: it.attemptId, questionId: it.questionId, code: it.studentId == null ? it.studentLabel : null));
    if (mounted) _load();
  }

  Future<void> _load() async {
    final r = await _api.review(widget.examId, state: _state);
    if (!mounted) return;
    setState(() {
      _error = r.ok ? null : r.message;
      if (r.ok) _queue = ReviewQueue.fromJson(r.map);
    });
    final q = _queue;
    if (r.ok && q != null) _loadNames(q.items);
  }

  Future<void> _accept(ReviewItem it) async {
    setState(() => _busy.add(it.answerId));
    final r = await _api.mark(it.answerId, accept: true);
    if (!mounted) return;
    setState(() => _busy.remove(it.answerId));
    if (!r.ok) return appToast(examCodeText(r.code ?? r.message), error: true);
    appToast(t('تم اعتماد الدرجة', 'The mark is saved'));
    _load();
  }

  Future<void> _edit(ReviewItem it) async {
    final saved = await showAppSheet<bool>(context, (_) => MarkEditor(item: it, onSave: ({score, criteria, comment}) async {
          final r = await _api.mark(it.answerId, score: score, criteria: criteria, comment: comment);
          if (!r.ok) appToast(examCodeText(r.code ?? r.message), error: true);
          return r.ok;
        }));
    if (saved == true) _load();
  }

  Future<void> _bulk() async {
    final q = _queue;
    if (q == null) return;
    final dry = await _api.bulkApprove(widget.examId, minConfidence: q.threshold, dryRun: true);
    if (!mounted) return;
    final n = dry.ok ? asInt(dry.map['approvable']) : q.approvable(q.threshold);
    final ok = await appConfirm(context,
        message: t('اعتماد $n اقتراحاً بثقة ${(q.threshold * 100).round()}% أو أكثر؟ يُسجَّل باسمك.',
            'Approve $n proposals with confidence ${(q.threshold * 100).round()}% or more? Recorded under your name.'),
        confirmLabel: t('اعتماد', 'Approve'));
    if (!ok) return;
    final r = await _api.bulkApprove(widget.examId, minConfidence: q.threshold);
    if (!mounted) return;
    if (!r.ok) return appToast(examCodeText(r.code ?? r.message), error: true);
    appToast(approvedProposalsText(asInt(r.map['approved'])));
    _load();
  }

  Future<void> _policy() async {
    final g = await _api.grading(widget.examId);
    if (!mounted || !g.ok) return;
    final changed = await showAppSheet<bool>(context, (_) => GradingPolicySheet(examId: widget.examId, policy: asMap(g.map['policy']), api: _api));
    if (changed == true) _load();
  }

  void _scans({int? pageId}) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamScansScreen(examId: widget.examId, examTitle: widget.examTitle, openPageId: pageId)));

  @override
  Widget build(BuildContext context) {
    final q = _queue;
    final c = context.colors;
    final gradeReview = widget.onOpenGradeReview ?? ExamReviewScreen.openGradeReviewHook;
    return BasePage(
      key: const ValueKey('exam.review'),
      appBar: AppBar(title: Text(t('مراجعة التصحيح', 'Review marking')), actions: [
        IconButton(onPressed: _scans, icon: const Icon(Icons.document_scanner_outlined), tooltip: t('الأوراق الممسوحة', 'Scanned pages')),
        IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamAppealsScreen(examId: widget.examId, examTitle: widget.examTitle,
                pointsOf: {for (final it in _queue?.items ?? const <ReviewItem>[]) it.questionId: it.points}))),
            icon: const Icon(Icons.gavel_rounded), tooltip: t('التظلمات', 'Appeals')),
        IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamAnalyticsScreen(examId: widget.examId, examTitle: widget.examTitle))),
            icon: const Icon(Icons.insights_rounded), tooltip: t('التحليلات', 'Analytics')),
        IconButton(
            key: const ValueKey('review.gradeLog'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamGradeLogScreen(examId: widget.examId, examTitle: widget.examTitle))),
            icon: const Icon(Icons.history_rounded), tooltip: t('سجل الدرجات', 'Grade log')),
        IconButton(onPressed: _policy, icon: const Icon(Icons.tune_rounded), tooltip: t('سياسة التصحيح', 'Grading policy')),
        IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OfflineExamPanel(examId: widget.examId, title: widget.examTitle)))
                .then((_) => _load()),
            icon: const Icon(Icons.offline_pin_rounded), tooltip: t('الاختبار دون اتصال', 'Offline sitting')),
      ]),
      child: AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          AppHero(title: widget.examTitle, subtitle: t('يقترح المصحح الآلي وتقرر أنت · الأقل ثقة أولاً', 'The grader proposes, you decide · lowest confidence first'),
              icon: Icons.rate_review_outlined),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppChoiceChip(label: t('المفتوحة', 'Open'), selected: _state == 'open', onTap: () => setState(() { _state = 'open'; _load(); })),
            AppChoiceChip(label: t('الكل', 'All'), selected: _state == 'all', onTap: () => setState(() { _state = 'all'; _load(); })),
          ]),
          const SizedBox(height: 10),
          if (gradeReview != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppBanner(
                key: const ValueKey('review.gradeReview'),
                icon: Icons.photo_camera_outlined,
                text: t('راجع الدرجات المكتوبة على أوراق الطلاب بالكاميرا', 'Check the marks written on the students\' papers with the camera'),
                action: TextButton(onPressed: () => gradeReview(context, widget.examId, widget.examTitle), child: Text(t('مراجعة الدرجات بالكاميرا', 'Grade review by camera'))),
              ),
            ),
          if (_error != null) AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
          if (q == null && _error == null) const AppListSkeleton(items: 3),
          if (q != null && !q.doubleMarking && q.approvable(q.threshold) > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppBanner(
                icon: Icons.done_all_rounded,
                text: approvableProposalsText(q.approvable(q.threshold)),
                action: TextButton(onPressed: _bulk, child: Text(t('اعتماد', 'Approve'))),
              ),
            ),
          if (q != null && _omrReview && q.items.any((it) => it.fromPaperReader))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppBanner(
                key: const ValueKey('review.sheetBanner'),
                icon: Icons.document_scanner_outlined,
                text: t('بعض هذه الإجابات قُرئت من أوراق ممسوحة. راجعها بجوار صورة كل إجابة من الورقة.',
                    'Some of these answers were read from scanned papers. Review them next to the image of each answer.'),
                action: TextButton(onPressed: _openSheetReview, child: Text(t('افتح', 'Open'))),
              ),
            ),
          if (q != null && q.items.isEmpty) AppEmpty(icon: Icons.task_alt_rounded, title: t('لا توجد إجابات تنتظر التصحيح', 'Nothing waits for marking')),
          if (q != null)
            for (final it in q.items)
              ReviewAnswerCard(item: it, threshold: q.threshold, studentName: reviewStudentText(it, _names), busy: _busy.contains(it.answerId),
                  onAccept: () => _accept(it), onEdit: () => _edit(it),
                  onScan: it.scanPageId == null ? null : () => _scans(pageId: it.scanPageId),
                  onSheet: _omrReview && it.fromPaperReader ? () => _openSheetReview(it) : null),
        ]),
      ),
    );
  }
}

/// The engine exams a teacher manages for a course, with how many answers wait for them. Hidden when the engine is
/// not deployed or the course has no engine exams, so the legacy hub stays as it was.
class EngineReviewSection extends StatefulWidget {
  const EngineReviewSection({super.key, required this.courseId, this.onItems});
  final int courseId;

  /// The engine exams once loaded: the exam hub counts them in its header and drops its legacy "No exams yet" when
  /// there are some (it showed 0 / 0 / 0 and "No exams yet" under a list of exams).
  final ValueChanged<List<Map<String, dynamic>>>? onItems;

  @override
  State<EngineReviewSection> createState() => _EngineReviewSectionState();
}

class _EngineReviewSectionState extends State<EngineReviewSection> with PageReturnAware {
  final _api = ExamAuthoringApi();
  List<Map<String, dynamic>> _items = const [];
  bool _ready = false;
  int? _orgId;
  Future<void>? _loading;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The hub is on screen again (a page above it closed, or its tab came back): an exam created or published from
  /// another page shows up without a pull (round 3 of the paper-exam e2e). One load at a time: the pop of a page this
  /// section opened also reloads it.
  @override
  void onPageReturn() => _load();

  Future<void> _load() => _loading ??= _fetch().whenComplete(() => _loading = null);

  // The course's space comes from the server: an organization's course answers 409 course_not_in_org naming it.
  Future<void> _fetch() async {
    final s = await _api.resolveScope(widget.courseId);
    if (!mounted || !s.list.ok) return;
    setState(() {
      _ready = true;
      _orgId = s.orgId;
      _items = asMapList(s.list.map['items']);
    });
    widget.onItems?.call(_items);
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)).then((_) => _load());

  void _edit([int? examId]) => _open(ExamEditorScreen(examId: examId, courseId: widget.courseId, orgId: _orgId));

  Future<void> _quick() async {
    await openQuickExam(context, courseId: widget.courseId, orgId: _orgId);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle(t('الاختبارات الجديدة', 'New-engine exams'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: () => _open(QuestionBankScreen(orgId: _orgId, courseId: widget.courseId)), icon: const Icon(Icons.quiz_outlined), tooltip: t('بنك الأسئلة', 'Question bank')),
              IconButton(onPressed: _quick, icon: Icon(Icons.add_circle_outline_rounded, color: c.primary), tooltip: t('اختبار جديد', 'New exam')),
            ])),
        // every exam at its natural height: the hub scrolls them with the rest of the tab (a box of a quarter of the
        // screen cut the list after two and a half rows, with empty space under it)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final e in _items)
              AppCard(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
                onTap: e['status'] == 'draft'
                    ? () => _edit(asInt(e['id']))
                    : () => _open(ExamResultsScreen(examId: asInt(e['id']), examTitle: '${e['title'] ?? ''}', courseId: widget.courseId)),
                child: Row(children: [
                  Icon(e['status'] == 'draft' ? Icons.edit_note_rounded : Icons.rate_review_outlined, color: c.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${e['title'] ?? ''}', style: appText(14, w: FontWeight.w700, c: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(examStatusLabel('${e['status'] ?? ''}'), style: appText(12, c: c.textMedium)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  if (e['status'] != 'draft')
                    AppBadgePill(omrAttemptsText(asInt(asMap(e['attempts'])['total'])), color: c.textMedium),
                  IconButton(onPressed: () => _edit(asInt(e['id'])), icon: Icon(Icons.edit_outlined, color: c.textMedium), tooltip: t('تعديل', 'Edit')),
                ]),
              ),
        ]),
      ]),
    );
  }
}
