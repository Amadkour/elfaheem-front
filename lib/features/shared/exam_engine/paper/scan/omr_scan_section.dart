// The bubble-sheet part of the exam's scans screen (exam_scan_review.dart): Print bubble sheets · Scan with camera ·
// Upload images / PDF · Review · Results, and the latest batches with their "X of N papers processed" (tap → the
// progress screen). Shown for an exam whose paper_format is bubble / both, behind the kill switch `exam.omr`.
// With [OmrScanSection.bubble] false (an "Exam paper only" exam: handwritten answers on the engine's printed sheets)
// it keeps only Review and Results: the written answers are reviewed on the same page, each next to its crop (D-160).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show asMapList, t;
import 'omr_routes.dart';
import 'omr_scan.dart';
import 'omr_scan_widgets.dart';
import 'omr_scanner_screen.dart';
import 'omr_sheets_sheet.dart';
import 'omr_upload_screen.dart';

class OmrScanSection extends StatefulWidget {
  const OmrScanSection({super.key, required this.examId, this.examTitle = '', this.bubble = true, this.api, this.onChanged});
  final int examId;
  final String examTitle;

  /// A bubble-sheet exam (bubble / both): print, camera, upload and the batches; false = Review and Results only.
  final bool bubble;
  final OmrScanApi? api;

  /// Called after a scan / upload screen closes (the caller reloads its page list).
  final VoidCallback? onChanged;

  @override
  State<OmrScanSection> createState() => _OmrScanSectionState();
}

class _OmrScanSectionState extends State<OmrScanSection> {
  late final OmrScanApi _api = widget.api ?? OmrScanApi();
  List<OmrBatchProgress> _batches = const [];

  @override
  void initState() {
    super.initState();
    if (widget.bubble) _load();
  }

  Future<void> _load() async {
    final r = await _api.batches(widget.examId);
    if (!mounted || !r.ok) return;
    setState(() => _batches = [for (final b in asMapList(r.map['items'])) OmrBatchProgress.fromJson(b)]);
  }

  Future<void> _after(Future<void> f) async {
    await f;
    if (!mounted) return;
    _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final soon = t('تتوفر قريبًا', 'Available soon');
    final entries = [
      if (widget.bubble) ...[
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
        OmrToolEntry(
          id: 'upload',
          icon: Icons.upload_file_rounded,
          title: t('رفع الأوراق', 'Upload papers'),
          subtitle: t('من معرض الصور أو الملفات أو مجلد الماسح الضوئي — صور وPDF معًا',
              "From the photo gallery, files or a scanner's folder — images and PDFs together"),
          onTap: () => _after(startOmrUpload(context, examId: widget.examId, examTitle: widget.examTitle, api: widget.api)),
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
        AppSectionTitle(t('آخر الدفعات', 'Latest batches')),
        for (final b in _batches.take(5))
          AppCard(
            key: ValueKey('omr.batch.${b.batchId}'),
            margin: const EdgeInsets.only(bottom: AppSpace.xs),
            onTap: () => _after(Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OmrScanProgressScreen(
                    examId: widget.examId, examTitle: widget.examTitle, batchId: b.batchId, camera: b.kind == 'camera', api: widget.api)))),
            child: Row(children: [
              Icon(b.kind == 'camera' ? Icons.photo_camera_outlined : Icons.document_scanner_outlined, color: b.finished ? c.success : c.primary),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.text, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                  Text(b.whenText, key: ValueKey('omr.batch.when.${b.batchId}'), style: appText(12.5, c: c.textMedium)),
                  const SizedBox(height: AppSpace.xxs),
                  AppProgressBar(value: b.fraction * 100, height: 5, color: b.finished ? c.success : c.primary),
                  if (b.review > 0 || b.rejected > 0) ...[
                    const SizedBox(height: AppSpace.xs),
                    Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
                      if (b.review > 0) AppBadgePill(t('${b.review} للمراجعة', '${b.review} to review'), color: c.warning),
                      if (b.rejected > 0) AppBadgePill(t('${b.rejected} مرفوضة', '${b.rejected} rejected'), color: c.danger),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.chevron_right_rounded, color: c.textMedium),
            ]),
          ),
      ],
    ]);
  }
}
