// An exam's results for the teacher: every student's attempt (name from the course roster), what waits for marking,
// each answer with its grade and a "change" that overrides it (POST /answers/{id}/mark — objective answers too),
// offline marks typed per student, and "publish results" when students see them only once published. A paper exam
// (delivery paper, any paper_format) always shows its "Paper exam" card on top (`PaperExamEntry`): print, scan /
// upload, review and results stay reachable before the first scan and after the last paper is graded.
// Students see only their own result (exam_result_screen.dart, from the student exam list).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asDouble, asInt, asMap, asMapList, t;
import '../../admin/admin_money_p8.dart' show p8SaveBytes;
import 'exam_authoring.dart';
import 'exam_grade_log_screen.dart' show ExamGradeLogScreen;
import 'exam_grading.dart';
import 'exam_grading_widgets.dart';
import 'exam_paper_sheet.dart' show openExamPaper;
import 'exam_quick.dart';
import 'exam_review.dart' show ExamReviewApi;
import 'exam_review_screen.dart' show ExamReviewScreen;
import 'exam_taking.dart' show examCodeText;
import 'paper/paper_exam_entry.dart' show PaperExamEntry;
import 'paper/review/omr_review.dart' show omrLtr;
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/api_client.dart';

/// A student's answer as one line of text (choice ids, text, file name …).
String answerSummary(Map<String, dynamic> answer) {
  if (answer['file'] is Map) return '📎 ${asMap(answer['file'])['name'] ?? ''}';
  if (answer['source'] == 'manual') return t('درجة مُدخلة يدوياً', 'Mark entered by hand');
  final text = answer['text'];
  if (text is String) return text.trim().isEmpty ? '—' : text.trim();
  if (answer['option'] != null) return '${answer['option']}';
  if (answer['options'] is List) return (answer['options'] as List).join(', ');
  if (answer['value'] != null) return '${answer['value']}${answer['unit'] != null ? ' ${answer['unit']}' : ''}';
  if (answer['blanks'] is List) return (answer['blanks'] as List).join(' · ');
  if (answer['order'] is List) return (answer['order'] as List).join(' → ');
  if (answer['pairs'] is Map) return asMap(answer['pairs']).entries.map((e) => '${e.key} ↔ ${e.value}').join(' · ');
  return answer.isEmpty ? '—' : '$answer';
}

/// Average percentage of the finished attempts, or null.
double? averagePercent(List<ResultRow> rows) {
  final v = [for (final r in rows) if (r.finished && r.percentage != null) r.percentage!];
  return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
}

/// The results table for Excel / Word / PDF (`showAppExportSheet`). Build it inside `bilingualExport(() => …)` so an
/// English or "Both" file gets English headers in the Arabic app. Pure (unit-tested).
AppTableExport examResultsExport({required String title, required List<ResultRow> rows}) {
  String status(ResultRow r) => r.needsReview ? 'waiting' : (r.finished ? (r.passed == true ? 'passed' : (r.passed == false ? 'failed' : 'submitted')) : 'not_submitted');
  return AppTableExport(
    id: 'exam.results',
    title: title,
    fileName: title,
    columns: [
      AppExportColumn('name', t('الطالب', 'Student'), locked: true),
      AppExportColumn('score', t('الدرجة', 'Score'), type: AppColType.number, decimals: 2),
      AppExportColumn('max', t('من', 'Out of'), type: AppColType.number, decimals: 2),
      AppExportColumn('percentage', t('النسبة', 'Percentage'), type: AppColType.percent, decimals: 1),
      AppExportColumn('status', t('الحالة', 'Status'), type: AppColType.status, statusLabels: {
        'passed': t('ناجح', 'Passed'),
        'failed': t('راسب', 'Failed'),
        'submitted': t('سلّم', 'Submitted'),
        'waiting': t('ينتظر التصحيح', 'Waiting for marking'),
        'not_submitted': t('لم يسلّم', 'Not submitted'),
      }),
    ],
    rows: [
      for (final r in rows) {'name': r.name, 'score': r.score, 'max': r.maxScore, 'percentage': r.percentage, 'status': status(r)},
    ],
  );
}

class ExamResultsScreen extends StatefulWidget {
  const ExamResultsScreen({super.key, required this.examId, required this.examTitle, this.courseId});
  final int examId;
  final String examTitle;
  final int? courseId;

  @override
  State<ExamResultsScreen> createState() => _ExamResultsScreenState();
}

