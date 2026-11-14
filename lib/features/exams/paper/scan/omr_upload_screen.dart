// Bulk upload of bubble sheets (brief 3.3 / 3.4, Example 5): images (JPG / PNG / WebP) and PDFs through the exam's
// existing scan intake (`POST …/scans` routes a bubble exam's pages to the OMR pipeline), then "X of N papers
// processed" fed by the uploader's live event `job_updated {kind: omr_scan, id: batch}` through EventOrPoll (a slow
// poll only as the fallback), the rejected pages with the server's own sentence ("Page 7 is too blurry. Please
// upload a clearer image of it.") and "Replace this page" (`POST …/omr/pages/{id}/replace`: one photo through the
// capture gate, accepted or refused with the exact reason; the new page is followed by its `page_id` in the batch's
// events, its own page state as the fallback). The camera's session lands on the same screen.
// Where the pages come from is ONE sheet (scan_sources.dart: camera, gallery, files, a scanner's folder); a pick is
// shown first ("12 files found · 9 images · 3 PDFs · 2 skipped"), then sent in parts that join one batch
// (scan_files.dart ScanUploader: "Uploading 3 of 12 files", a failed part does not stop the rest, Retry).
// Smart photos: each paper read shows its own result (the batch's `pages[].result`: read successfully / N questions
// to review / read in part + a suggested retake / couldn't read + reason + tip) with a preview of the improved photo
// (`preview_url` through the signed-image call); a rejected page's preview offers "Replace this page".
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/paper/omr_counts.dart' show omrFilePlace, omrPaperText;
import 'package:flutter_education_app/features/exams/paper/review/omr_review_page.dart' show OmrReviewPage;
import 'package:flutter_education_app/features/exams/paper/scan/omr_batch_notice.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_paper_result.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_routes.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scan_issues.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scanner_screen.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_files.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_prepare.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_sources.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_upload_view.dart';

/// Picks ONE replacement page. Tests hand their own; the app opens the source sheet (gallery / files).
typedef OmrFilePicker = Future<List<(String, Uint8List)>> Function({bool many});

/// "Upload": the source sheet (the live camera too unless [camera] is false), then the progress screen with the
/// pick's summary first. [sources] / [platform]: tests.
Future<void> startOmrUpload(BuildContext context,
    {required int examId,
    String examTitle = '',
    OmrScanApi? api,
    OmrFilePicker? picker,
    bool replace = false,
    bool camera = true,
    ScanSourcePicker? sources,
    ScanPlatform? platform}) async {
  final nav = Navigator.of(context);
  final pick = await showScanSourceSheet(context, camera: camera, platform: platform, picker: sources);
  if (pick == null) return;
  final Route<void> route = pick.source == ScanSource.camera
      ? MaterialPageRoute<void>(builder: (_) => OmrScannerScreen(examId: examId, examTitle: examTitle, api: api))
      : MaterialPageRoute<void>(
          builder: (_) => OmrScanProgressScreen(
              examId: examId, examTitle: examTitle, picked: pick, api: api, picker: picker, sources: sources, platform: platform));
  if (replace) {
    await nav.pushReplacement(route);
  } else {
    await nav.push(route);
  }
}

class _Replacement {
  _Replacement(this.state, this.row);
  String state; // uploading · refused · processing · processed · review · rejected · failed

  /// The rejected page as it was listed: an accepted replacement takes it out of the batch's `rejected_pages`, and
  /// its row stays on screen with the outcome.
  final OmrRejectedPage? row;

  /// The new page (accepted): its `job_updated` / page state tells how the reading ended.
  int? newPageId;
  String? text;
}

/// A page status of the new page → the replacement's state (null while it is still being read).
String? _replacementState(String status) => switch (status) {
      'processed' => 'processed',
      'review' => 'review',
      'rejected' => 'rejected',
      'failed' || 'purged' => 'failed',
      _ => null,
    };

class OmrScanProgressScreen extends StatefulWidget {
  const OmrScanProgressScreen({
    super.key,
    required this.examId,
    this.examTitle = '',
    this.batchId,
    this.files,
    this.picked,
    this.camera = false,
    this.api,
    this.picker,
    this.sources,
    this.platform,
    this.prepare,
    this.liveBus,
    this.liveStream,
  }) : assert(batchId != null || files != null || picked != null);

  /// The camera's "Upload instead" (picks first, see [startOmrUpload]).
  static Widget pick({required int examId, String examTitle = '', OmrScanApi? api}) => _PickFirst(examId: examId, examTitle: examTitle, api: api);

