// Exam Hub, F4: "Correct this exam". One calm start: import one PDF with every paper, or scan with the camera; what was
// corrected so far, and the way back into it. An exam without bubble sheets goes straight to the written flow, so
// nobody lands on a dead end. A teacher's own sheet has no live camera (it looks for NextBrain's corner marks).
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../exam_features.dart' show kExamAutoCorrectKey;
import '../../exam_scan_review.dart' show ExamScansScreen;
import '../../paper/exam_setup.dart' show ExamSetup, ExamSetupApi, kExamOmrFeatureKey;
import '../../paper/omr_counts.dart' show omrSheetsText;
import '../../paper/scan/omr_routes.dart' show openOmrReview;
import '../../paper/scan/omr_scan.dart';
import '../../paper/scan/omr_scanner_screen.dart';
import '../../paper/scan/omr_upload_screen.dart';
import '../result/exam_get_result_screen.dart' show openExamGetResult;
import 'sheet_review_screen.dart';

Future<void> openExamCorrection(BuildContext context, {required int examId, required String title, int? courseId}) => Navigator.of(context)
    .push<void>(MaterialPageRoute<void>(builder: (_) => ExamCorrectionScreen(examId: examId, title: title, courseId: courseId)));

/// What the exam can do (pure, for the test). [written]: no bubble sheet, or scanning is switched off.
enum CorrectionRoute { written, uploadOnly, cameraAndUpload }

CorrectionRoute correctionRouteOf({required bool isBubble, required bool ownSheet, required bool omrOff}) {
  if (!isBubble || omrOff) return CorrectionRoute.written;
  return ownSheet ? CorrectionRoute.uploadOnly : CorrectionRoute.cameraAndUpload;
}

/// "3 need a clearer photo".
String correctionClearerText(int n) => t('بحاجة إلى صورة أوضح: $n', n == 1 ? '1 needs a clearer photo' : '$n need a clearer photo');

/// The batches added up: what has been read, what waits for a person.
class CorrectionTotals {
  const CorrectionTotals({this.total = 0, this.done = 0, this.graded = 0, this.review = 0, this.rejected = 0, this.pending = 0});
  final int total, done, graded, review, rejected, pending;

  static CorrectionTotals of(List<OmrBatchProgress> batches) {
    var total = 0, done = 0, graded = 0, review = 0, rejected = 0, pending = 0;
    for (final b in batches) {
      total += b.total;
      done += b.done;
      graded += b.graded;
      review += b.review;
      rejected += b.rejected;
      pending += b.pending;
    }
    return CorrectionTotals(total: total, done: done, graded: graded, review: review, rejected: rejected, pending: pending);
  }

  bool get any => total > 0;
}

class ExamCorrectionScreen extends StatefulWidget {
  const ExamCorrectionScreen({super.key, required this.examId, required this.title, this.courseId, this.setupApi, this.api});
  final int examId;
  final String title;
  final int? courseId;
  final ExamSetupApi? setupApi;
  final OmrScanApi? api;

  @override
  State<ExamCorrectionScreen> createState() => _ExamCorrectionScreenState();
}

class _ExamCorrectionScreenState extends State<ExamCorrectionScreen> {
  late final ExamSetupApi _setupApi = widget.setupApi ?? ExamSetupApi();
  late final OmrScanApi _api = widget.api ?? OmrScanApi();

  ExamSetup? _setup;
  List<OmrBatchProgress>? _batches;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _omrOff => AppConfig.disableList.contains(kExamOmrFeatureKey) || AppConfig.disableList.contains(kExamAutoCorrectKey);

