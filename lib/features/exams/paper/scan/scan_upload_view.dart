// What a pick holds before it is sent ("12 files found · 9 images · 3 PDFs · 2 skipped"), the parts going up
// ("Uploading 3 of 12 files"), and what did not go with a Retry — plain values in, drawn the same on the bubble-sheet
// progress screen (omr_upload_screen.dart) and on the written-answer upload page below ([ScanUploadPage]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/exams/paper/omr_counts.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scan.dart' show omrErrorText;
import 'package:flutter_education_app/features/exams/paper/scan/scan_files.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_prepare.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_sources.dart';

/// "12 files found" / "وُجد 12 ملفًا".
String scanFoundText(int n) => countText(n,
    ar0: 'لم يُعثر على صور أو ملفات PDF',
    ar1: 'وُجد ملف واحد',
    ar2: 'وُجد ملفان',
    arFew: 'وُجدت {n} ملفات',
    arMany: 'وُجد {n} ملفًا',
    en0: 'No images or PDFs found',
    en1: '1 file found',
    en: '{n} files found');

/// "Uploading 3 of 12 files" / "جارٍ رفع 3 من 12 ملفًا".
String scanUploadingText(int done, int total) =>
    t('جارٍ رفع $done من ${omrFilesText(total, after: true)}', 'Uploading $done of ${omrFilesText(total)}');

/// "3 files uploaded" / "رُفعت 3 ملفات".
String scanUploadedText(int n) => countText(n,
    ar1: 'رُفع ملف واحد', ar2: 'رُفع ملفان', arFew: 'رُفعت {n} ملفات', arMany: 'رُفع {n} ملفًا', en1: '1 file uploaded', en: '{n} files uploaded');

/// "2 files were not uploaded".
String scanNotUploadedText(int n) => countText(n,
    ar1: 'لم يُرفع ملف واحد',
    ar2: 'لم يُرفع ملفان',
    arFew: 'لم تُرفع {n} ملفات',
    arMany: 'لم يُرفع {n} ملفًا',
    en1: '1 file was not uploaded',
    en: '{n} files were not uploaded');

String scanSkipText(ScanSkipReason r) => switch (r) {
      ScanSkipReason.unsupported => t('ليس صورة ولا ملف PDF', 'Not an image or a PDF'),
      ScanSkipReason.tooLarge => t('ملف PDF أكبر من 25 ميجابايت', 'A PDF larger than 25 MB'),
      ScanSkipReason.empty => t('ملف فارغ', 'Empty file'),
    };

/// A part the server (or the gateway in front of it) refused, in plain words.
String scanSendErrorText(EngineResult r) {
  final retake = scanRetakeText(r);
  if (retake != null) return retake;
  if (r.status == 413) {
    return t('أكبر مما يقبله الخادم في طلب واحد — قسّم الملف أو قلّل دقته', 'Too large for the server in one request — split the file or lower its resolution');
  }
  return omrErrorText(r);
}

/// An NB2 page refused by the quality check (contract B3), in words: what is wrong and what to do; null for any other.
String? scanRetakeText(EngineResult r) {
  switch (r.code) {
    case 'sheet_marks_missing':
      final found = r.detail['found'];
      final seen = found is num ? t(' (ظهر ${found.toInt()} من 4)', ' (${found.toInt()} of 4 seen)') : '';
      return t('أعد تصوير هذه الصفحة: لم تظهر المربعات الأربعة في الأركان$seen. صوّر الصفحة كاملة ومستوية.',
          'Retake this page: the four corner squares were not found$seen. Photograph the whole page, flat.');
    case 'page_blurry':
      return t('أعد تصوير هذه الصفحة: الصورة غير واضحة. ثبّت الهاتف وأعد التصوير.', 'Retake this page: the photo is blurred. Hold still and take it again.');
    case 'not_this_exam':
      return t('هذه الورقة لاختبار آخر. ارفعها في اختبارها.', 'This sheet belongs to another exam. Upload it there.');
  }
  return null;
}

