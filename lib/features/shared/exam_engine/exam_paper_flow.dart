// Paper exams (Phase 6, brief §7.5): printed answer sheets, bulk scan upload, the mapping file, offline marks import and the
// student picker for the unmatched queue.
//
// Pure parts (unit-tested: test/org/exam_scan_flow_test.dart): result parsing, problem rows, error-code text, id parsing.
// Presentational widgets take plain values + callbacks so the layout harness can test them without a server or a picker.
// Server contract: ../back/exam_engine/routers/scans.py and grading.py (FLUTTER_API_CHANGES · phase 6).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, asMapList, t;
import 'exam_taking.dart' show examCodeText;

// ── pure ─────────────────────────────────────────────────────────────────────

/// One row the server refused in a marks / mapping file (`errors[]` on success, `problems[]` on a 422).
class PaperProblem {
  const PaperProblem({required this.row, required this.code, this.extra = const {}});
  final int row;
  final String code;
  final Map<String, dynamic> extra;

  factory PaperProblem.fromJson(Map<String, dynamic> j) =>
      PaperProblem(row: asInt(j['row']), code: '${j['code'] ?? ''}', extra: {for (final e in j.entries) if (e.key != 'row' && e.key != 'code') e.key: e.value});
}

List<PaperProblem> parseProblems(dynamic list) => [for (final p in asMapList(list)) PaperProblem.fromJson(p)];

String _need(dynamic v) => v is List ? v.join(', ') : '$v';

/// A row problem as text ("Row 4: …"); row 0 = the whole file.
String paperProblemText(PaperProblem p) {
  final what = switch (p.code) {
    'bad_row' => t('صف غير صالح (رقم الطالب أو السؤال أو الدرجة)', 'Invalid row (student, question or score)'),
    'not_a_student' => t('طالب ليس من طلاب هذا الاختبار: ${p.extra['student_id'] ?? ''}', 'Not a student of this exam: ${p.extra['student_id'] ?? ''}'),
    'question_not_in_paper' => t('السؤال ${p.extra['question_id'] ?? ''} ليس في الورقة', 'Question ${p.extra['question_id'] ?? ''} is not in the paper'),
    'score_out_of_range' => t('الدرجة خارج المدى (الأعلى ${p.extra['max'] ?? ''})', 'Score out of range (maximum ${p.extra['max'] ?? ''})'),
    'empty_file' => t('الملف فارغ', 'The file is empty'),
    'missing_columns' => t('أعمدة ناقصة: ${_need(p.extra['need'])}', 'Missing columns: ${_need(p.extra['need'])}'),
    _ => paperCodeText(p.code),
  };
  return p.row <= 0 ? what : t('الصف ${p.row}: $what', 'Row ${p.row}: $what');
}

/// Every code of the sheets / scans / mapping / marks routes, else the shared exam codes, else the code itself.
String paperCodeText(String code) => switch (code) {
      'students_required' => t('حدد الطلاب أو عدد الأوراق الفارغة', 'Choose students or a number of blank sheets'),
      'not_a_student' => t('طالب ليس من طلاب هذا الاختبار', 'Not a student of this exam'),
      'too_many_files' => t('حد الرفع 50 ملفاً في المرة', 'Up to 50 files at a time'),
      'too_many_pages' => t('عدد الصفحات أكبر من الحد المسموح في الرفع الواحد', 'Too many pages in one upload'),
      'upload_too_large' => t('حجم الرفع الكلي أكبر من المسموح', 'The upload is larger than allowed'),
      'file_too_large' => t('الملف أكبر من الحد المسموح', 'The file is larger than allowed'),
      'no_files' => t('أرفق صورة أو ملف PDF', 'Attach an image or a PDF'),
      'unsupported_file' => t('نوع ملف غير مدعوم (PNG، JPEG، WebP، PDF)', 'Unsupported file type (PNG, JPEG, WebP, PDF)'),
      'grading_busy' => t('قائمة التصحيح ممتلئة الآن — أعد المحاولة بعد قليل', 'The grading queue is full — try again shortly'),
      'bad_mapping_file' => t('الملف يحتاج الأعمدة student_id و file_name', 'The file needs the columns student_id and file_name'),
      'bad_marks_file' => t('الملف يحتاج الأعمدة student_id و question_id و score', 'The file needs the columns student_id, question_id and score'),
      'too_many_rows' => t('حد الاستيراد 5000 صف', 'Import is limited to 5000 rows'),
      'scan_not_found' => t('الصفحة غير موجودة', 'The page was not found'),
      'scan_not_rendered' => t('الصفحة لم تُعالَج بعد — أعد المحاولة بعد قليل', 'The page is not processed yet — try again shortly'),
      'batch_not_found' => t('الدفعة غير موجودة', 'The batch was not found'),
      'question_not_in_paper' => t('السؤال ليس في الورقة', 'The question is not in the paper'),
      'forbidden' => t('ليس لديك صلاحية على هذا الاختبار', 'You have no rights on this exam'),
      'exam_not_found' => t('الاختبار غير موجود', 'The exam was not found'),
      'too_many_requests' => t('طلبات كثيرة — أعد المحاولة بعد قليل', 'Too many requests — try again shortly'),
      _ => examCodeText(code),
    };

