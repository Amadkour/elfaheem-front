// The bubble-sheet part of the exam's scans screen (exam_scan_review.dart): Print bubble sheets · Scan with camera ·
// Upload images / PDF · Review · Results, and the latest batches with their "X of N papers processed" (tap → the
// progress screen); "Show all batches" lists every batch, older ones a page at a time (`?limit=&before=`). Shown for an exam whose paper_format is bubble / both, behind the kill switch `exam.omr`.
// With [OmrScanSection.bubble] false (an "Exam paper only" exam: handwritten answers on the engine's printed sheets)
// it keeps only Review and Results: the written answers are reviewed on the same page, each next to its crop (D-160).
// With [OmrScanSection.ownSheet] (an answer table or the teacher's own detected sheet, D-302) there is nothing to
// print and no live camera (it looks for NextBrain's marks): papers come in through Upload (photos, scans, PDFs; a
// phone's gallery offers its camera too).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/paper/scan/omr_routes.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scanner_screen.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_sheets_sheet.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_upload_screen.dart';

class OmrScanSection extends StatefulWidget {
  const OmrScanSection({super.key, required this.examId, this.examTitle = '', this.bubble = true, this.ownSheet = false, this.api, this.onChanged});
  final int examId;
  final String examTitle;

  /// A bubble-sheet exam (bubble / both): print, camera, upload and the batches; false = Review and Results only.
  final bool bubble;

  /// The exam's sheet is not printed by NextBrain (D-241 answer table, D-302 own sheet): no Print, no live camera.
  final bool ownSheet;
  final OmrScanApi? api;

  /// Called after a scan / upload screen closes (the caller reloads its page list).
  final VoidCallback? onChanged;

  @override
  State<OmrScanSection> createState() => _OmrScanSectionState();
}

class _OmrScanSectionState extends State<OmrScanSection> {
  late final OmrScanApi _api = widget.api ?? OmrScanApi();
  List<OmrBatchProgress> _batches = const [];
  bool _all = false, _hasMore = false, _loadingMore = false;
  int? _nextBefore;

  /// One more than shown, so the first answer already says whether "Show all batches" has anything to add.
  static const _firstPage = kOmrLatestBatches + 1;
  static const _olderPage = 20;

  @override
  void initState() {
    super.initState();
    if (widget.bubble) _load();
  }

  /// The newest batches again (after a scan / upload screen closes): as many as are listed now, at most 100.
  Future<void> _load() async {
    final limit = _all ? _batches.length.clamp(_firstPage, 100) : _firstPage;
    final r = await _api.batches(widget.examId, limit: limit);
    if (!mounted || !r.ok) return;
    final page = OmrBatchList.fromJson(r.map);
    setState(() {
      _batches = page.items;
      _hasMore = page.hasMore;
      _nextBefore = page.nextBefore;
    });
  }

  /// "Show older batches": the next page after the last one listed.
  Future<void> _older() async {
    final before = _nextBefore;
    if (before == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    final r = await _api.batches(widget.examId, limit: _olderPage, before: before);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _loadingMore = false);
      return;
    }
    final page = OmrBatchList.fromJson(r.map);
    final known = {for (final b in _batches) b.batchId};
    setState(() {
      _batches = [..._batches, for (final b in page.items) if (!known.contains(b.batchId)) b];
      _hasMore = page.hasMore;
      _nextBefore = page.nextBefore;
      _loadingMore = false;
    });
  }

  /// "Show all batches": every batch loaded so far, and the next page when the first one was all there was.
  void _showAll() {
    setState(() => _all = true);
    if (_hasMore && _batches.length <= _firstPage) _older();
  }

  void _open(OmrBatchProgress b) => _after(Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OmrScanProgressScreen(
          examId: widget.examId, examTitle: widget.examTitle, batchId: b.batchId, camera: b.kind == 'camera', api: widget.api))));

  Future<void> _after(Future<void> f) async {
    await f;
    if (!mounted) return;
    _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final soon = t('تتوفر قريبًا', 'Available soon');
    final entries = [
      if (widget.bubble && !widget.ownSheet) ...[
        OmrToolEntry(
          id: 'print',
          icon: Icons.print_outlined,
          title: t('طباعة أوراق التظليل', 'Print bubble sheets'),
          subtitle: t('PDF لكل نموذج، أو ورقة باسم كل طالب', 'A PDF per model, or a named sheet per student'),
          onTap: () => showOmrSheetsSheet(context, examId: widget.examId, api: widget.api),
        ),
        OmrToolEntry(
          id: 'camera',
          icon: Icons.document_scanner_outlined,
          title: t('التصوير بالكاميرا', 'Scan with camera'),
          subtitle: t('التقاط تلقائي عند ثبات الورقة ووضوحها', 'Captures by itself when the sheet is steady and sharp'),
          onTap: () => _after(Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => OmrScannerScreen(examId: widget.examId, examTitle: widget.examTitle, api: widget.api)))),
        ),
      ],
      if (widget.bubble) ...[
        OmrToolEntry(
          id: 'upload',
          icon: Icons.upload_file_rounded,
          title: t('رفع الأوراق', 'Upload papers'),
          subtitle: widget.ownSheet
              ? t('صوّر الأوراق أو ارفع صورًا وملفات PDF — نجد كل صفحة ونعدّلها ونطابقها بنفسنا',
                  'Photograph the papers or upload photos and PDFs — we find, straighten and match every page ourselves')
              : t('من معرض الصور أو الملفات أو مجلد الماسح الضوئي — صور وPDF معًا',
                  "From the photo gallery, files or a scanner's folder — images and PDFs together"),
          onTap: () => _after(startOmrUpload(context, examId: widget.examId, examTitle: widget.examTitle, api: widget.api, camera: !widget.ownSheet)),
        ),
      ],
      OmrToolEntry(
        id: 'review',
        icon: Icons.rate_review_outlined,
        title: t('المراجعة', 'Review'),
        subtitle: widget.bubble
            ? t('الحالات غير الواضحة: رقم الطالب، النموذج، التظليل', 'Unclear cases: student ID, model, marks')
            : t('كل إجابة مكتوبة بجوار صورتها من الورقة: اقبل الدرجة أو عدّلها', 'Each written answer next to its image from the paper: accept or change the score'),
        onTap: OmrRoutes.review == null ? null : () => _after(openOmrReview(context, widget.examId)),
        note: OmrRoutes.review == null ? soon : null,
      ),
      OmrToolEntry(
        id: 'results',
        icon: Icons.leaderboard_outlined,
        title: t('النتائج', 'Results'),
        subtitle: t('الدرجات وإحصاءات الأسئلة والنشر', 'Grades, question statistics and publishing'),
        onTap: OmrRoutes.results == null ? null : () => _after(openOmrResults(context, widget.examId)),
        note: OmrRoutes.results == null ? soon : null,
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.bubble)
        OmrToolsPanel(entries: entries)
      else
        OmrToolsPanel(
          entries: entries,
          title: t('الإجابات المكتوبة', 'Written answers'),
          subtitle: t('راجع ما قرأه النظام من أوراق الطلاب، ثم انشر النتائج', "Review what the system read from the students' papers, then publish the results"),
        ),
      if (_batches.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        OmrBatchesPanel(
          batches: _batches,
          expanded: _all,
          hasMore: _hasMore,
          loadingMore: _loadingMore,
          onOpen: _open,
          onShowAll: _showAll,
          onMore: _older,
        ),
      ],
    ]);
  }
}