  Future<void> _load() async {
    setState(() => _error = null);
    final setupF = _setupApi.setup(widget.examId);
    final batchF = _api.batches(widget.examId, limit: 20);
    final s = await setupF;
    final b = await batchF;
    if (!mounted) return;
    if (!s.ok) return setState(() => _error = omrErrorText(s));
    final setup = ExamSetup.fromJson(s.map);
    if (correctionRouteOf(isBubble: setup.isBubble, ownSheet: setup.template?.ownSheet ?? false, omrOff: _omrOff) == CorrectionRoute.written) {
      await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => ExamScansScreen(examId: widget.examId, examTitle: widget.title)));
      return;
    }
    setState(() {
      _setup = setup;
      _batches = b.ok ? OmrBatchList.fromJson(b.map).items : const [];
    });
  }

  bool get _ownSheet => _setup?.template?.ownSheet ?? false;

  Future<void> _import() async {
    await startOmrUpload(context, examId: widget.examId, examTitle: widget.title, api: widget.api, camera: false);
    if (mounted) _load();
  }

  Future<OmrPaperStep> _showPaper(BuildContext context, OmrCaptureResult res, Uint8List photo) async {
    final exit = await openSheetReview(context,
        examId: widget.examId,
        examTitle: widget.title,
        batchId: res.batchId!,
        pageId: res.pageId,
        photo: photo,
        suggestRetake: res.result?.tier == OmrTier.retake);
    return switch (exit?.kind) {
      SheetExitKind.retake => OmrPaperStep.retake,
      SheetExitKind.finish => OmrPaperStep.finish,
      _ => OmrPaperStep.nextPaper,
    };
  }

  Future<void> _scan({int? batchId, int? replacePageId}) async {
    final exit = await Navigator.of(context).push<OmrScannerExit>(MaterialPageRoute<OmrScannerExit>(
        builder: (_) => OmrScannerScreen(
            examId: widget.examId, examTitle: widget.title, api: widget.api, onPaper: _showPaper, batchId: batchId, replacePageId: replacePageId)));
    if (!mounted) return;
    if (exit == OmrScannerExit.finished) {
      await _openResult();
    }
    if (mounted) _load();
  }

  Future<void> _openResult() => openExamGetResult(context, examId: widget.examId, title: widget.title, courseId: widget.courseId);

  Future<void> _openBatch(OmrBatchProgress b) async {
    final exit = await openSheetReview(context, examId: widget.examId, examTitle: widget.title, batchId: b.batchId, canShoot: !_ownSheet);
    if (!mounted) return;
    switch (exit?.kind) {
      case SheetExitKind.nextPaper:
        await _scan(batchId: b.kind == 'camera' ? b.batchId : null);
      case SheetExitKind.retake:
        await _scan(batchId: b.kind == 'camera' ? b.batchId : null, replacePageId: exit!.pageId);
      case SheetExitKind.finish:
        await _openResult();
      case null:
        break;
    }
    if (mounted) _load();
  }

  Future<void> _openProblems(OmrBatchProgress b) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => OmrScanProgressScreen(examId: widget.examId, examTitle: widget.title, batchId: b.batchId, camera: b.kind == 'camera', api: widget.api)));
    if (mounted) _load();
  }

  Future<void> _review() async {
    await openOmrReview(context, widget.examId);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final batches = _batches;
    return BasePage(
      appBar: AppBar(title: Text(t('تصحيح الاختبار', 'Correct the exam'))),
      background: c.background,
      child: _error != null
          ? Center(
              child: AppEmpty(
                icon: Icons.cloud_off_rounded,
                title: t('تعذّر فتح التصحيح', "Correction couldn't be opened"),
                message: _error,
                actionLabel: t('إعادة المحاولة', 'Try again'),
                onAction: _load,
              ),
            )
          : batches == null
              ? const AppListSkeleton(items: 4)
              : CorrectionStartView(
                  title: widget.title,
                  batches: batches,
                  ownSheet: _ownSheet,
                  preferUpload: kIsWeb,
                  onImport: _import,
                  onScan: _ownSheet ? null : () => _scan(),
                  onResume: _resumeTarget(batches) == null ? null : () => _scan(batchId: _resumeTarget(batches)!.batchId),
                  onBatch: _openBatch,
                  onProblems: _openProblems,
                  onReview: _review,
                  onResults: _openResult,
                ),
    );
  }

  /// The newest camera batch can be carried on with the same count of papers; only when the camera is on offer.
  OmrBatchProgress? _resumeTarget(List<OmrBatchProgress> list) {
    if (_ownSheet) return null;
    for (final b in list) {
      if (b.kind == 'camera') return b;
    }
    return null;
  }
}

// ── the start, as plain values ──────────────────────────────────────────────────────────────────────────────────