/// Text for a failed call: the code, else the server message, else a generic line.
String paperFailText(String? code, String message) {
  if (code != null && code.isNotEmpty) {
    final x = paperCodeText(code);
    if (x != code) return x;
  }
  return message.isNotEmpty ? message : t('تعذر تنفيذ الطلب', 'The request failed');
}

/// `{batch_id, pages, duplicates}` of the scan upload.
class ScanUploadResult {
  const ScanUploadResult({required this.batchId, required this.pages, required this.duplicates});
  final int batchId, pages, duplicates;
  factory ScanUploadResult.fromJson(Map<String, dynamic> j) =>
      ScanUploadResult(batchId: asInt(j['batch_id']), pages: asInt(j['pages']), duplicates: asInt(j['duplicates']));

  String get summary => duplicates > 0
      ? t('رُفعت $pages صفحة وتجاهلنا $duplicates مكررة (الدفعة #$batchId)', '$pages pages uploaded, $duplicates duplicates skipped (batch #$batchId)')
      : t('رُفعت $pages صفحة (الدفعة #$batchId)', '$pages pages uploaded (batch #$batchId)');
}

/// `{saved, errors[], attempts}` of the marks entry / import.
class MarksImportResult {
  const MarksImportResult({required this.saved, required this.attempts, required this.problems});
  final int saved, attempts;
  final List<PaperProblem> problems;
  factory MarksImportResult.fromJson(Map<String, dynamic> j) =>
      MarksImportResult(saved: asInt(j['saved']), attempts: asInt(j['attempts']), problems: parseProblems(j['errors']));
  String get summary => t('حُفظت $saved درجة لـ $attempts طالباً', '$saved marks saved for $attempts students');
}

/// `{assigned, errors[]}` of the mapping file.
class MappingResult {
  const MappingResult({required this.assigned, required this.problems});
  final int assigned;
  final List<PaperProblem> problems;
  factory MappingResult.fromJson(Map<String, dynamic> j) => MappingResult(assigned: asInt(j['assigned']), problems: parseProblems(j['errors']));
  String get summary => t('أُسندت $assigned صفحة', '$assigned pages assigned');
}

/// Student ids typed as "12, 15 ٣٢\n40" (Arabic digits too); bad tokens are dropped, duplicates removed, order kept.
List<int> parseStudentIds(String text) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final norm = text.split('').map((ch) => ar.contains(ch) ? '${ar.indexOf(ch)}' : ch).join();
  final seen = <int>{};
  return [
    for (final tok in norm.split(RegExp(r'[\s,;،]+')))
      if (int.tryParse(tok) case final id? when id > 0 && seen.add(id)) id
  ];
}

/// The students the exam already knows (paper or online attempts) from `GET …/attempts`; empty under anonymous grading
/// (the server hides `student_id`), so the picker also takes a typed id.
List<int> rosterFromAttempts(Map<String, dynamic> body) {
  final seen = <int>{};
  return [
    for (final a in asMapList(body['items']))
      if (a['student_id'] != null && seen.add(asInt(a['student_id']))) asInt(a['student_id'])
  ]..sort();
}

/// Batch ids of a scans listing, newest first.
List<int> batchIdsOf(Map<String, dynamic> body) {
  final s = <int>{for (final p in asMapList(body['items'])) if (p['batch_id'] != null) asInt(p['batch_id'])};
  return s.toList()..sort((a, b) => b.compareTo(a));
}

// ── widgets ──────────────────────────────────────────────────────────────────

/// The four paper actions. [busy] names the one that is running (`sheets|upload|mapping|marks`); the others are disabled.
class PaperToolsPanel extends StatelessWidget {
  const PaperToolsPanel({super.key, required this.busy, required this.onSheets, required this.onUpload, required this.onMapping, required this.onMarks});
  final String? busy;
  final VoidCallback onSheets, onUpload, onMapping, onMarks;