class _ExamResultsScreenState extends State<ExamResultsScreen> {
  final _api = ExamAuthoringApi();
  ExamView? _exam;
  List<ResultRow>? _rows;
  Map<int, String> _names = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ex = await _api.exam(widget.examId);
    final at = await _api.attempts(widget.examId);
    if (_names.isEmpty && widget.courseId != null) {
      final r = await _api.courseStudents(widget.courseId!);
      final list = r.map['value'] is List ? asMapList(r.map['value']) : asMapList(r.map['items']);
      _names = {for (final s in list) asInt(s['id']): '${s['name'] ?? ''}'};
    }
    if (!mounted) return;
    setState(() {
      _error = !ex.ok ? authoringError(ex) : (!at.ok ? authoringError(at) : null);
      if (ex.ok) _exam = ExamView.fromJson(ex.map);
      if (at.ok) _rows = ResultRow.fromAttempts(at.map, _names);
    });
  }

  bool get _offline => _exam?.sections.any((s) => s.section.mode == 'paper') == true;

  PublishOutcome? _outcome;

  /// Publish. A plain publish that the server refuses with `review_pending` opens the sheet: go and review, or publish
  /// the reviewed attempts only (`graded_only`: the rest stay hidden from their students until a person resolves them).
  Future<void> _publishResults({bool gradedOnly = false}) async {
    if (!gradedOnly &&
        !await appConfirm(context, message: t('يرى كل طالب نتيجته الآن. متابعة؟', 'Every student will now see their result. Continue?'))) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final r = await ExamGradingApi().publishResults(widget.examId, gradedOnly: gradedOnly);
    if (!mounted) return;
    setState(() => _busy = false);
    final pending = ReviewPending.from(r);
    if (pending != null) {
      final pick = await showAppSheet<PublishChoice>(context, (_) => PublishBlockedSheet(pending: pending));
      if (!mounted || pick == null) return;
      if (pick == PublishChoice.publishReviewed) return _publishResults(gradedOnly: true);
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ExamReviewScreen(examId: widget.examId, examTitle: widget.examTitle)));
      if (mounted) _load();
      return;
    }
    if (!r.ok) return appToast(authoringError(r), error: true);
    final out = PublishOutcome.fromJson(r.map);
    setState(() => _outcome = out);
    appToast(out.text);
    _load();
  }

  Future<void> _unpublishResults() async {
    if (!await appConfirm(context,
        danger: true,
        message: t('يختفي الاختبار من نتائج الطلاب وأولياء الأمور فوراً إلى أن تنشره مرة أخرى. متابعة؟',
            'Students and parents stop seeing these results at once, until you publish them again. Continue?'))) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final r = await ExamGradingApi().unpublishResults(widget.examId);
    if (!mounted) return;
    setState(() { _busy = false; if (r.ok) _outcome = null; });
    if (!r.ok) return appToast(authoringError(r), error: true);
    appToast(t('أُلغي نشر النتائج', 'Results unpublished'));
    _load();
  }

  void _exportResults() {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return;
    showAppExportSheet(context, bilingualExport(() => examResultsExport(title: widget.examTitle, rows: rows)));
  }

  void _openGradeLog() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExamGradeLogScreen(examId: widget.examId, examTitle: widget.examTitle, attemptNames: {for (final r in _rows ?? const <ResultRow>[]) r.attemptId: r.name})));

  Future<void> _downloadPaper(Map<String, dynamic> f) async {
    try {
      final bytes = await _api.paperFile(widget.examId);
      await p8SaveBytes(bytes, '${f['name'] ?? 'exam'}', mime: '${f['content_type'] ?? 'application/octet-stream'}');
    } catch (e) {
      appToast(apiErrorText(ApiException.from(e)), error: true);
    }
  }

  Future<void> _open(ResultRow r) async {
    await showAppSheet<void>(context, (_) => AttemptAnswersSheet(attemptId: r.attemptId, title: r.name, api: _api, examId: widget.examId, examTitle: widget.examTitle));
    _load();
  }

  Future<void> _enterMarks() async {
    final v = _exam;
    if (v == null) return;
    final qs = [for (final s in v.sections) ...s.questions];
    final saved = await showAppSheet<bool>(context, (_) => OfflineMarksSheet(examId: widget.examId, questions: qs, students: _names, api: _api));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _rows;
    final v = _exam;
    final waiting = rows?.where((r) => r.needsReview).length ?? 0;
    final done = rows?.where((r) => r.finished).length ?? 0;
    final avg = rows == null ? null : averagePercent(rows);
    final paper = v == null ? null : paperFileOf(v.exam.toJsonForCopy());
    final canPublishResults = v != null && v.exam.resultsPolicy == 'when_published' && v.exam.resultsPublishedAt == null && v.exam.status != 'draft';
    final isPublished = v != null && v.exam.resultsPolicy == 'when_published' && v.exam.resultsPublishedAt != null;
    return BasePage(
      key: const ValueKey('exam.results'),
      appBar: AppBar(title: Text(widget.examTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
      child: AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          if (_error != null) AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
          PaperExamEntry(examId: widget.examId, examTitle: widget.examTitle, onChanged: _load, margin: const EdgeInsets.only(bottom: 12)),
          if (isPublished) Padding(padding: const EdgeInsets.only(bottom: 12), child: PublishedBanner(outcome: _outcome, publishedAt: v.exam.resultsPublishedAt, busy: _busy, onUnpublish: _unpublishResults)),
          if (rows == null && _error == null) const AppListSkeleton(items: 5),
          if (rows != null) ...[
            // the list already has its gutter (the grid's own 16 px indented the tiles past the cards); on a phone the
            // three numbers sit on one line as chips instead of three stacked full-width tiles
            LayoutBuilder(builder: (context, box) {
              final avgText = avg == null ? '—' : '${avg.toStringAsFixed(0)}%';
              if (box.maxWidth < 520) {
                return Wrap(key: const ValueKey('exam.results.stats'), spacing: 8, runSpacing: 8, children: [
                  AppStatChip(icon: Icons.assignment_turned_in_rounded, value: '$done', label: t('سلّموا', 'Submitted'), color: c.primary),
                  AppStatChip(icon: Icons.insights_rounded, value: avgText, label: t('المتوسط', 'Average'), color: c.primary),
                  AppStatChip(icon: Icons.rate_review_rounded, value: '$waiting', label: t('ينتظر التصحيح', 'Waiting for you'),
                      color: waiting > 0 ? c.warning : c.primary),
                ]);
              }
              return AppGrid(key: const ValueKey('exam.results.stats'), padding: EdgeInsets.zero, children: [
                AppStatTile(label: t('سلّموا', 'Submitted'), value: '$done', icon: Icons.assignment_turned_in_rounded),
                AppStatTile(label: t('المتوسط', 'Average'), value: avgText, icon: Icons.insights_rounded),
                AppStatTile(label: t('ينتظر التصحيح', 'Waiting for you'), value: '$waiting', icon: Icons.rate_review_rounded,
                    color: waiting > 0 ? c.warning : null),
              ]);
            }),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (waiting > 0)
                AppPill(
                    icon: Icons.rate_review_rounded,
                    label: t('صحّح الإجابات المنتظرة', 'Mark what is waiting'),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => ExamReviewScreen(examId: widget.examId, examTitle: widget.examTitle)))
                        .then((_) => _load())),
              if (_offline && _names.isNotEmpty) AppPill(icon: Icons.edit_note_rounded, label: t('إدخال الدرجات', 'Enter marks'), onTap: _enterMarks),
              if (canPublishResults) AppPill(icon: Icons.campaign_rounded, label: t('انشر النتائج للطلاب', 'Publish results to students'), onTap: _busy ? null : _publishResults),
              AppPill(icon: Icons.history_rounded, label: t('سجل الدرجات', 'Grade log'), onTap: _openGradeLog),
              if (rows.isNotEmpty) AppPill(icon: Icons.file_download_outlined, label: t('تصدير النتائج', 'Export results'), onTap: _exportResults),
              if (paper != null) AppPill(icon: Icons.download_rounded, label: t('ملف الامتحان', 'Exam file'), onTap: () => _downloadPaper(paper)),
              if (paper == null && v != null && v.questionCount > 0)
                AppPill(icon: Icons.print_rounded, label: t('ورقة الامتحان للطباعة', 'Printable exam paper'), onTap: () => openExamPaper(context, examId: widget.examId)),
            ]),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              AppEmpty(
                  icon: Icons.hourglass_empty_rounded,
                  title: t('لا توجد نتائج بعد', 'No results yet'),
                  message: _offline ? t('أدخل درجات الطلاب بعد الامتحان', 'Enter the students\' marks after the exam') : t('تظهر هنا عندما يسلّم الطلاب', 'They show up here as students submit')),
            for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: ResultRowCard(row: r, onTap: () => _open(r))),
          ],
        ]),
      ),
    );
  }
}