  final int examId;
  final String examTitle;

  /// An existing batch (the camera session, an earlier upload) …
  final int? batchId;

  /// … or files to upload now (sent at once) …
  final List<(String, Uint8List)>? files;

  /// … or a pick from the source sheet: its summary first, sent on "Upload".
  final ScanPick? picked;
  final bool camera;
  final OmrScanApi? api;
  final OmrFilePicker? picker;

  /// Tests: the source sheet's pickers and platform, the file preparation.
  final ScanSourcePicker? sources;
  final ScanPlatform? platform;
  final ScanPrepare? prepare;
  final LiveEvents? liveBus;
  final LiveStreamHandle? liveStream;

  @override
  State<OmrScanProgressScreen> createState() => _OmrScanProgressScreenState();
}

class _OmrScanProgressScreenState extends State<OmrScanProgressScreen> {
  late final OmrScanApi _api = widget.api ?? OmrScanApi();

  /// The pick waiting for "Upload" (its summary is shown), null once sent / for a batch.
  ScanPlan? _plan;
  ScanSource? _source;
  ScanUploader? _up;
  int? _batchId;
  OmrBatchProgress? _progress;

  /// A FETCHED answer said done (the live event's "done" alone still needs the fetch: counts + rejected pages).
  bool _settled = false;
  OmrScanIssues _issues = OmrScanIssues.empty;
  bool _doneNoticed = false;
  String? _loadError;
  final Map<int, _Replacement> _replacements = {};
  EventOrPoll? _watch;