String _mb(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 10 ? mb.toStringAsFixed(0) : mb.toStringAsFixed(1);
}

IconData scanSourceIcon(ScanSource? s) => switch (s) {
      ScanSource.folder => Icons.folder_open_rounded,
      ScanSource.gallery => Icons.photo_library_outlined,
      ScanSource.camera => Icons.photo_camera_outlined,
      _ => Icons.upload_file_rounded,
    };

/// The pick before it is sent: counts, what is left out and why, Upload / Choose again.
class ScanPickSummary extends StatelessWidget {
  const ScanPickSummary({super.key, required this.plan, this.source, required this.onUpload, required this.onChooseAgain});
  final ScanPlan plan;
  final ScanSource? source;
  final VoidCallback onUpload, onChooseAgain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = plan.files.length;
    final bytes = plan.knownBytes;
    final folder = plan.folder;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        key: const ValueKey('scan.summary'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: (n > 0 ? c.primary : c.warning).withValues(alpha: .12), shape: BoxShape.circle),
              child: Icon(scanSourceIcon(source), color: n > 0 ? c.primary : c.warning),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plan.tooMany ? t('ملفات أكثر من اللازم', 'Too many files') : scanFoundText(n),
                    style: appText(18, w: FontWeight.w800, c: c.textDark, h: 1.25)),
                if (folder != null && folder.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(t('من المجلد «$folder»', 'From the folder “$folder”'),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textMedium)),
                ] else if (n > 0 && bytes != null) ...[
                  const SizedBox(height: 2),
                  Text(t('${_mb(bytes)} ميجابايت', '${_mb(bytes)} MB'), style: appText(13, c: c.textMedium)),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppStatChip(icon: Icons.image_outlined, value: '${plan.images}', label: t('صور', 'Images'), color: c.primary),
            AppStatChip(icon: Icons.picture_as_pdf_outlined, value: '${plan.pdfs}', label: t('ملفات PDF', 'PDFs'), color: c.primary),
            if (plan.skipped.isNotEmpty)
              AppStatChip(icon: Icons.block_rounded, value: '${plan.skipped.length}', label: t('تم تخطيها', 'Skipped'), color: c.warning),
          ]),
          if (plan.tooMany) ...[
            const SizedBox(height: AppSpace.sm),
            AppBanner(
              icon: Icons.warning_amber_rounded,
              color: c.warning,
              text: t('أكثر من $kScanMaxPick ملف في هذا المجلد — اختر مجلد فصل أو اختبار واحد',
                  'More than $kScanMaxPick files in this folder — choose the folder of one class or one exam'),
            ),
          ] else if (n > 0) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              t('تُرسل على دفعات صغيرة بترتيب أسماء الملفات؛ الصفحات المرفوعة من قبل تُتخطّى.',
                  'Sent in small parts in file-name order; pages uploaded before are skipped.'),
              style: appText(12.5, c: c.textMedium, h: 1.4),
            ),
          ],
          if (plan.hidden > 0) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(
              t('تجاهلنا ملفات النظام المخفية (${plan.hidden})', 'Hidden system files ignored (${plan.hidden})'),
              style: appText(12, c: c.textLight),
            ),
          ],
        ]),
      ),
      if (plan.skipped.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        ScanFileList(
          key: const ValueKey('scan.skipped'),
          title: t('لن تُرفع', 'Will not be uploaded'),
          rows: [for (final s in plan.skipped) (s.label, scanSkipText(s.reason))],
          color: c.warning,
        ),
      ],
      const SizedBox(height: AppSpace.md),
      if (n > 0)
        AppPrimaryButton(
          key: const ValueKey('scan.upload'),
          label: t('رفع ${omrFilesText(n, after: true)}', 'Upload ${omrFilesText(n)}'),
          icon: Icons.cloud_upload_outlined,
          onPressed: onUpload,
        ),
      const SizedBox(height: AppSpace.sm),
      OutlinedButton.icon(
        key: const ValueKey('scan.again'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
        onPressed: onChooseAgain,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(t('اختيار ملفات أخرى', 'Choose other files')),
      ),
    ]);
  }
}

