// An exam's results for the teacher: every student's attempt (name from the course roster), what waits for marking,
// each answer with its grade and a "change" that overrides it (POST /answers/{id}/mark — objective answers too),
// offline marks typed per student, and "publish results" when students see them only once published.
// Students see only their own result (exam_result_screen.dart, from the student exam list).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asDouble, asInt, asMap, asMapList, t;
import '../../admin/admin_money_p8.dart' show p8SaveBytes;
import 'exam_authoring.dart';
import 'exam_paper_sheet.dart' show openExamPaper;
import 'exam_quick.dart';
import 'exam_review.dart' show ExamReviewApi;
import 'exam_review_screen.dart' show ExamReviewScreen;
import 'exam_taking.dart' show examCodeText;

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

  Future<void> _publishResults() async {
    if (!await appConfirm(context, message: t('يرى كل طالب نتيجته الآن. متابعة؟', 'Every student will now see their result. Continue?'))) return;
    setState(() => _busy = true);
    final r = await _api.lifecycle(widget.examId, ExamAction.publishResults);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return appToast(authoringError(r), error: true);
    appToast(t('نُشرت النتائج', 'Results published'));
    _load();
  }

  Future<void> _downloadPaper(Map<String, dynamic> f) async {
    try {
      final bytes = await _api.paperFile(widget.examId);
      await p8SaveBytes(bytes, '${f['name'] ?? 'exam'}', mime: '${f['content_type'] ?? 'application/octet-stream'}');
    } catch (e) {
      appToast('$e', error: true);
    }
  }

  Future<void> _open(ResultRow r) async {
    await showAppSheet<void>(context, (_) => AttemptAnswersSheet(attemptId: r.attemptId, title: r.name, api: _api));
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
    return BasePage(
      key: const ValueKey('exam.results'),
      appBar: AppBar(title: Text(widget.examTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          if (_error != null) AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
          if (rows == null && _error == null) const AppListSkeleton(items: 5),
          if (rows != null) ...[
            AppGrid(children: [
              AppStatTile(label: t('سلّموا', 'Submitted'), value: '$done', icon: Icons.assignment_turned_in_rounded),
              AppStatTile(label: t('المتوسط', 'Average'), value: avg == null ? '—' : '${avg.toStringAsFixed(0)}%', icon: Icons.insights_rounded),
              AppStatTile(label: t('ينتظر التصحيح', 'Waiting for you'), value: '$waiting', icon: Icons.rate_review_rounded,
                  color: waiting > 0 ? c.warning : null),
            ]),
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
                Text('${fmtPoints(row.score!)} / ${fmtPoints(row.maxScore!)}', style: appText(12.5, c: c.textMedium)),
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
  const AttemptAnswersSheet({super.key, required this.attemptId, required this.title, required this.api});
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
      appToast('$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader(widget.title),
      if (_error != null) AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
      if (items == null && _error == null) const AppListSkeleton(items: 3, withAvatar: false),
      if (items != null && items.isEmpty) AppEmpty(icon: Icons.inbox_outlined, title: t('لا توجد إجابات', 'No answers')),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${item['prompt'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: 6),
        Text(answerSummary(asMap(item['answer'])), maxLines: 6, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(
                finalScore != null ? '${fmtPoints(finalScore)} / ${fmtPoints(pts)}' : (proposal != null ? t('مقترح ${fmtPoints(proposal)} / ${fmtPoints(pts)}', 'Suggested ${fmtPoints(proposal)} / ${fmtPoints(pts)}') : '— / ${fmtPoints(pts)}'),
                style: appText(13.5, w: FontWeight.w800, c: finalScore != null ? c.primary : c.textMedium),
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
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader(t('إدخال الدرجات', 'Enter marks')),
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