  @override
  void initState() {
    super.initState();
    _batchId = widget.batchId;
    if (widget.picked != null) {
      _plan = widget.picked!.plan();
      _source = widget.picked!.source;
    } else if (widget.files != null) {
      _upload([for (final (n, b) in widget.files!) ScanSourceFile.bytes(n, b)]);
    } else {
      _track();
    }
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  /// Sends the files part by part; the parts after the first join the first part's batch.
  Future<void> _upload(List<ScanSourceFile> files) async {
    final up = ScanUploader(
      files: files,
      prepare: widget.prepare ?? prepareScanFile,
      send: (part, batchId) => _api.upload(widget.examId, part, batchId: batchId),
      errorText: scanSendErrorText,
      prepareErrorText: scanPrepareErrorText,
      onChange: () {
        if (mounted) setState(() {});
      },
    );
    setState(() {
      _plan = null;
      _up = up;
    });
    await up.run();
    if (!mounted) return;
    _afterSend();
  }

  /// Retry: the failed files again, into the same batch.
  Future<void> _retry() async {
    final up = _up;
    if (up == null) return;
    await up.retry();
    if (!mounted) return;
    _afterSend();
  }

  void _afterSend() {
    final b = _up?.batchId;
    if (b == null) return;
    setState(() {
      _batchId = b;
      _settled = false; // new pages: the batch is read again
    });
    if (_watch?.running ?? false) {
      _watch!.poke();
    } else {
      _watch = null;
      _track();
    }
  }

  int get _duplicates => _up?.duplicates ?? 0;
  bool get _nothingNew => (_up?.anySent ?? false) && _up!.pages == 0 && _up!.failures.isEmpty;

  /// The batch while it is still being read (a replacement is a new page of the same batch).
  Set<String> get _open => {
        if (_batchId != null && (!_settled || _replacements.values.any((r) => r.state == 'processing'))) '$_batchId',
      };

  void _track() {
    if (_batchId == null) return;
    if (_watch?.running ?? false) {
      _watch!.poke();
      return;
    }
    _watch = EventOrPoll(
      poll: _poll,
      every: const Duration(seconds: 3),
      fallbackEvery: const Duration(seconds: 15),
      match: (e) => e.kind == kOmrScanJobKind && _open.contains(e.id),
      onEvent: (e) {
        // the event's own numbers at once ("13 of 40 papers processed"); the fetch right after brings the rest
        if (e.id == '$_batchId' && _progress != null && mounted) setState(() => _progress = _progress!.withEvent(e.data));
        if (e.id == '$_batchId') {
          _loadIssues();
          if ('${e.data['status']}' == 'done') _batchDone();
        }
        // a replacement's page read: its outcome at once
        final pid = int.tryParse('${e.data['page_id'] ?? ''}');
        final st = _replacementState('${e.data['page_status'] ?? ''}');
        if (pid != null && st != null && mounted) {
          for (final rep in _replacements.values) {
            if (rep.newPageId == pid && rep.state == 'processing') setState(() => rep.state = st);
          }
        }
      },
      bus: widget.liveBus,
      stream: widget.liveStream,
    )..start(pollNow: true);
  }

  Future<void> _loadIssues() async {
    final b = _batchId;
    if (b == null) return;
    final r = await _api.issues(widget.examId, batchId: b);
    if (!mounted || !r.ok) return;
    setState(() => _issues = OmrScanIssues.fromJson(r.map));
  }

  /// The batch finished while the screen is open: "Grading finished: X graded, Y to review" (once per run).
  Future<void> _batchDone() async {
    if (_doneNoticed) return;
    _doneNoticed = true;
    await _poll(); // the counts of the finished batch
    if (!mounted) return;
    final p = _progress;
    showOmrBatchDone(p?.graded ?? 0, p?.review ?? 0, () => openOmrReview(context, widget.examId));
  }

  void _openIssue(OmrScanIssue i) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OmrReviewPage(examId: widget.examId, initialItemId: i.reviewItemId)));
  }

  Future<void> _poll() async {
    final ids = _open;
    if (ids.isEmpty) {
      _watch?.stop();
      return;
    }
    for (final id in ids) {
      final r = await _api.batch(widget.examId, int.parse(id));
      if (!mounted) return;
      if (!r.ok) {
        if (id == '$_batchId') setState(() => _loadError = omrErrorText(r));
        continue;
      }
      final p = OmrBatchProgress.fromJson(r.map);
      setState(() {
        _loadError = null;
        // a read older than the live event already shown never moves the count back (a replacement may lower it)
        final cur = _progress;
        if (cur == null || p.finished || p.done >= cur.done || p.total != cur.total) _progress = p;
        if (p.finished) _settled = true;
        if (!p.finished) _doneNoticed = false;
      });
    }
    // the replacements still being read: their page's own state (the fallback when no event came)
    for (final rep in _replacements.values.where((r) => r.state == 'processing' && r.newPageId != null).toList()) {
      final r = await _api.page(widget.examId, rep.newPageId!);
      if (!mounted) return;
      if (!r.ok) continue;
      final page = r.map['page'] is Map ? Map<String, dynamic>.from(r.map['page'] as Map) : const <String, dynamic>{};
      final st = _replacementState('${page['status'] ?? ''}');
      if (st != null) setState(() => rep.state = st);
    }
    if (_open.isEmpty) _watch?.stop();
    await _loadIssues();
  }

  /// "Replace this page": ONE photo through the capture gate on the request (`POST …/omr/pages/{id}/replace`) —
  /// accepted (a new page of the same batch, read like any other) or refused with the exact reason, nothing stored.
  Future<void> _replace(int pageId) async {
    final files = widget.picker != null
        ? await widget.picker!(many: false)
        : await pickOneScanPage(context, platform: widget.platform, picker: widget.sources, pageLabel: _pageLabelOf(pageId), paper: true);
    if (files.isEmpty || !mounted) return;
    final problem = omrReplaceProblem(files.first);
    if (problem != null) {
      showAppNotice(problem, error: true);
      return;
    }
    final row = _progress?.rejectedPages.where((p) => p.pageId == pageId).firstOrNull ?? _replacements[pageId]?.row;
    setState(() => _replacements[pageId] = _Replacement('uploading', row));
    final r = await _api.replacePage(widget.examId, pageId, files.first);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _replacements.remove(pageId));
      showAppNotice(omrErrorText(r), error: true);
      return;
    }
    final res = OmrReplaceResult.fromJson(r.map);
    if (!res.accepted) {
      final why = [res.refusal, ...?res.result?.tipTexts.where((x) => !res.refusal.contains(x)).take(1)].join(' ');
      if (row == null) {
        // a paper read in part keeps its card: the refusal is said, the card offers Replace again
        setState(() => _replacements.remove(pageId));
        showAppNotice(why, error: true);
        return;
      }
      setState(() => _replacements[pageId] = _Replacement('refused', row)..text = why);
      return;
    }
    // a page read in part has no rejected row to carry the outcome: say it here
    if (row == null && res.text.isNotEmpty) showAppNotice(res.text);
    setState(() {
      _replacements[pageId] = _Replacement('processing', row)
        ..newPageId = res.pageId
        ..text = res.text;
      if (res.progress != null) _progress = res.progress;
      _settled = res.progress?.finished ?? false;
    });
    if (_watch?.running ?? false) {
      _watch!.poke();
    } else {
      _watch = null;
      _track();
    }
  }

  /// The papers of the batch that were read (each with its result), "Paper n" by the page's name in the batch (the
  /// one the server's sentences and the papers that need a clearer image use; the batch's order on an older server —
  /// never `page_no`: every photo is its own page 1), with the file name (and "PDF page 4 of scan.pdf" for a PDF's
  /// page) for an upload; the rejected ones are listed apart (with Replace).
  List<OmrPaperRow> _paperRows(OmrBatchProgress p, {required bool camera}) {
    // a paper being replaced stays (with "Checking the new image…") until the gate answers
    final rejected = {for (final r in p.rejectedPages) r.pageId, for (final e in _replacements.entries) if (e.value.state != 'uploading' || e.value.row != null) e.key};
    return [
      for (final (i, pg) in p.pages.indexed)
        if (pg.result != null && pg.result!.tier != OmrTier.reject && !rejected.contains(pg.pageId))
          OmrPaperRow(
              pageId: pg.pageId,
              label: omrPaperText(pg.label.isEmpty ? '${i + 1}' : pg.label),
              fileName: camera ? null : omrFilePlace(pg.fileName, pg.pageFilePage),
              result: pg.result!,
              replacing: _replacements[pg.pageId]?.state == 'uploading'),
    ];
  }

  /// "7" of the paper [pageId], as its card says it ("Paper 7"): the Replace sheet says which paper it replaces.
  String? _pageLabelOf(int pageId) {
    final p = _progress;
    if (p == null) return null;
    final r = p.rejectedPages.where((x) => x.pageId == pageId).firstOrNull ?? _replacements[pageId]?.row;
    if (r != null) return r.label.isEmpty ? '${r.pageNo}' : r.label;
    final i = p.pages.indexWhere((x) => x.pageId == pageId);
    if (i < 0) return null;
    final pg = p.pages[i];
    // the batch's order when an older server sent no name (never page_no: every photo is its own page 1)
    return pg.label.isEmpty ? '${i + 1}' : pg.label;
  }

  /// The improved photo of a page; a rejected one, or one read in part (`retake`: the server lets a better photo
  /// supersede the partial read), can be replaced from there.
  Future<void> _preview(int pageId, OmrPageResult result) async {
    final canReplace = (_progress?.rejectedPages.any((p) => p.pageId == pageId) ?? false) || result.tier == OmrTier.retake;
    final again = await showOmrPreview(context,
        result: result,
        load: () => _api.image(result.previewUrl),
        retake: canReplace && _replacements[pageId] == null,
        retakeLabel: t('استبدال هذه الورقة', 'Replace this paper'));
    if (again && mounted) await _replace(pageId);
  }

  /// The batch's rejected pages, plus the ones replaced here (gone from the server's list, kept with the outcome).
  List<OmrRejectedPage> _rejectedRows(OmrBatchProgress p) {
    final listed = {for (final r in p.rejectedPages) r.pageId};
    return [
      ...p.rejectedPages,
      for (final e in _replacements.entries)
        if (!listed.contains(e.key) && e.value.row != null) e.value.row!,
    ];
  }

  Future<void> _more() async {
    if (widget.camera) {
      Navigator.of(context).maybePop();
      return;
    }
    await startOmrUpload(context,
        examId: widget.examId,
        examTitle: widget.examTitle,
        api: widget.api,
        picker: widget.picker,
        replace: true,
        sources: widget.sources,
        platform: widget.platform);
  }

  /// "Choose other files" on the summary: the sheet again, without the camera (this screen is the upload's).
  Future<void> _chooseAgain() async {
    final pick = await showScanSourceSheet(context, platform: widget.platform, picker: widget.sources);
    if (pick == null || !mounted) return;
    setState(() {
      _plan = pick.plan();
      _source = pick.source;
    });
  }

  Widget _body() {
    final c = context.colors;
    final plan = _plan;
    if (plan != null) {
      return ScanPickSummary(plan: plan, source: _source, onUpload: () => _upload(plan.files), onChooseAgain: _chooseAgain);
    }
    final up = _up;
    if (up != null && up.phase == ScanUploadPhase.sending && _batchId == null) {
      return ScanUploadProgress(done: up.finished, total: up.runTotal, current: up.current);
    }
    if (up != null && up.phase == ScanUploadPhase.done && !up.anySent) {
      // nothing went: the reasons, Retry, other files
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ScanUploadFailures(failures: up.failures, onRetry: _retry),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton.icon(
          key: const ValueKey('scan.other'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
          onPressed: _more,
          icon: const Icon(Icons.upload_file_rounded),
          label: Text(t('اختيار ملفات أخرى', 'Choose other files')),
        ),
      ]);
    }
    // some went: the batch below; a retry running, or what did not go, above it
    final sendingMore = up != null && up.phase == ScanUploadPhase.sending;
    final failed = up != null && up.phase == ScanUploadPhase.done && up.failures.isNotEmpty;
    final head = <Widget>[
      if (sendingMore) ...[ScanUploadProgress(done: up.finished, total: up.runTotal, current: up.current), const SizedBox(height: AppSpace.md)],
      if (failed) ...[ScanUploadFailures(failures: up.failures, onRetry: _retry), const SizedBox(height: AppSpace.md)],
    ];
    final p = _progress;
    if (p == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...head,
        if (_loadError != null) AppBanner(icon: Icons.error_outline_rounded, text: _loadError!, color: c.danger) else const AppListSkeleton(items: 2),
      ]);
    }
    final review = OmrRoutes.review == null ? null : () => openOmrReview(context, widget.examId);
    final results = OmrRoutes.results == null ? null : () => openOmrResults(context, widget.examId);
    final camera = widget.camera || p.kind == 'camera';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...head,
      if (_nothingNew) ...[
        AppBanner(icon: Icons.info_outline_rounded, text: t('كل هذه الصفحات مرفوعة من قبل — لم يُضف شيء جديد', 'All of these pages were uploaded before — nothing new was added')),
        const SizedBox(height: AppSpace.sm),
      ],
      ScanProgressView(
        headline: p.text,
        done: p.done,
        total: p.total,
        finished: p.finished,
        graded: p.graded,
        review: p.review,
        rejected: p.rejected,
        failed: p.failed,
        duplicates: _duplicates,
        camera: camera,
        rejectedPages: [
          for (final r in _rejectedRows(p))
            RejectedPageRow(
              pageId: r.pageId,
              // "Paper 3", like the read papers under it (the server's own sentence, when shown, says "Page 3")
              label: omrPaperText(r.label.isEmpty ? '${r.pageNo}' : r.label),
              text: r.text,
              instruction: r.instruction,
              fileName: omrFilePlace(r.fileName, r.pageFilePage),
              replacement: _replacements[r.pageId]?.state,
              replacementText: _replacements[r.pageId]?.text,
              result: r.result,
            ),
        ],
        papers: _paperRows(p, camera: camera),
        onReplace: _replace,
        onPreview: _preview,
        onReview: review,
        onResults: results,
        onMore: _more,
      ),
      if (!_issues.isEmpty) ...[
        const SizedBox(height: AppSpace.md),
        OmrIssuesCard(issues: _issues, onOpen: _openIssue, onReplace: (i) => _replace(i.pageId!)),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('exam.omr.progress'),
      appBar: AppHeader(title: widget.camera ? t('الأوراق المصوّرة', 'Captured papers') : t('معالجة الأوراق', 'Processing papers')),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [_body()]),
        ),
      ),
    );
  }
}

/// The camera screen's "Upload instead": one tap to open the file dialog (a user gesture, needed on the web).
class _PickFirst extends StatelessWidget {
  const _PickFirst({required this.examId, required this.examTitle, this.api});
  final int examId;
  final String examTitle;
  final OmrScanApi? api;

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('exam.omr.pick'),
      appBar: AppHeader(title: t('رفع الأوراق', 'Upload papers')),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: AppEmpty(
            icon: Icons.upload_file_rounded,
            title: t('ارفع صور الأوراق أو ملفات PDF', 'Upload photos of the papers or PDFs'),
            message: t('من معرض الصور أو الملفات أو مجلد الماسح الضوئي — صور وملفات PDF معًا، حتى 25 ميجابايت للملف',
                "From the photo gallery, files or a scanner's folder — images and PDFs together, up to 25 MB a file"),
            actionLabel: t('اختيار الصفحات', 'Choose the pages'),
            // the camera is what brought the teacher here (it failed, or they chose to upload): no camera in the sheet
            onAction: () => startOmrUpload(context, examId: examId, examTitle: examTitle, api: api, replace: true, camera: false),
          ),
        ),
      ),
    );
  }
}
