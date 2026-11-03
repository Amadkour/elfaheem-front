// The camera scanner (brief 3.1 / 3.2, D-159): a large guide with corner guides over the live picture, the server's
// own guidance from `POST …/omr/live-hint` on small frames at a modest rate (backing off on 503 omr_busy), an
// automatic capture once the hint says ready for a short steady run, the full photo checked by `POST …/omr/capture`:
// accepted → "Paper 12 of 40 captured" and the next sheet; rejected → the exact reason + a big Retake, nothing graded.
// Smart photos: a hint with `blocking: false` ("Add a little more light") is a soft tip and the frame may still be
// captured; the capture's `result` speaks per paper ("Read successfully" / "Read with 3 questions to review" / "Read
// in part" + a Retake that is only a suggestion / "Couldn't read" + reason + tip), with a thumbnail of the improved
// photo (its `preview_url` through the signed-image call) that opens the preview with Retake. Retake of a paper read
// in part (or a rejected one the server kept) sends the next shot to `POST …/omr/pages/{page_id}/replace`: the new
// photo supersedes the partial read (a new capture would be the same student twice). 409 (`page_reviewed`: the teacher
// already resolved items on it; an older server's `page_not_rejected`) keeps the page: its sentence, then the shot
// goes on as a new paper only if the teacher says so.
// The manual shutter always works; torch / switch where the camera has them; a dead camera shows the fix and a way
// out (upload instead). Phones and browsers (omr_camera.dart).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../../../admin/admin_common.dart' show t;
import '../../exam_engine_api.dart' show EngineResult;
import 'omr_camera.dart';
import 'omr_paper_result.dart';
import 'omr_scan.dart';
import 'omr_scan_widgets.dart';
import 'omr_upload_screen.dart';
import '../omr_counts.dart';

/// How long a capture's card stays before the next sheet (null: until the person acts): an older server's accepted
/// photo and a clean read briefly, a read with questions to review a little longer, a suggested retake until chosen.
Duration? omrResultStays(OmrPageResult? r) => switch (r?.tier) {
      null || OmrTier.accept => const Duration(milliseconds: 2600),
      OmrTier.flags => const Duration(milliseconds: 4500),
      OmrTier.retake || OmrTier.reject => null,
    };

class OmrScannerScreen extends StatefulWidget {
  const OmrScannerScreen({super.key, required this.examId, this.examTitle = '', this.camera, this.api, this.clock});

  final int examId;
  final String examTitle;

  /// The camera to use (tests hand a fake); the platform's by default.
  final OmrCamera Function()? camera;
  final OmrScanApi? api;
  final DateTime Function()? clock;

  @override
  State<OmrScannerScreen> createState() => _OmrScannerScreenState();
}

class _OmrScannerScreenState extends State<OmrScannerScreen> with WidgetsBindingObserver {
  late final OmrScanApi _api = widget.api ?? OmrScanApi();
  late final DateTime Function() _now = widget.clock ?? DateTime.now;
  final _gate = AutoCaptureGate();
  final _pacer = HintPacer();

  OmrCamera? _cam;
  bool _starting = true;
  OmrCameraIssue? _issue;
  int _gen = 0; // the hint loop's generation: a new one stops the old

  OmrLiveHint? _hint;
  String? _note; // busy / network line instead of a hint
  String? _setupProblem; // the exam cannot be scanned (409 readiness)

  bool _capturing = false;
  OmrCaptureResult? _result;
  Timer? _hideResult;

  /// The improved photo of [_result] (its `preview_url`), and the preview sheet being open (the hints wait).
  Uint8List? _previewBytes;
  bool _previewLoading = false;
  bool _previewOpen = false;

  /// Retake chosen on a paper the server kept: the next shot replaces this page (null: a new paper).
  int? _replaceTarget;

  /// A question is open over the camera (send a refused retake as a new paper?): the hints wait.
  bool _asking = false;

  int? _batchId;
  int? _expected;
  int _captured = 0;
  bool _auto = true;
  bool _paused = false;