class CorrectionStartView extends StatelessWidget {
  const CorrectionStartView({
    super.key,
    required this.title,
    required this.batches,
    this.ownSheet = false,
    this.preferUpload = false,
    this.onImport,
    this.onScan,
    this.onResume,
    this.onBatch,
    this.onProblems,
    this.onReview,
    this.onResults,
  });

  final String title;
  final List<OmrBatchProgress> batches;
  final bool ownSheet;

  /// On a computer the PDF is the recommended way; on a phone, the camera.
  final bool preferUpload;
  final VoidCallback? onImport;

  /// Null: this exam cannot be shot with the live camera.
  final VoidCallback? onScan;
  final VoidCallback? onResume;
  final ValueChanged<OmrBatchProgress>? onBatch;
  final ValueChanged<OmrBatchProgress>? onProblems;
  final VoidCallback? onReview;
  final VoidCallback? onResults;

  @override
  Widget build(BuildContext context) {
    final totals = CorrectionTotals.of(batches);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 960;
      final recommendUpload = preferUpload || onScan == null;
      final options = <Widget>[
        _OptionCard(
          key: const ValueKey('correct.import'),
          icon: Icons.picture_as_pdf_rounded,
          title: t('استيراد ملف PDF واحد بكل الأوراق', 'Import one PDF with all the papers'),
          body: t('امسح الأوراق كلها في ملف واحد. حتى ${OmrLimits.maxPages} صفحة و25 ميجابايت.',
              'Scan every paper into one file. Up to ${OmrLimits.maxPages} pages and 25 MB.'),
          badge: recommendUpload ? t('الأنسب', 'Recommended') : null,
          onTap: onImport,
        ),
        if (onScan != null)
          _OptionCard(
            key: const ValueKey('correct.camera'),
            icon: Icons.document_scanner_rounded,
            title: t('التصوير بالكاميرا', 'Scan with the camera'),
            body: t('ورقة بعد ورقة: تظهر الدرجة فوق الصورة، ولا تنتظر التصحيح لتصوير التالية.',
                'Paper by paper: the degree appears on the photo, and the next shot never waits for grading.'),
            badge: recommendUpload ? null : t('الأنسب', 'Recommended'),
            onTap: onScan,
          )
        else
          _CameraOffNote(ownSheet: ownSheet),
      ];
      final progress = totals.any
          ? _ProgressPanel(totals: totals, batches: batches, onResume: onResume, onBatch: onBatch, onProblems: onProblems, onReview: onReview, onResults: onResults)
          : _EmptyProgress(onResults: onResults);
      final head = Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(22, w: FontWeight.w800, c: context.colors.textDark, h: 1.25)),
          const SizedBox(height: AppSpace.xxs),
          Text(t('صحّح أوراق التظليل بطريقتك، وتابع من حيث توقفت.', 'Correct the bubble sheets your way, and carry on where you stopped.'),
              style: appText(14.5, c: context.colors.textMedium, h: 1.4)),
        ]),
      );
      final gutter = AppSpace.gutter(box.maxWidth);
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              head,
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: options)),
                  const SizedBox(width: AppSpace.lg),
                  Expanded(child: progress),
                ])
              else ...[
                ...options,
                const SizedBox(height: AppSpace.md),
                progress,
              ],
            ]),
          ),
        ),
      );
    });
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({super.key, required this.icon, required this.title, required this.body, this.badge, this.onTap});
  final IconData icon;
  final String title, body;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.lg),
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.card)),
          child: Icon(icon, color: appInk(context, c.primary), size: AppIconSize.xl),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (badge != null) ...[AppBadgePill(badge!, color: c.success), const SizedBox(height: AppSpace.xxs)],
            Text(title, style: appText(17, w: FontWeight.w800, c: c.textDark, h: 1.3)),
            const SizedBox(height: AppSpace.xxs),
            Text(body, style: appText(13.5, c: c.textMedium, h: 1.45)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        Icon(Icons.chevron_right_rounded, color: c.textMedium),
      ]),
    );
  }
}

class _CameraOffNote extends StatelessWidget {
  const _CameraOffNote({required this.ownSheet});
  final bool ownSheet;