/// Files with a reason each (left out, failed); folded after the first [fold] rows.
class ScanFileList extends StatefulWidget {
  const ScanFileList({super.key, required this.title, required this.rows, required this.color, this.fold = 5});
  final String title;
  final List<(String, String)> rows;
  final Color color;
  final int fold;

  @override
  State<ScanFileList> createState() => _ScanFileListState();
}

class _ScanFileListState extends State<ScanFileList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _all ? widget.rows : widget.rows.take(widget.fold).toList();
    final more = widget.rows.length - rows.length;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: appText(14, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        for (final (label, reason) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.insert_drive_file_outlined, size: 18, color: widget.color),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // a file name reads left to right whatever the language
                  Text(label,
                      textDirection: TextDirection.ltr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appText(13, w: FontWeight.w600, c: c.textDark)),
                  Text(reason, style: appText(12.5, c: c.textMedium, h: 1.35)),
                ]),
              ),
            ]),
          ),
        if (more > 0)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              onPressed: () => setState(() => _all = true),
              child: Text(t('عرض ${omrFilesText(more, after: true)} أخرى', 'Show ${omrFilesText(more)} more')),
            ),
          ),
      ]),
    );
  }
}

/// The parts going up.
class ScanUploadProgress extends StatelessWidget {
  const ScanUploadProgress({super.key, required this.done, required this.total, this.current});
  final int done, total;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final frac = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0).toDouble();
    return AppCard(
      key: const ValueKey('scan.progress'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: .12), shape: BoxShape.circle),
            child: Icon(Icons.cloud_upload_outlined, color: c.primary),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(liveRegion: true, child: Text(scanUploadingText(done, total), style: appText(17, w: FontWeight.w800, c: c.textDark, h: 1.25))),
              const SizedBox(height: 2),
              Text(t('ابقَ على هذه الصفحة حتى يكتمل الرفع', 'Stay on this page until the upload finishes'), style: appText(13, c: c.textMedium)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        AppProgressBar(value: frac * 100, height: 8, color: c.primary),
        if (current != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(current!,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appText(12, c: c.textLight)),
        ],
      ]),
    );
  }
}

/// What did not go, with Retry.
class ScanUploadFailures extends StatelessWidget {
  const ScanUploadFailures({super.key, required this.failures, required this.onRetry, this.busy = false});
  final List<ScanFailure> failures;
  final VoidCallback? onRetry;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = failures.length;
    // pages to photograph again come first, apart: sending the same photo again cannot help (D-687)
    final retake = [for (final f in failures) if (f.retake) f];
    final other = [for (final f in failures) if (!f.retake) f];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: scanNotUploadedText(n)),
      if (retake.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        ScanFileList(
          key: const ValueKey('scan.retake'),
          title: t('أعد تصوير هذه الصفحات', 'Retake these pages'),
          rows: [for (final f in retake) (f.file.label, f.reason)],
          color: appInkOn(context, c.warning, c.cardBg),
        ),
      ],
      if (other.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        ScanFileList(
          key: const ValueKey('scan.failed'),
          title: t('الأسباب', 'Why'),
          rows: [for (final f in other) (f.file.label, f.reason)],
          color: c.danger,
        ),
      ],
      if (other.isEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('صوّرها من جديد ثم ارفع الصور الجديدة.', 'Photograph them again, then upload the new photos.'), style: AppType.meta(context)),
      ],
      if (other.isNotEmpty) ...[
      const SizedBox(height: AppSpace.sm),
      AppPrimaryButton(
        key: const ValueKey('scan.retry'),
        label: t('إعادة رفع ${omrFilesText(other.length, after: true)}', 'Retry ${omrFilesText(other.length)}'),
        icon: Icons.refresh_rounded,
        busy: busy,
        onPressed: busy ? null : onRetry,
      ),
      ],
    ]);
  }
}