  bool get _holding => _capturing || _paused || _previewOpen || _asking || (_result?.blocks ?? false) || _setupProblem != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gen++;
    _hideResult?.cancel();
    final cam = _cam;
    _cam = null;
    if (cam != null) unawaited(cam.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return; // the browser keeps the stream; a hidden tab simply sends nothing
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _paused = true;
      _gen++;
      final cam = _cam;
      _cam = null;
      if (cam != null) unawaited(cam.dispose());
    } else if (state == AppLifecycleState.resumed && _paused) {
      _paused = false;
      _start();
    }
  }

  Future<void> _start({bool front = false}) async {
    _starting = true;
    _issue = null;
    // a retry from the problem view shows "Starting the camera…" at once (a microtask: also called from initState)
    Future.microtask(() {
      if (mounted) setState(() {});
    });
    final old = _cam; // a camera opened while the app was going to the background
    _cam = null;
    _gen++;
    if (old != null) await old.dispose();
    final cam = (widget.camera ?? createOmrCamera)();
    try {
      await cam.open(front: front);
    } on OmrCameraException catch (e) {
      await cam.dispose();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _issue = e.issue;
      });
      return;
    } catch (_) {
      await cam.dispose();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _issue = OmrCameraIssue.failed;
      });
      return;
    }
    if (!mounted) {
      await cam.dispose();
      return;
    }
    setState(() {
      _cam = cam;
      _starting = false;
      _hint = null;
    });
    _gate.reset();
    final gen = ++_gen;
    unawaited(_hints(gen));
  }

  Future<void> _wait(Duration d, int gen) async {
    var left = d;
    const step = Duration(milliseconds: 100);
    while (left > Duration.zero && mounted && gen == _gen) {
      final s = left < step ? left : step;
      await Future<void>.delayed(s);
      left -= s;
    }
  }

  /// The live-hint loop: one frame at a time, the next one booked by [HintPacer].
  Future<void> _hints(int gen) async {
    String? prev;
    while (mounted && gen == _gen) {
      final cam = _cam;
      if (cam == null) return;
      if (_holding) {
        prev = null; // steadiness starts over after a capture / a pause
        await _wait(const Duration(milliseconds: 200), gen);
        continue;
      }
      final sw = Stopwatch()..start();
      final f = await cam.frame(maxSide: 640);
      if (!mounted || gen != _gen) return;
      if (f == null || f.jpeg.length > OmrLimits.hintMaxBytes) {
        await _wait(_pacer.afterError(), gen);
        continue;
      }
      final r = await _api.liveHint(widget.examId, f.jpeg, prev: prev);
      if (!mounted || gen != _gen) return;
      if (_holding) continue; // a shutter press while the frame was out: this answer is about the old picture
      Duration wait;
      if (r.ok) {
        final h = OmrLiveHint.fromJson(r.map, frameW: f.width, frameH: f.height);
        prev = h.stat;
        final fire = _auto && _gate.feed(h, _now());
        setState(() {
          _hint = h;
          _note = null;
        });
        if (fire) unawaited(_shoot());
        wait = _pacer.afterOk(sw.elapsed);
      } else if (r.code == 'omr_busy' || r.status == 503) {
        setState(() => _note = omrErrorText(r));
        wait = _pacer.afterBusy(retryAfterOf(r));
      } else if (r.status == 429) {
        setState(() => _note = omrErrorText(r));
        wait = _pacer.afterRateLimit(retryAfterOf(r));
      } else if (omrIsSetupProblem(r.code) || r.status == 403) {
        setState(() => _setupProblem = omrErrorText(r));
        return;
      } else {
        prev = null;
        setState(() => _note = omrErrorText(r));
        wait = _pacer.afterError();
      }
      await _wait(wait, gen);
    }
  }

  Future<void> _shoot() async {
    final cam = _cam;
    if (_capturing || cam == null || _setupProblem != null) return;
    _hideResult?.cancel();
    setState(() {
      _capturing = true;
      _result = null;
      _previewBytes = null;
      _previewLoading = false;
    });
    _gate.captured();
    final photo = await cam.photo();
    if (!mounted) return;
    if (photo == null || photo.isEmpty) {
      setState(() => _capturing = false);
      _gate.reset();
      showAppNotice(t('تعذّر التقاط الصورة — حاول مرة أخرى', 'The photo could not be taken — try again'), error: true);
      return;
    }
    final target = _replaceTarget;
    if (target != null) return _replaceShot(target, photo);
    await _captureShot(photo);
  }

  /// A new paper: `POST …/omr/capture`.
  Future<void> _captureShot(Uint8List photo) async {
    // the count goes with every photo: changed mid-session, the server keeps the new one (its answer used to put the old back)
    final r = await _api.capture(widget.examId, photo, batchId: _batchId, expected: _expected);
    if (!mounted) return;
    if (!r.ok) return _captureFailed(r);
    _show(OmrCaptureResult.fromJson(r.map));
  }

  /// The retake of a kept paper: `POST …/omr/pages/{page_id}/replace` — the answer's result is shown like a capture's
  /// (the count does not move: it is the same paper).
  Future<void> _replaceShot(int pageId, Uint8List photo) async {
    final r = await _api.replacePage(widget.examId, pageId, (photoNameOf(photo), photo));
    if (!mounted) return;
    if (!r.ok) {
      if (r.status == 409) return _replaceRefused(r, photo);
      return _captureFailed(r); // busy / network: the retake stays aimed at the same page
    }
    final rep = OmrReplaceResult.fromJson(r.map);
    if (rep.accepted) _replaceTarget = null; // the new page is that paper now
    _show(OmrCaptureResult(
      accepted: rep.accepted,
      code: rep.code,
      en: rep.accepted ? rep.en : (rep.pageEn.isNotEmpty ? rep.pageEn : rep.en),
      ar: rep.accepted ? rep.ar : (rep.pageAr.isNotEmpty ? rep.pageAr : rep.ar),
      pageId: rep.pageId,
      batchId: rep.batchId ?? _batchId,
      captured: _captured,
      expected: _expected,
      issues: rep.issues,
      result: rep.result,
    ));
  }

  /// 409 on a retake: the page stays as it is (the server's sentence); the photo becomes a new paper only on request.
  Future<void> _replaceRefused(EngineResult r, Uint8List photo) async {
    setState(() {
      _replaceTarget = null;
      _capturing = false;
      _asking = true;
    });
    showAppNotice(omrErrorText(r), error: true);
    final asNew = await appConfirm(context,
        message: t('الورقة السابقة تبقى كما هي. هل تُرسل هذه الصورة كورقة جديدة؟', 'The earlier paper stays as it is. Send this photo as a new paper?'),
        confirmLabel: t('إرسالها كورقة جديدة', 'Send as a new paper'));
    if (!mounted) return;
    setState(() {
      _asking = false;
      _capturing = asNew;
    });
    // declined: the camera waits for the next sheet (the gate stays disarmed until the scene changes)
    if (asNew) await _captureShot(photo);
  }

  void _show(OmrCaptureResult res) {
    final url = res.result?.previewUrl;
    setState(() {
      _capturing = false;
      _result = res;
      _previewLoading = url != null;
      if (res.accepted) {
        _batchId = res.batchId ?? _batchId;
        if (res.captured > 0) _captured = res.captured;
        _expected = res.expected ?? _expected;
      }
    });
    if (url != null) unawaited(_loadPreview(res, url));
    if (!res.blocks) {
      unawaited(HapticFeedback.mediumImpact());
      final stay = omrResultStays(res.result);
      if (stay != null) {
        _hideResult = Timer(stay, () {
          if (mounted && _result == res && !_previewOpen) setState(() => _result = null);
        });
      }
    } else {
      unawaited(HapticFeedback.heavyImpact());
    }
  }

  Future<void> _loadPreview(OmrCaptureResult res, String url) async {
    final b = await _api.image(url);
    if (!mounted || _result != res) return;
    setState(() {
      _previewBytes = b;
      _previewLoading = false;
    });
  }

  /// The improved photo, full size: Retake from there too. The live hints wait while it is open.
  Future<void> _openPreview() async {
    final res = _result, r = res?.result;
    if (res == null || r == null) return;
    _hideResult?.cancel();
    setState(() => _previewOpen = true);
    final again = await showOmrPreview(context,
        result: r,
        bytes: _previewBytes,
        load: _previewBytes == null ? () => _api.image(r.previewUrl) : null,
        retake: r.wantsRetake || !res.accepted);
    if (!mounted) return;
    setState(() => _previewOpen = false);
    if (again) {
      _retake();
    } else if (_result == res && !res.blocks && r.tier != OmrTier.retake) {
      setState(() => _result = null); // seen: the next sheet
    }
  }

  void _captureFailed(EngineResult r) {
    _gate.reset();
    if (r.code == 'batch_not_found') _batchId = null; // the session is gone: the next photo starts a new one
    setState(() {
      _capturing = false;
      if (omrIsSetupProblem(r.code) || r.status == 403) _setupProblem = omrErrorText(r);
    });
    if (_setupProblem == null) showAppNotice(omrErrorText(r), error: true);
  }

  /// Retake: a paper the server kept (read in part, or a rejected one it stored) is replaced by the next shot; a photo
  /// that stored nothing is simply taken again.
  void _retake() {
    _hideResult?.cancel();
    _gate.reset();
    final res = _result, tier = res?.result?.tier, pid = res?.pageId;
    setState(() {
      if (pid != null && (tier == OmrTier.retake || tier == OmrTier.reject)) _replaceTarget = pid;
      _result = null;
      _previewBytes = null;
      _previewLoading = false;
    });
  }

  /// "Cancel" on the retake pill: the next shot is a new paper again.
  void _cancelRetake() => setState(() => _replaceTarget = null);

  Future<void> _toggleTorch() async {
    final cam = _cam;
    if (cam == null) return;
    await cam.setTorch(!cam.torchOn);
    if (mounted) setState(() {});
  }

  Future<void> _switch() async {
    final cam = _cam;
    if (cam == null) return;
    _gate.reset();
    await cam.switchCamera();
    if (mounted) setState(() => _hint = null);
  }

  Future<void> _setExpected() async {
    final ctl = TextEditingController(text: _expected == null ? '' : '$_expected');
    final v = await showAppSheet<int?>(context, (ctx) => AppSheetContent(title: t('عدد الأوراق', 'Number of papers'), children: [
          Text(t('كم ورقة ستصوّر؟ يظهر العدد في "تم التقاط الورقة 12 من 40". اختياري.', 'How many papers will you scan? It shows as "Paper 12 of 40 captured". Optional.'),
              style: appText(13.5, c: ctx.colors.textMedium, h: 1.4)),
          const SizedBox(height: AppSpace.sm),
          AppField(controller: ctl, label: t('عدد الأوراق', 'Papers'), keyboard: TextInputType.number, ltr: true),
          const SizedBox(height: AppSpace.md),
          AppPrimaryButton(
            label: t('حفظ', 'Save'),
            icon: Icons.check_rounded,
            onPressed: () {
              final n = int.tryParse(ctl.text.trim());
              if (n != null && (n < 1 || n > OmrLimits.maxExpected)) {
                appToast(omrCodeText('expected_invalid'), error: true);
                return;
              }
              Navigator.pop(ctx, n ?? 0);
            },
          ),
        ]));
    ctl.dispose();
    if (v == null || !mounted) return;
    setState(() => _expected = v == 0 ? null : v);
  }

  Future<void> _finish() async {
    final id = _batchId;
    if (id == null) {
      Navigator.of(context).maybePop();
      return;
    }
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => OmrScanProgressScreen(examId: widget.examId, examTitle: widget.examTitle, batchId: id, camera: true, api: widget.api)));
  }

  void _upload() {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => OmrScanProgressScreen.pick(examId: widget.examId, examTitle: widget.examTitle, api: widget.api)));
  }

  (String, OmrHintTone, IconData?) _message() {
    if (_starting) return (t('تشغيل الكاميرا…', 'Starting the camera…'), OmrHintTone.neutral, Icons.photo_camera_outlined);
    if (_capturing) return (t('جارٍ فحص الصورة…', 'Checking the photo…'), OmrHintTone.neutral, Icons.hourglass_top_rounded);
    if (_result != null) return ('', OmrHintTone.neutral, null); // the result card speaks
    if (!_gate.armed && _captured > 0) {
      return (t('أبعد الورقة وضع الورقة التالية', 'Take the paper away and place the next one'), OmrHintTone.neutral, Icons.swap_horiz_rounded);
    }
    if (_note != null) return (_note!, OmrHintTone.warn, Icons.cloud_queue_rounded);
    final h = _hint;
    if (_replaceTarget != null && (h == null || h.text.isEmpty || h.code == 'ready')) {
      return (t('صوّر الورقة نفسها مرة أخرى', 'Take the same paper again'), OmrHintTone.neutral, Icons.autorenew_rounded);
    }
    if (h == null || h.text.isEmpty) return (t('وجّه الكاميرا إلى ورقة التظليل', 'Point the camera at the bubble sheet'), OmrHintTone.neutral, null);
    return (h.text, omrHintTone(h.code, blocking: h.blocking), null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = widget.examTitle.isEmpty ? t('تصوير الأوراق', 'Scan papers') : widget.examTitle;
    if (_setupProblem != null) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: AppEmpty(
              icon: Icons.rule_folder_outlined,
              title: t('لا يمكن تصوير هذا الاختبار الآن', 'This exam cannot be scanned yet'),
              message: _setupProblem,
              actionLabel: t('رجوع', 'Back'),
              onAction: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      );
    }
    if (_issue != null) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: Text(title)),
        body: CameraProblemView(
          issue: _issue!,
          web: kIsWeb,
          onRetry: _start,
          onSettings: kIsWeb ? null : () => openAppSettings(),
          onUpload: _upload,
        ),
      );
    }
    final cam = _cam;
    final (msg, tone, icon) = _message();
    final res = _result;
    final countLabel = _expected != null
        ? t('$_captured من $_expected', '$_captured of $_expected')
        : (_captured > 0 ? t(omrSheetsText(_captured), '$_captured captured') : t('عدد الأوراق', 'Papers'));
    return Scaffold(
      backgroundColor: c.charcoalDark,
      body: Stack(children: [
        Positioned.fill(child: cam == null ? const SizedBox.shrink() : cam.preview()),
        Positioned.fill(
          child: ScannerOverlay(
            message: msg,
            tone: tone,
            icon: icon,
            quarters: (_holding || res != null ? null : _hint?.cornerQuarters) ?? const [false, false, false, false],
            progress: _gate.progress,
            scanning: !_holding && !_starting && _gate.armed,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: ScannerTopBar(
              title: title,
              onClose: () => Navigator.of(context).maybePop(),
              countLabel: countLabel,
              onCount: _setExpected,
              torchOn: cam?.torchOn ?? false,
              onTorch: (cam?.canTorch ?? false) ? _toggleTorch : null,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (res != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: CaptureResultCard(
                    key: ValueKey('omr.result.${res.accepted}'),
                    accepted: res.accepted,
                    title: res.text,
                    more: res.accepted ? const [] : res.moreIssues,
                    duplicate: res.duplicate,
                    onRetake: _retake,
                    onDismiss: () {
                      _hideResult?.cancel();
                      setState(() => _result = null);
                    },
                    result: res.result,
                    previewBytes: _previewBytes,
                    previewLoading: _previewLoading,
                    onPreview: res.result?.previewUrl == null ? null : _openPreview,
                  ),
                ),
              if (res == null && _replaceTarget != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: RetakeTargetPill(onCancel: _cancelRetake),
                ),
              if (res == null || !res.blocks)
                ScannerControls(
                  onShutter: cam == null || _starting ? null : _shoot,
                  busy: _capturing,
                  onFinish: _captured > 0 ? _finish : null,
                  finishLabel: t('إنهاء ($_captured)', 'Finish ($_captured)'),
                  onSwitch: (cam?.canSwitch ?? false) ? _switch : null,
                  autoOn: _auto,
                  onAuto: (v) => setState(() {
                    _auto = v;
                    _gate.reset();
                  }),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