/// One student's result (plain values; under the layout harness).
class ResultRowCard extends StatelessWidget {
  const ResultRowCard({super.key, required this.row, this.onTap});
  final ResultRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = row.percentage;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        AppAvatar(name: row.name, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (row.needsReview) AppBadgePill(t('ينتظر التصحيح', 'Waiting for marking'), color: c.warning)
              else if (!row.finished) AppBadgePill(t('لم يسلّم', 'Not submitted'), color: c.textLight),
              if (row.score != null && row.maxScore != null)
                // one left-to-right run: in Arabic a bare "2 / 3" is drawn "3 / 2"
                Text(omrLtr('${fmtPoints(row.score!)} / ${fmtPoints(row.maxScore!)}'), style: appText(12.5, c: c.textMedium)),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        Text(p == null ? '—' : '${p.toStringAsFixed(0)}%', style: appText(16, w: FontWeight.w800, c: p == null ? c.textLight : appScoreColor(context, p))),
      ]),
    );
  }
}

/// One attempt's answers, each with its grade and a way to change it.
class AttemptAnswersSheet extends StatefulWidget {
  const AttemptAnswersSheet({super.key, required this.attemptId, required this.title, required this.api, this.examId, this.examTitle = ''});
  final int? examId;
  final String examTitle;
  final int attemptId;
  final String title;
  final ExamAuthoringApi api;

