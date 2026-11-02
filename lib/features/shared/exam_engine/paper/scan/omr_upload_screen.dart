// Bulk upload of bubble sheets (brief 3.3 / 3.4, Example 5): images (JPG / PNG / WebP) and PDFs through the exam's
// existing scan intake (`POST …/scans` routes a bubble exam's pages to the OMR pipeline), then "X of N papers
// processed" fed by the uploader's live event `job_updated {kind: omr_scan, id: batch}` through EventOrPoll (a slow
// poll only as the fallback), the rejected pages with the server's own sentence ("Page 7 is too blurry. Please
// upload a clearer image of it.") and "Replace this page". The camera's session lands on the same screen.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show t;
import 'omr_routes.dart';
import 'omr_scan.dart';
import 'omr_scan_widgets.dart';

/// Picks files: several (an upload) or one (a replacement). Tests hand their own.
typedef OmrFilePicker = Future<List<(String, Uint8List)>> Function({bool many});

Future<List<(String, Uint8List)>> omrPickFiles({bool many = true}) async {
  final picked = many
      ? await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: omrUploadExtensions)
      : [?await FilePicker.pickFile(type: FileType.custom, allowedExtensions: omrUploadExtensions)];
  final out = <(String, Uint8List)>[];
  for (final f in picked) {
    try {
      out.add((f.name, await f.readAsBytes()));
    } catch (_) {}
  }
  return out;
}

/// "Upload images / PDF": picks inside the tap (a browser opens the file dialog only on a user gesture), checks the
/// limits, then opens the progress screen, which sends them.
Future<void> startOmrUpload(BuildContext context,
    {required int examId, String examTitle = '', OmrScanApi? api, OmrFilePicker? picker, bool replace = false}) async {
  final nav = Navigator.of(context);
  final files = await (picker ?? omrPickFiles)(many: true);
  if (files.isEmpty) return;
  final problem = omrPickProblem(files);
  if (problem != null) {
    showAppNotice(problem, error: true);
    return;
  }
  final route = MaterialPageRoute<void>(
      builder: (_) => OmrScanProgressScreen(examId: examId, examTitle: examTitle, files: files, api: api, picker: picker));
  if (replace) {
    await nav.pushReplacement(route);
  } else {
    await nav.push(route);
  }
}

class _Replacement {
  _Replacement(this.state, {this.batchId});
  String state; // uploading · processing · processed · review · rejected · failed
  int? batchId;
  String? text;
}

class OmrScanProgressScreen extends StatefulWidget {
  const OmrScanProgressScreen({
    super.key,
    required this.examId,
    this.examTitle = '',
    this.batchId,
    this.files,
    this.camera = false,
    this.api,
    this.picker,
    this.liveBus,
    this.liveStream,
  }) : assert(batchId != null || files != null);

  /// The camera's "Upload instead" (picks first, see [startOmrUpload]).
  static Widget pick({required int examId, String examTitle = '', OmrScanApi? api}) => _PickFirst(examId: examId, examTitle: examTitle, api: api);

  final int examId;
  final String examTitle;

  /// An existing batch (the camera session, an earlier upload) …
  final int? batchId;

  /// … or files to upload now.
  final List<(String, Uint8List)>? files;
  final bool camera;
  final OmrScanApi? api;
  final OmrFilePicker? picker;
  final LiveEvents? liveBus;
  final LiveStreamHandle? liveStream;

  @override
  State<OmrScanProgressScreen> createState() => _OmrScanProgressScreenState();
}

class _OmrScanProgressScreenState extends State<OmrScanProgressScreen> {
  late final OmrScanApi _api = widget.api ?? OmrScanApi();
  bool _uploading = false;
  String? _uploadError;
  int? _batchId;
  int _duplicates = 0;
  bool _nothingNew = false;
  OmrBatchProgress? _progress;

  /// A FETCHED answer said done (the live event's "done" alone still needs the fetch: counts + rejected pages).
  bool _settled = false;
  String? _loadError;
  final Map<int, _Replacement> _replacements = {};
  EventOrPoll? _watch;

