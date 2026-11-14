// The paper exam's own entry, on the exam's screens (the editor, the results, the quick builder's end): one card
// that leads to the exam's paper section (`ExamScansScreen`: print, camera, upload, the latest batches) and straight
// to the review and results pages through `OmrRoutes`. Shown for every exam whose delivery is paper, whatever its
// paper_format, from before the first scan until long after the last paper is graded — the section never depends
// on something waiting for review. The bubble parts (print bubble sheets, review, results) follow the kill switch
// `exam.omr`; without it the card still opens the section, where the written-answer tools live.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_scan_review.dart' show ExamScansScreen;
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_routes.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_sheets_sheet.dart';

/// The paper format in words (D-151).
String paperFormatText(String? format) => switch (format) {
      'bubble' => t('ورقة التظليل فقط', 'Bubble sheet only'),
      'both' => t('ورقة الأسئلة مع ورقة التظليل', 'Exam paper with a bubble sheet'),
      'paper' => t('ورقة الأسئلة فقط · إجابات مكتوبة بخط اليد', 'Exam paper only · handwritten answers'),
      _ => t('لم يُختر شكل الورقة بعد', 'The paper format is not chosen yet'),
    };

/// True when [setup] makes this a paper exam (any paper_format, even none chosen yet).
bool isPaperExam(ExamSetup? setup) => setup?.delivery == 'paper';

/// Opens the exam's paper section (print, scan, upload, the latest batches; review and results inside).
Future<void> openPaperSection(BuildContext context, {required int examId, String examTitle = ''}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExamScansScreen(examId: examId, examTitle: examTitle)));

/// The card, plain values (the layout harness pumps it). A null callback hides its action.
class PaperExamCard extends StatelessWidget {
  const PaperExamCard({
    super.key,
    required this.paperFormat,
    required this.onOpen,
    this.onPrint,
    this.onReview,
    this.onResults,
    this.onSetup,
    this.margin,
  });

  /// paper | bubble | both | null (not chosen yet).
  final String? paperFormat;

  /// The paper section (scan / upload live there).
  final VoidCallback onOpen;
  final VoidCallback? onPrint, onReview, onResults;

  /// "Finish the setup" while no paper format is chosen.
  final VoidCallback? onSetup;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary);
    final bubble = paperFormat == 'bubble' || paperFormat == 'both';
    final hint = switch (paperFormat) {
      null => t('اختر شكل الورقة لتطبع الأوراق وتصحّحها هنا.', 'Choose the paper format to print and mark the papers here.'),
      'paper' => t('ارفع صور أوراق الطلاب، راجع الإجابات المكتوبة مع صورة كل إجابة، ثم انشر النتائج.',
          'Upload the students\' papers, review each written answer next to its image, then publish the results.'),
      _ => t('اطبع الأوراق، ثم صوّرها أو ارفعها، راجع ما لم يتأكد منه النظام، ثم انشر النتائج.',
          'Print the sheets, scan or upload them, review what the system was unsure of, then publish the results.'),
    };
    return Semantics(
      container: true,
      child: AppCard(
        key: const ValueKey('paper.entry'),
        margin: margin,
        padding: const EdgeInsets.all(AppSpace.md),
        onTap: onOpen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.chip)),
              child: Icon(bubble ? Icons.grid_on_rounded : Icons.document_scanner_outlined, color: ink),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('الاختبار الورقي', 'Paper exam'), style: appText(15, w: FontWeight.w800, c: c.textDark)),
                const SizedBox(height: 2),
                Text(paperFormatText(paperFormat), style: appText(12.5, w: FontWeight.w600, c: ink, h: 1.3)),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            Icon(Icons.chevron_right_rounded, color: c.textMedium),
          ]),
          const SizedBox(height: AppSpace.xs),
          Text(hint, style: appText(12.5, c: c.textMedium, h: 1.4)),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (paperFormat == null && onSetup != null)
              AppPill(key: const ValueKey('paper.entry.setup'), icon: Icons.fact_check_outlined, label: t('أكمل الإعداد', 'Finish the setup'), onTap: onSetup),
            if (bubble && onPrint != null)
              AppPill(key: const ValueKey('paper.entry.print'), icon: Icons.print_outlined, label: t('طباعة أوراق التظليل', 'Print bubble sheets'), onTap: onPrint),
            AppPill(
                key: const ValueKey('paper.entry.scan'),
                icon: bubble ? Icons.document_scanner_outlined : Icons.upload_file_rounded,
                label: bubble ? t('التصوير والرفع', 'Scan or upload') : t('الأوراق والرفع', 'Sheets and uploads'),
                onTap: onOpen),
            if (onReview != null)
              AppPill(key: const ValueKey('paper.entry.review'), icon: Icons.rate_review_outlined, label: t('المراجعة', 'Review'), onTap: onReview),
            if (onResults != null)
              AppPill(key: const ValueKey('paper.entry.results'), icon: Icons.leaderboard_outlined, label: t('النتائج', 'Results'), onTap: onResults),
          ]),
        ]),
      ),
    );
  }
}