  @override
  Widget build(BuildContext context) {
    if (!ownSheet) return const SizedBox.shrink();
    return AppBanner(
      icon: Icons.info_outline_rounded,
      text: t('ورقة هذا الاختبار من تصميمك، فلا تعمل معها الكاميرا الحية. ارفع صورًا لها أو ملف PDF، ومن الهاتف يمكنك التقاطها من المعرض.',
          'This exam uses your own sheet, so the live camera does not work with it. Upload photos or a PDF; on a phone you can pick photos from the gallery.'),
    );
  }
}

class _EmptyProgress extends StatelessWidget {
  const _EmptyProgress({this.onResults});
  final VoidCallback? onResults;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('لم تُصحَّح أي ورقة بعد', 'No paper corrected yet'), style: appText(16, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: AppSpace.xxs),
        Text(t('بعد أول ورقة ستجد هنا ما صُحّح، وما يحتاج مراجعتك، ومكان المتابعة.', "After the first paper you'll find here what is corrected, what needs you, and where to carry on."),
            style: appText(13.5, c: c.textMedium, h: 1.45)),
        if (onResults != null) ...[
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              onPressed: onResults,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(t('عندي الدرجات في ملف Excel', 'I have the degrees in an Excel file')),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.totals, required this.batches, this.onResume, this.onBatch, this.onProblems, this.onReview, this.onResults});
  final CorrectionTotals totals;
  final List<OmrBatchProgress> batches;
  final VoidCallback? onResume, onReview, onResults;
  final ValueChanged<OmrBatchProgress>? onBatch, onProblems;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final finished = totals.total > 0 && totals.done >= totals.total && totals.review == 0 && totals.rejected == 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        key: const ValueKey('correct.progress'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('ما تم حتى الآن', 'So far'), style: appText(13, w: FontWeight.w700, c: c.textMedium)),
          const SizedBox(height: AppSpace.xxs),
          Text(
            t('صُحّحت ${totals.graded} من ${omrSheetsText(totals.total)}', '${totals.graded} of ${totals.total} papers corrected'),
            style: appText(20, w: FontWeight.w800, c: c.textDark, h: 1.3),
          ),
          const SizedBox(height: AppSpace.sm),
          AppProgressBar(value: totals.total == 0 ? 0 : totals.graded * 100 / totals.total, height: 8, color: finished ? c.success : c.primary),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (totals.pending > 0) AppBadgePill(t('${totals.pending} تُقرأ الآن', '${totals.pending} being read'), color: c.primary),
            if (totals.review > 0) AppBadgePill(t('${totals.review} للمراجعة', '${totals.review} to review'), color: c.warning),
            if (totals.rejected > 0) AppBadgePill(correctionClearerText(totals.rejected), color: c.danger),
          ]),
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (onResume != null)
              FilledButton.icon(
                key: const ValueKey('correct.resume'),
                style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(t('متابعة التصوير', 'Carry on scanning')),
              ),
            if (totals.review > 0 && onReview != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                onPressed: onReview,
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(t('مراجعة ${totals.review}', 'Review ${totals.review}')),
              ),
            if (onResults != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                onPressed: onResults,
                icon: const Icon(Icons.leaderboard_outlined),
                label: Text(t('النتائج', 'Results')),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: AppSpace.sm),
      AppSectionTitle(t('الدفعات', 'Batches')),
      for (final b in batches.take(6))
        AppCard(
          key: ValueKey('correct.batch.${b.batchId}'),
          margin: const EdgeInsets.only(bottom: AppSpace.xs),
          onTap: onBatch == null ? null : () => onBatch!(b),
          child: Row(children: [
            Icon(b.kind == 'camera' ? Icons.photo_camera_outlined : Icons.picture_as_pdf_outlined, color: b.finished ? c.success : c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.text, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                Text(b.whenText, style: appText(12.5, c: c.textMedium)),
                const SizedBox(height: AppSpace.xxs),
                AppProgressBar(value: b.fraction * 100, height: 5, color: b.finished ? c.success : c.primary),
                if (b.rejected > 0) ...[
                  const SizedBox(height: AppSpace.xxs),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
                    onPressed: onProblems == null ? null : () => onProblems!(b),
                    child: Text(correctionClearerText(b.rejected), style: appText(13, w: FontWeight.w700, c: appInk(context, c.danger))),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            Icon(Icons.chevron_right_rounded, color: c.textMedium),
          ]),
        ),
    ]);
  }
}