  @override
  State<AttemptAnswersSheet> createState() => _AttemptAnswersSheetState();
}

class _AttemptAnswersSheetState extends State<AttemptAnswersSheet> {
  final _review = ExamReviewApi();
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api.attemptReview(widget.attemptId);
    if (!mounted) return;
    setState(() {
      _error = r.ok ? null : authoringError(r);
      if (r.ok) _items = asMapList(r.map['answers'] ?? r.map['items']);
    });
  }

  Future<void> _change(Map<String, dynamic> it) async {
    final pts = asDouble(it['points']);
    final ctl = TextEditingController(text: it['final_score'] == null ? '' : fmtPoints(asDouble(it['final_score'])));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('الدرجة من ${fmtPoints(pts)}', 'Mark out of ${fmtPoints(pts)}')),
        content: TextField(controller: ctl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('حفظ', 'Save'))),
        ],
      ),
    );
    final score = parseNum(ctl.text);
    ctl.dispose();
    if (ok != true || !mounted) return;
    if (score == null || score < 0 || score > pts) return appToast(t('الدرجة بين 0 و ${fmtPoints(pts)}', 'The mark is between 0 and ${fmtPoints(pts)}'), error: true);
    final r = await _review.mark(asInt(it['answer_id']), score: score, comment: t('تعديل المعلم', 'Changed by the teacher'));
    if (!mounted) return;
    if (!r.ok) return appToast(examCodeText(r.code ?? r.message), error: true);
    appToast(t('عُدّلت الدرجة', 'The mark is changed'));
    _load();
  }

  Future<void> _download(Map<String, dynamic> it) async {
    final f = asMap(asMap(it['answer'])['file']);
    try {
      final bytes = await widget.api.answerFile(widget.attemptId, asInt(it['question_id']));
      await p8SaveBytes(bytes, '${f['name'] ?? 'answer'}', mime: '${f['content_type'] ?? 'application/octet-stream'}');
    } catch (e) {
      appToast(apiErrorText(ApiException.from(e)), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items;
    return AppSheetContent(title: widget.title, children: [
      if (_error != null) AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
      if (items == null && _error == null) const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero),
      if (items != null && items.isEmpty) AppEmpty(icon: Icons.inbox_outlined, title: t('لا توجد إجابات', 'No answers')),
      if (widget.examId != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('attempt.gradeLog'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ExamGradeLogScreen(examId: widget.examId!, examTitle: widget.examTitle, attemptId: widget.attemptId, attemptNames: {widget.attemptId: widget.title}))),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: Text(t('سجل تغييرات الدرجات', 'Grade changes')),
          ),
        ),
      for (final it in items ?? const <Map<String, dynamic>>[])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AnswerGradeCard(
            item: it,
            onChange: it['answer_id'] == null ? null : () => _change(it),
            onDownload: asMap(it['answer'])['file'] is Map ? () => _download(it) : null,
          ),
        ),
    ]);
  }
}