/// The card wired to the real pages. Reads `GET …/setup` itself unless [setup] is given; shows nothing for an online
/// exam (or while the setup is unknown).
class PaperExamEntry extends StatefulWidget {
  const PaperExamEntry({super.key, required this.examId, this.examTitle = '', this.setup, this.api, this.onSetup, this.onChanged, this.margin});
  final int examId;
  final String examTitle;

  /// Already loaded by the caller (no request then).
  final ExamSetup? setup;
  final ExamSetupApi? api;

  /// "Finish the setup" (the wizard) while no paper format is chosen.
  final VoidCallback? onSetup;

  /// After the section / review / results page closes (the caller reloads).
  final VoidCallback? onChanged;
  final EdgeInsetsGeometry? margin;

  @override
  State<PaperExamEntry> createState() => _PaperExamEntryState();
}

class _PaperExamEntryState extends State<PaperExamEntry> {
  ExamSetup? _loaded;

  ExamSetup? get _setup => widget.setup ?? _loaded;

  @override
  void initState() {
    super.initState();
    if (widget.setup == null) _load();
  }

  Future<void> _load() async {
    final r = await (widget.api ?? ExamSetupApi()).setup(widget.examId);
    if (mounted && r.ok) setState(() => _loaded = ExamSetup.fromJson(r.map));
  }

  Future<void> _after(Future<void> f) async {
    await f;
    if (!mounted) return;
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = _setup;
    if (!isPaperExam(s)) return const SizedBox.shrink();
    final omr = !AppConfig.disableList.contains(kExamOmrFeatureKey);
    final id = widget.examId;
    return PaperExamCard(
      paperFormat: s!.paperFormat,
      margin: widget.margin,
      onOpen: () => _after(openPaperSection(context, examId: id, examTitle: widget.examTitle)),
      onPrint: omr && s.isBubble ? () => showOmrSheetsSheet(context, examId: id) : null,
      onReview: omr && s.paperFormat != null && OmrRoutes.review != null ? () => _after(openOmrReview(context, id).then((_) {})) : null,
      onResults: omr && s.paperFormat != null && OmrRoutes.results != null ? () => _after(openOmrResults(context, id).then((_) {})) : null,
      onSetup: widget.onSetup,
    );
  }
}

/// The end of the quick builder for a paper exam: where the papers are printed, scanned and marked from now on.
Future<void> showPaperExamReady(BuildContext context, {required int examId, String examTitle = '', String? paperFormat, Future<void> Function()? onExamPaper}) async {
  final pick = await showAppSheet<String>(
      context, (ctx) => PaperExamReadyBody(paperFormat: paperFormat, canPrintPaper: onExamPaper != null, onPick: (v) => Navigator.pop(ctx, v)));
  if (!context.mounted) return;
  switch (pick) {
    case 'section':
      await openPaperSection(context, examId: examId, examTitle: examTitle);
    case 'paper':
      await onExamPaper?.call();
  }
}

/// The sheet's content, plain values (the layout harness pumps it).
class PaperExamReadyBody extends StatelessWidget {
  const PaperExamReadyBody({super.key, required this.paperFormat, required this.onPick, this.canPrintPaper = false});
  final String? paperFormat;
  final bool canPrintPaper;

  /// 'section' | 'paper' | null (later).
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(tone: AppTone.success, icon: Icons.check_circle_outline_rounded, title: t('الاختبار الورقي جاهز', 'The paper exam is ready'), children: [
      AppBanner(icon: Icons.task_alt_rounded, color: c.success, text: paperFormatText(paperFormat)),
      const SizedBox(height: AppSpace.sm),
      Text(
          t('من «الاختبار الورقي» تطبع الأوراق وتصوّرها أو ترفعها وتراجعها وتنشر النتائج. تجده دائمًا في محرر الاختبار وصفحة نتائجه.',
              'The "Paper exam" section is where you print, scan or upload, review and publish. It is always on the exam\'s editor and results pages.'),
          style: appText(13, c: c.textMedium, h: 1.45)),
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(
          key: const ValueKey('paper.ready.section'),
          label: t('افتح الاختبار الورقي', 'Open the paper exam'),
          icon: Icons.document_scanner_outlined,
          onPressed: () => onPick('section')),
      if (canPrintPaper) ...[
        const SizedBox(height: AppSpace.xs),
        OutlinedButton.icon(
          key: const ValueKey('paper.ready.paper'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
          onPressed: () => onPick('paper'),
          icon: const Icon(Icons.print_rounded, size: 18),
          label: Text(t('ورقة الامتحان للطباعة', 'Printable exam paper')),
        ),
      ],
      const SizedBox(height: AppSpace.xxs),
      TextButton(key: const ValueKey('paper.ready.later'), onPressed: () => onPick(null), child: Text(t('لاحقًا', 'Later'))),
    ]);
  }
}