  @override
  Widget build(BuildContext context) {
    Widget tile(String id, IconData icon, String title, String sub, VoidCallback go) => _ToolTile(
          icon: icon, title: title, subtitle: sub, busy: busy == id, onTap: busy == null ? go : null);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(t('الأوراق الورقية', 'Paper exam')),
      tile('sheets', Icons.print_outlined, t('أوراق الإجابة', 'Answer sheets'), t('نزّل أوراقاً بالرمز لكل طالب أو أوراقاً فارغة', 'Download QR-coded sheets per student, or blank ones'), onSheets),
      tile('upload', Icons.upload_file_rounded, t('رفع الأوراق الممسوحة', 'Upload scans'), t('صور أو PDF — تُسند تلقائياً بالرمز', 'Images or PDFs — matched by the QR code'), onUpload),
      tile('mapping', Icons.table_view_rounded, t('ملف الإسناد', 'Mapping file'), t('CSV أو Excel يربط اسم الملف بالطالب', 'CSV or Excel linking a file name to a student'), onMapping),
      tile('marks', Icons.grading_rounded, t('استيراد الدرجات', 'Import marks'), t('للاختبارات الورقية بالكامل — student_id, question_id, score', 'For fully offline exams — student_id, question_id, score'), onMarks),
    ]);
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.icon, required this.title, required this.subtitle, required this.busy, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Opacity(
      opacity: onTap == null && !busy ? .55 : 1,
      child: AppCard(
        margin: const EdgeInsets.only(bottom: 8),
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: c.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: appText(14, w: FontWeight.w700, c: c.textDark)),
              const SizedBox(height: 2),
              Text(subtitle, style: appText(12, c: c.textMedium)),
            ]),
          ),
          const SizedBox(width: 8),
          if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) else Icon(Icons.chevron_right_rounded, color: c.textMedium),
        ]),
      ),
    );
  }
}

/// The outcome of an upload / import: one line, and the refused rows below it.
class PaperResultView extends StatelessWidget {
  const PaperResultView({super.key, required this.summary, this.problems = const [], this.maxRows = 50});
  final String summary;
  final List<PaperProblem> problems;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = problems.take(maxRows).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(icon: problems.isEmpty ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded, text: summary, color: problems.isEmpty ? c.success : c.warning),
      if (problems.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(t('${problems.length} صفاً لم يُقبل', '${problems.length} rows were not accepted'), style: appText(13, w: FontWeight.w700, c: c.danger)),
        const SizedBox(height: 4),
        for (final p in shown)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline_rounded, size: 16, color: c.danger),
              const SizedBox(width: 6),
              Expanded(child: Text(paperProblemText(p), style: appText(12.5, c: c.textDark))),
            ]),
          ),
        if (problems.length > shown.length)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('و${problems.length - shown.length} أخرى…', '…and ${problems.length - shown.length} more'), style: appText(12, c: c.textMedium))),
      ],
    ]);
  }
}

/// Body of the sheets sheet: pick students from the roster, add typed ids, or just N blank sheets.
class SheetsOptionsView extends StatelessWidget {
  const SheetsOptionsView({
    super.key, required this.roster, required this.selected, required this.onToggle, required this.idsController, required this.blankController,
    required this.onSubmit, required this.onShare, this.busy = false,
  });
  final List<int> roster;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final TextEditingController idsController, blankController;
  final VoidCallback onSubmit, onShare;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (roster.isNotEmpty) ...[
        AppSectionTitle(t('طلاب الاختبار', 'Students of the exam')),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in roster) AppChoiceChip(label: '#$id', selected: selected.contains(id), onTap: () => onToggle(id)),
        ]),
        const SizedBox(height: 12),
      ],
      AppField(controller: idsController, label: t('أرقام طلاب إضافية', 'More student ids'), hint: '12, 15, 40', ltr: true, maxLines: 2),
      const SizedBox(height: 10),
      AppField(controller: blankController, label: t('عدد الأوراق الفارغة', 'Blank sheets'), keyboard: TextInputType.number, ltr: true),
      const SizedBox(height: 12),
      AppPrimaryButton(label: t('تنزيل PDF', 'Download PDF'), icon: Icons.download_rounded, onPressed: busy ? null : onSubmit, busy: busy),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: busy ? null : onShare, icon: const Icon(Icons.share_rounded, size: 18), label: Text(t('مشاركة PDF', 'Share PDF'))),
    ]);
  }
}

/// Body of the student picker (unmatched queue): the roster to tap, or a typed id when the list is empty / hidden.
class StudentPickView extends StatelessWidget {
  const StudentPickView({super.key, required this.roster, required this.selected, required this.onSelect, required this.idController});
  final List<int> roster;
  final int? selected;
  final ValueChanged<int> onSelect;
  final TextEditingController idController;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (roster.isEmpty)
        AppBanner(icon: Icons.info_outline_rounded, text: t('لا توجد قائمة طلاب لهذا الاختبار — اكتب رقم الطالب', 'No student list for this exam — type the student id'))
      else
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in roster) AppChoiceChip(label: '#$id', selected: selected == id, onTap: () => onSelect(id)),
        ]),
      const SizedBox(height: 10),
      Text(t('أو اكتب الرقم', 'Or type the id'), style: appText(12, c: c.textMedium)),
      const SizedBox(height: 4),
      AppField(controller: idController, label: t('رقم الطالب', 'Student id'), keyboard: TextInputType.number, ltr: true),
    ]);
  }
}
