// The scan-to-result loop's paper (Exam Hub, F4): the real photo, every answer marked on it, the total large, the arrows
// walking the batch. Grading is never waited for: Next and the camera always work while a paper is being read.
// The reading is awaited on one JobWatch over the batch's `job_updated` (page_id, page_status), with its slow poll only
// while the stream is down; a sheet is read once when its page is final. A photo stays in memory for the last few papers.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../exam_scan_review.dart' show ExamScansScreen;
import '../../paper/review/omr_review_page.dart' show OmrPaperPage, OmrReviewPage;
import '../../paper/scan/omr_scan.dart';
import 'sheet_models.dart';
import 'sheet_review_parts.dart';

/// How the person left the paper.
enum SheetExitKind { nextPaper, retake, finish }

class SheetExit {
  const SheetExit(this.kind, [this.pageId]);
  final SheetExitKind kind;

  /// [SheetExitKind.retake]: the page to replace.
  final int? pageId;
}

/// The paper screen on the navigator; null when the person just went back.
Future<SheetExit?> openSheetReview(
  BuildContext context, {
  required int examId,
  required String examTitle,
  required int batchId,
  int? pageId,
  Uint8List? photo,
  bool canShoot = true,
  bool suggestRetake = false,
}) =>
    Navigator.of(context).push<SheetExit>(PageRouteBuilder<SheetExit>(
      opaque: true,
      transitionDuration: AppMotion.of(context).base,
      reverseTransitionDuration: AppMotion.of(context).fast,
      pageBuilder: (_, _, _) => SheetReviewScreen(
          examId: examId, examTitle: examTitle, batchId: batchId, pageId: pageId, photo: photo, canShoot: canShoot, suggestRetake: suggestRetake),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));

class SheetReviewScreen extends StatefulWidget {
  const SheetReviewScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    required this.batchId,
    this.pageId,
    this.photo,
    this.canShoot = true,
    this.suggestRetake = false,
    this.api,
    this.scanApi,
    this.liveBus,
    this.liveStream,
  });

  final int examId;
  final String examTitle;
  final int batchId;

  /// The paper to open; the batch's first when null.
  final int? pageId;

  /// The shot just taken, shown until the server's image arrives.
  final Uint8List? photo;

  /// The exam can be shot with the camera (a teacher's own sheet cannot): Next on the last student opens it.
  final bool canShoot;

  /// The reading suggested a clearer photo of [pageId].
  final bool suggestRetake;
  final SheetApi? api;
  final OmrScanApi? scanApi;
  final LiveEvents? liveBus;
  final LiveStreamHandle? liveStream;

  @override
  State<SheetReviewScreen> createState() => _SheetReviewScreenState();
}

class _SheetReviewScreenState extends State<SheetReviewScreen> {
  late final SheetApi _api = widget.api ?? SheetApi();
  late final OmrScanApi _scan = widget.scanApi ?? OmrScanApi();
  late final JobWatch _watch = JobWatch(kind: kOmrScanJobKind, id: '${widget.batchId}', bus: widget.liveBus, stream: widget.liveStream);

  List<SheetRow> _rows = const [];
  int _index = 0;
  final Map<int, SheetView> _views = {};
  final Map<int, Uint8List> _photos = {};
  final Set<int> _serverPhoto = {};
  String? _error;
  bool _notBubble = false;
  bool _closed = false;
  int? _focusN;
  DateTime _lastRows = DateTime.fromMillisecondsSinceEpoch(0);

  int? get _pageId => _rows.isEmpty ? widget.pageId : _rows[_index].pageId;
  SheetView? get _view => _pageId == null ? null : _views[_pageId!];

  @override
  void initState() {
    super.initState();
    if (widget.pageId != null && widget.photo != null) _remember(widget.pageId!, widget.photo!);
    unawaited(_start());
  }

  @override
  void dispose() {
    _closed = true;
    _watch.dispose();
    super.dispose();
  }

  void _remember(int pageId, Uint8List bytes) {
    _photos.remove(pageId);
    _photos[pageId] = bytes;
    while (_photos.length > 8) {
      _photos.remove(_photos.keys.first);
    }
  }

  Future<void> _start() async {
    await _loadRows();
    if (!mounted) return;
    await _openCurrent();
    await _watchLoop();
  }

  Future<void> _loadRows() async {
    final r = await _api.sheets(widget.examId, widget.batchId);
    _lastRows = DateTime.now();
    if (!mounted || !r.ok) return;
    final rows = sheetRowsOf(r.map);
    if (rows.isEmpty) return; // a just-created batch may not be listed yet: the arrows wait for the next read
    final keep = _pageId;
    final hasIt = rows.indexWhere((x) => x.pageId == keep);
    setState(() {
      _rows = rows;
      _index = hasIt >= 0 ? hasIt : sheetIndexOf(rows, widget.pageId);
    });
  }

  Future<void> _openCurrent() async {
    final id = _pageId;
    if (id == null) return;
    if (_views[id]?.ready == true) {
      await _loadPhoto(_views[id]!);
      return;
    }
    await _readSheet(id);
  }