/// The outcome of [ScanUploadPage]: the batch, new pages, duplicates (null batch = nothing went).
class ScanUploadOutcome {
  const ScanUploadOutcome({this.batchId, this.pages = 0, this.duplicates = 0, this.failed = 0});
  final int? batchId;
  final int pages, duplicates, failed;
}

/// The written-answer / QR sheets upload (exam_scan_review.dart): the pick's summary, the parts, the failures with
/// Retry; pops with a [ScanUploadOutcome] (straight away when everything went).
class ScanUploadPage extends StatefulWidget {
  const ScanUploadPage({super.key, required this.pick, required this.send, this.prepare, this.onChooseAgain});
  final ScanPick pick;
  final ScanSend send;
  final ScanPrepare? prepare;

  /// "Choose other files": the caller's sheet again (null: back to the page).
  final Future<ScanPick?> Function(BuildContext context)? onChooseAgain;

  @override
  State<ScanUploadPage> createState() => _ScanUploadPageState();
}

class _ScanUploadPageState extends State<ScanUploadPage> {
  late ScanPick _pick = widget.pick;
  late ScanPlan _plan = _pick.plan();
  ScanUploader? _up;

  ScanUploadOutcome _outcome() =>
      ScanUploadOutcome(batchId: _up?.batchId, pages: _up?.pages ?? 0, duplicates: _up?.duplicates ?? 0, failed: _up?.failures.length ?? 0);

  Future<void> _start() async {
    final up = ScanUploader(
      files: _plan.files,
      prepare: widget.prepare ?? prepareScanFile,
      send: widget.send,
      errorText: scanSendErrorText,
      prepareErrorText: scanPrepareErrorText,
      onChange: () {
        if (mounted) setState(() {});
      },
    );
    setState(() => _up = up);
    await up.run();
    if (mounted && up.failures.isEmpty) Navigator.of(context).pop(_outcome());
  }

  Future<void> _retry() async {
    final up = _up!;
    await up.retry();
    if (mounted && up.failures.isEmpty) Navigator.of(context).pop(_outcome());
  }

  Future<void> _again() async {
    final again = widget.onChooseAgain;
    if (again == null) {
      Navigator.of(context).pop(_up?.anySent ?? false ? _outcome() : null);
      return;
    }
    final p = await again(context);
    if (p == null || !mounted) return;
    setState(() {
      _pick = p;
      _plan = p.plan();
      _up = null;
    });
  }

  Widget _body() {
    final c = context.colors;
    final up = _up;
    if (up == null) return ScanPickSummary(plan: _plan, source: _pick.source, onUpload: _start, onChooseAgain: _again);
    if (up.phase != ScanUploadPhase.done) {
      return ScanUploadProgress(done: up.finished, total: up.runTotal, current: up.current);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (up.anySent) ...[
        AppCard(
          child: Row(children: [
            Icon(Icons.task_alt_rounded, color: c.success),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(scanUploadedText(up.sent.length),
                  style: appText(15, w: FontWeight.w700, c: c.textDark)),
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      ScanUploadFailures(failures: up.failures, onRetry: _retry, busy: up.phase == ScanUploadPhase.sending),
      const SizedBox(height: AppSpace.sm),
      OutlinedButton(
        key: const ValueKey('scan.done'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
        onPressed: () => Navigator.of(context).pop(_outcome()),
        child: Text(t('تم', 'Done')),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final sending = _up?.phase == ScanUploadPhase.sending;
    return PopScope(
      // leaving mid-upload would drop the parts not sent yet
      canPop: !sending,
      child: BasePage(
        key: const ValueKey('exam.scans.upload'),
        appBar: AppHeader(title: t('رفع الأوراق', 'Upload papers')),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [_body()]),
          ),
        ),
      ),
    );
  }
}