/// One answer with its grade (plain values; under the layout harness).
class AnswerGradeCard extends StatelessWidget {
  const AnswerGradeCard({super.key, required this.item, this.onChange, this.onDownload});
  final Map<String, dynamic> item;
  final VoidCallback? onChange;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pts = asDouble(item['points']);
    final finalScore = item['final_score'] == null ? null : asDouble(item['final_score']);
    final proposal = item['auto_score'] == null ? null : asDouble(item['auto_score']);
    final waiting = const {'needs_review', 'queued', 'proposed', 'second_pending', 'moderation'}.contains('${item['review_state']}');
    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${item['prompt'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: 6),
        Text(answerSummary(asMap(item['answer'])), maxLines: 6, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(
                finalScore != null
                    ? omrLtr('${fmtPoints(finalScore)} / ${fmtPoints(pts)}')
                    : (proposal != null
                        ? t('مقترح ${omrLtr('${fmtPoints(proposal)} / ${fmtPoints(pts)}')}', 'Suggested ${fmtPoints(proposal)} / ${fmtPoints(pts)}')
                        : omrLtr('— / ${fmtPoints(pts)}')),
                style: appText(13.5, w: FontWeight.w800, c: finalScore != null ? appInk(context, c.primary) : c.textMedium),
              ),
              if (waiting) AppBadgePill(t('ينتظر', 'Waiting'), color: c.warning),
            ]),
          ),
          if (onDownload != null) IconButton(onPressed: onDownload, icon: Icon(Icons.download_rounded, color: c.primary), tooltip: t('تنزيل الملف', 'Download the file')),
          if (onChange != null) TextButton(onPressed: onChange, child: Text(t('تغيير الدرجة', 'Change mark'))),
        ]),
      ]),
    );
  }
}

/// Offline exam: one row per student of the course, one field per question; empty fields are skipped.
class OfflineMarksSheet extends StatefulWidget {
  const OfflineMarksSheet({super.key, required this.examId, required this.questions, required this.students, required this.api});
  final int examId;
  final List<PlacedQuestion> questions;
  final Map<int, String> students;
  final ExamAuthoringApi api;

  @override
  State<OfflineMarksSheet> createState() => _OfflineMarksSheetState();
}

class _OfflineMarksSheetState extends State<OfflineMarksSheet> {
  final Map<(int, int), TextEditingController> _ctl = {};
  bool _busy = false;

  TextEditingController _c(int sid, int qid) => _ctl.putIfAbsent((sid, qid), TextEditingController.new);

  @override
  void dispose() {
    for (final x in _ctl.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final rows = <Map<String, dynamic>>[];
    for (final e in _ctl.entries) {
      if (e.value.text.trim().isEmpty) continue;
      final v = parseNum(e.value.text);
      if (v == null) return appToast(t('درجة غير صحيحة: ${e.value.text}', 'Not a number: ${e.value.text}'), error: true);
      rows.add({'student_id': e.key.$1, 'question_id': e.key.$2, 'score': v});
    }
    if (rows.isEmpty) return appToast(t('لم تُدخل أي درجة', 'No mark entered'), error: true);
    setState(() => _busy = true);
    final r = await widget.api.enterMarks(widget.examId, rows);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return appToast(authoringError(r), error: true);
    final errors = asMapList(r.map['errors']);
    if (errors.isNotEmpty) appToast(t('${errors.length} درجة لم تُحفظ (خارج المدى أو ليس طالباً)', '${errors.length} mark(s) not saved (out of range or not a student)'), error: true);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final students = widget.students.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return AppSheetContent(title: t('إدخال الدرجات', 'Enter marks'), children: [
      for (final s in students)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < widget.questions.length; i++)
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _c(s.key, widget.questions[i].questionId),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        isDense: true,
                        labelText: widget.questions.length == 1 ? t('الدرجة', 'Mark') : t('س${i + 1}', 'Q${i + 1}'),
                        suffixText: '/${fmtPoints(widget.questions[i].points)}'),
                  ),
                ),
            ]),
          ]),
        ),
      const SizedBox(height: 6),
      AppPrimaryButton(label: t('حفظ الدرجات', 'Save marks'), icon: Icons.save_rounded, busy: _busy, onPressed: _busy ? null : _save),
    ]);
  }
}