  /// One read of the sheet; called when it opens and when its page turned final.
  Future<void> _readSheet(int pageId) async {
    final r = await _api.sheet(widget.examId, pageId);
    if (!mounted) return;
    if (!r.ok) {
      if (r.code == 'exam_not_bubble') {
        setState(() => _notBubble = true);
      } else if (pageId == _pageId) {
        setState(() => _error = omrErrorText(r));
      }
      return;
    }
    final v = SheetView.fromJson(r.map);
    setState(() {
      _views[pageId] = v;
      if (pageId == _pageId) _error = null;
      final i = _rows.indexWhere((x) => x.pageId == pageId);
      if (i >= 0 && v.ready) {
        final rows = [..._rows];
        rows[i] = rows[i].copyWith(status: v.status, studentName: v.studentName, score: v.score, max: v.max);
        _rows = rows;
      }
    });
    if (v.ready) await _loadPhoto(v);
  }

  Future<void> _loadPhoto(SheetView v) async {
    // the boxes are measured on the server's image: it takes over from the local shot once, then stays cached
    if (_photos[v.pageId] != null && _serverPhoto.contains(v.pageId)) return;
    final bytes = await _scan.image(v.imageUrl);
    if (!mounted || bytes == null) return;
    _serverPhoto.add(v.pageId);
    setState(() => _remember(v.pageId, bytes));
  }

  /// The batch's events: a page turning final is read once when it is the one on screen; while the stream is down
  /// [JobWatch.next] comes back empty on its slow pace and only then a waiting paper is read again.
  Future<void> _watchLoop() async {
    while (mounted && !_closed) {
      final e = await _watch.next(const Duration(seconds: 4), fallbackEvery: const Duration(seconds: 20));
      if (!mounted || _closed) return;
      final pid = e == null ? null : int.tryParse('${e.data['page_id'] ?? ''}');
      final status = '${e?.data['page_status'] ?? ''}';
      final cur = _pageId;
      final waiting = cur != null && _views[cur]?.ready != true && !(_views[cur]?.dead ?? false);
      if (e == null) {
        if (waiting) await _readSheet(cur);
        continue;
      }
      if (pid != null && pid == cur && sheetEventIsFinal(status)) {
        await _readSheet(pid);
      } else if (pid != null && sheetEventIsFinal(status) && DateTime.now().difference(_lastRows) > const Duration(seconds: 3)) {
        await _loadRows(); // another paper of the batch was graded: its name and degree for the arrows
      }
    }
  }

  Future<void> _go(int delta) async {
    final next = _index + delta;
    if (next < 0 || next >= _rows.length) return;
    setState(() {
      _index = next;
      _focusN = null;
      _error = null;
    });
    await _openCurrent();
  }

  void _next() {
    if (sheetNextOpensCamera(_index, _rows.length)) {
      Navigator.of(context).pop(const SheetExit(SheetExitKind.nextPaper));
    } else {
      _go(1);
    }
  }

  void _finish() => Navigator.of(context).pop(const SheetExit(SheetExitKind.finish));

  void _retake() => Navigator.of(context).pop(SheetExit(SheetExitKind.retake, _pageId));

  /// A question: the paper page, on that question, where its review item is one tap away. A picked item opens the review
  /// queue on it; anything changed is read again.
  Future<void> _correct(int n) async {
    final id = _pageId;
    if (id == null) return;
    setState(() => _focusN = n);
    await _openPaper(id, n);
  }

  Future<void> _openPaper(int pageId, int? n) async {
    final nav = Navigator.of(context);
    final picked = await nav.push<int>(MaterialPageRoute<int>(builder: (_) => OmrPaperPage(examId: widget.examId, pageId: pageId, focusN: n)));
    if (picked != null && mounted) {
      await nav.push<void>(MaterialPageRoute<void>(builder: (_) => OmrReviewPage(examId: widget.examId, initialItemId: picked)));
    }
    if (!mounted) return;
    _views.remove(pageId);
    await _readSheet(pageId);
  }

  @override
  Widget build(BuildContext context) {
    final id = _pageId;
    final v = _view;
    final isFirst = _index <= 0;
    final count = _rows.length;
    final lastOpensCamera = sheetNextOpensCamera(_index, count);
    final name = _rows.isNotEmpty ? (_rows[_index].studentName ?? t('تُقرأ الورقة', 'Reading this paper')) : t('تُقرأ الورقة', 'Reading this paper');
    final position = count == 0 ? null : t('الورقة ${_index + 1} من $count', 'Paper ${_index + 1} of $count');
    final canRetake = widget.canShoot && id != null && ((v?.dead ?? false) || (widget.suggestRetake && id == widget.pageId));
    return Scaffold(
      body: SheetReviewView(
        waitingName: name,
        view: v,
        photo: id == null ? null : _photos[id],
        position: position,
        error: _error,
        notBubble: _notBubble,
        focusN: _focusN,
        onBack: () => Navigator.of(context).maybePop(),
        onPrev: isFirst ? null : () => _go(-1),
        onNext: lastOpensCamera && !widget.canShoot ? null : _next,
        nextIsCamera: lastOpensCamera && widget.canShoot,
        onFinish: _finish,
        onQuestion: _correct,
        onReview: id == null ? null : () => _openPaper(id, null),
        onRetake: canRetake ? _retake : null,
        onRetry: id == null ? null : () => _readSheet(id),
        onWritten: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => ExamScansScreen(examId: widget.examId, examTitle: widget.examTitle))),
      ),
    );
  }
}