  @override
  void initState() {
    super.initState();
    _batchId = widget.batchId;
    if (widget.files != null) {
      _upload(widget.files!);
    } else {
      _track();
    }
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _upload(List<(String, Uint8List)> files) async {
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    final r = await _api.upload(widget.examId, files);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _uploading = false;
        _uploadError = omrErrorText(r);
      });
      return;
    }
    final u = OmrUploadReply.fromJson(r.map);
    setState(() {
      _uploading = false;
      _batchId = u.batchId;
      _duplicates = u.duplicates;
      _nothingNew = u.pages.isEmpty;
    });
    _track();
  }

  /// Batches still being read: the main one and the replacements in flight.
  Set<String> get _open => {
        if (_batchId != null && !_settled) '$_batchId',
        for (final r in _replacements.values)
          if (r.batchId != null && r.state == 'processing') '${r.batchId}',
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
      },
      bus: widget.liveBus,
      stream: widget.liveStream,
    )..start(pollNow: true);
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
        if (p.batchId == _batchId) {
          // a read older than the live event already shown never moves the count back
          final cur = _progress;
          if (cur == null || p.finished || p.done >= cur.done) _progress = p;
          if (p.finished) _settled = true;
        } else {
          for (final rep in _replacements.values) {
            if (rep.batchId == p.batchId && p.finished) _settle(rep, p);
          }
        }
      });
    }
    if (_open.isEmpty) _watch?.stop();
  }

  void _settle(_Replacement rep, OmrBatchProgress p) {
    if (p.graded > 0) {
      rep.state = 'processed';
    } else if (p.review > 0) {
      rep.state = 'review';
    } else if (p.rejected > 0) {
      rep.state = 'rejected';
      rep.text = p.rejectedPages.isEmpty ? null : p.rejectedPages.first.text;
    } else if (p.failed > 0) {
      rep.state = 'failed';
    } else {
      rep.state = 'processed';
    }
  }

  Future<void> _replace(int pageId) async {
    final files = await (widget.picker ?? omrPickFiles)(many: false);
    if (files.isEmpty || !mounted) return;
    final problem = omrPickProblem(files);
    if (problem != null) {
      showAppNotice(problem, error: true);
      return;
    }
    setState(() => _replacements[pageId] = _Replacement('uploading'));
    final r = await _api.upload(widget.examId, files.take(1).toList());
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _replacements.remove(pageId));
      showAppNotice(omrErrorText(r), error: true);
      return;
    }
    final u = OmrUploadReply.fromJson(r.map);
    if (u.pages.isEmpty) {
      setState(() => _replacements.remove(pageId));
      showAppNotice(t('هذه الصورة مرفوعة من قبل — اختر صورة أخرى أوضح', 'This image was already uploaded — choose another, clearer one'), error: true);
      return;
    }
    setState(() => _replacements[pageId] = _Replacement('processing', batchId: u.batchId));
    if (_watch?.running ?? false) {
      _watch!.poke();
    } else {
      _watch = null;
      _track();
    }
  }

  Future<void> _more() async {
    if (widget.camera) {
      Navigator.of(context).maybePop();
      return;
    }
    await startOmrUpload(context, examId: widget.examId, examTitle: widget.examTitle, api: widget.api, picker: widget.picker, replace: true);
  }

  Widget _body() {
    final c = context.colors;
    if (_uploading) {
      final n = widget.files?.length ?? 0;
      return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('جارٍ رفع $n ملف…', 'Uploading $n file${n == 1 ? '' : 's'}…'), style: appText(17, w: FontWeight.w800, c: c.textDark)),
          const SizedBox(height: AppSpace.xs),
          Text(t('ابقَ على هذه الصفحة حتى يكتمل الرفع', 'Stay on this page until the upload finishes'), style: appText(13, c: c.textMedium)),
          const SizedBox(height: AppSpace.md),
          ClipRRect(borderRadius: BorderRadius.circular(AppRadius.chip), child: const LinearProgressIndicator(minHeight: 8)),
        ]),
      );
    }
    if (_uploadError != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppBanner(icon: Icons.error_outline_rounded, text: _uploadError!, color: c.danger),
        const SizedBox(height: AppSpace.md),
        if (widget.files != null)
          AppPrimaryButton(label: t('إعادة المحاولة', 'Try again'), icon: Icons.refresh_rounded, onPressed: () => _upload(widget.files!)),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
          onPressed: _more,
          icon: const Icon(Icons.upload_file_rounded),
          label: Text(t('اختيار ملفات أخرى', 'Choose other files')),
        ),
      ]);
    }
    final p = _progress;
    if (p == null) {
      if (_loadError != null) return AppBanner(icon: Icons.error_outline_rounded, text: _loadError!, color: c.danger);
      return const AppListSkeleton(items: 2);
    }
    final review = OmrRoutes.review == null ? null : () => openOmrReview(context, widget.examId);
    final results = OmrRoutes.results == null ? null : () => openOmrResults(context, widget.examId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
        camera: widget.camera || p.kind == 'camera',
        rejectedPages: [
          for (final r in p.rejectedPages)
            RejectedPageRow(
              pageId: r.pageId,
              text: r.text,
              instruction: r.instruction,
              fileName: r.fileName,
              replacement: _replacements[r.pageId]?.state,
              replacementText: _replacements[r.pageId]?.text,
            ),
        ],
        onReplace: _replace,
        onReview: review,
        onResults: results,
        onMore: _more,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('exam.omr.progress'),
      appBar: AppBar(title: Text(widget.camera ? t('الأوراق المصوّرة', 'Captured papers') : t('معالجة الأوراق', 'Processing papers'))),
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
      appBar: AppBar(title: Text(t('رفع الأوراق', 'Upload papers'))),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: AppEmpty(
            icon: Icons.upload_file_rounded,
            title: t('ارفع صور الأوراق أو ملفات PDF', 'Upload photos of the papers or PDFs'),
            message: t('JPG أو PNG أو WebP أو PDF — حتى ${OmrLimits.maxFiles} ملفًا و ${OmrLimits.maxPages} صفحة في المرة',
                'JPG, PNG, WebP or PDF — up to ${OmrLimits.maxFiles} files and ${OmrLimits.maxPages} pages at a time'),
            actionLabel: t('اختيار الملفات', 'Choose files'),
            onAction: () => startOmrUpload(context, examId: examId, examTitle: examTitle, api: api, replace: true),
          ),
        ),
      ),
    );
  }
}
