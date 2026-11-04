// Continuous capture for a mark session (contract §5): the OMR scanner's camera layer (OmrCamera, the guide,
// AutoCaptureGate, HintPacer — imported, not edited) with the mark session's calls. The phone only captures: each photo
// goes to `POST …/pages`; the quality gate answers at once (422 → a big retake card and nothing goes on until the
// person retakes; 409 → "already scanned") and the reading runs on the server. A counter "12 sheets · 9 read · 2
// waiting" follows the live `job_updated {kind: mark_session}` event (EventOrPoll keeps a slow poll as the fallback).
// Where there is no camera, or by choice, several images can be uploaded instead.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../../../admin/admin_common.dart' show t;
import '../../paper/scan/omr_camera.dart';
import '../../paper/scan/omr_scan.dart' show AutoCaptureGate, HintPacer, OmrHintTone, OmrLimits, OmrLiveHint, omrHintTone, retryAfterOf;
import '../../paper/scan/omr_scan_widgets.dart';
import '../mark_sessions_api.dart';

/// The sentence for a quality-gate refusal (422) — the person's next move, in plain words.
String gradeRetakeText(String code, {String fallback = ''}) => switch (code) {
      'blurry' => t('الصورة غير واضحة — ثبّت الهاتف وأعد التصوير', 'The photo is blurry — hold the phone steady and retake'),
      'too_dark' => t('الإضاءة ضعيفة — انتقل إلى إضاءة أفضل وأعد التصوير', 'Too dark — move to better light and retake'),
      'too_bright' => t('الإضاءة شديدة — قلّل الضوء وأعد التصوير', 'Too bright — reduce the light and retake'),
      'glare' => t('يوجد انعكاس ضوء على الورقة — غيّر الزاوية وأعد التصوير', 'There is glare on the paper — change the angle and retake'),
      'page_not_found' => t('لم نجد الورقة كاملة — أدخل الأركان الأربعة في الإطار وأعد التصوير', 'The whole page was not found — fit all four corners in the frame and retake'),
      'not_this_sheet' => t('هذه ليست ورقة هذا النموذج — صوّر الورقة الصحيحة', 'This is not a sheet of this template — scan the right paper'),
      _ => fallback.isNotEmpty ? fallback : t('تعذّر قبول الصورة — أعد التصوير', 'The photo could not be accepted — retake'),
    };

String gradeOutcomeText(MarkPageOutcome o) => switch (o.kind) {
      MarkPageKind.duplicate => t('هذه الورقة صُوّرت من قبل', 'This sheet was already scanned'),
      MarkPageKind.retake => gradeRetakeText(o.code, fallback: o.message),
      _ => o.message.isNotEmpty ? o.message : t('تعذّر إرسال الصورة — حاول مرة أخرى', 'The photo could not be sent — try again'),
    };

/// "12 sheets · 9 read · 2 waiting".
String gradeCounterText(int sheets, int read, int waiting) {
  final s = countText(sheets,
      ar1: 'ورقة واحدة', ar2: 'ورقتان', arFew: '$sheets أوراق', arMany: '$sheets ورقة', en1: '1 sheet', en: '$sheets sheets', ar0: 'لا أوراق', en0: 'no sheets');
  return '$s · ${t('$read مقروءة', '$read read')} · ${t('$waiting بالانتظار', '$waiting waiting')}';
}

/// What the capture screen draws over the picture, as plain values: the counter and, when the last photo needs the
/// person, the big card with the reason and the retake button.
class GradeCaptureHud extends StatelessWidget {
  const GradeCaptureHud({super.key, required this.sheets, required this.read, required this.waiting, this.problem, this.onRetake, this.onDismiss, this.checking = false, this.showCounter = true});

  final int sheets, read, waiting;
  final MarkPageOutcome? problem;
  final VoidCallback? onRetake, onDismiss;

  /// A photo is being checked by the quality gate.
  final bool checking;

  /// False when the counter is drawn elsewhere (the problem card sits at the bottom, the counter on top).
  final bool showCounter;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = problem;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (showCounter)
      Semantics(
        liveRegion: true,
        child: Container(
          key: const ValueKey('gr.counter'),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: BoxDecoration(color: c.heroShade.withValues(alpha: .75), borderRadius: BorderRadius.circular(AppRadius.hero)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(checking ? Icons.hourglass_top_rounded : Icons.collections_outlined, size: 16, color: c.onHero),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: Text(gradeCounterText(sheets, read, waiting), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w700, c: c.onHero))),
          ]),
        ),
      ),
      if (p != null && p.kind != MarkPageKind.queued) ...[
        if (showCounter) const SizedBox(height: AppSpace.sm),
        CaptureResultCard(
          key: ValueKey('gr.problem.${p.kind.name}'),
          accepted: false,
          title: gradeOutcomeText(p),
          duplicate: p.kind == MarkPageKind.duplicate,
          onRetake: p.kind == MarkPageKind.duplicate ? null : onRetake,
          onDismiss: onDismiss,
        ),
      ],
    ]);
  }
}

class GradeCaptureScreen extends StatefulWidget {
  const GradeCaptureScreen({super.key, required this.session, this.api, this.camera, this.onDone});

  final MarkSession session;
  final MarkSessionsApi? api;

  /// The camera to use (tests hand a fake); the platform's by default.
  final OmrCamera Function()? camera;

  /// "Review results": the caller replaces this screen with the results.
  final void Function(BuildContext context)? onDone;

  @override
  State<GradeCaptureScreen> createState() => _GradeCaptureScreenState();
}

class _GradeCaptureScreenState extends State<GradeCaptureScreen> with WidgetsBindingObserver {
  late final MarkSessionsApi _api = widget.api ?? MarkSessionsApi();
  final _gate = AutoCaptureGate();
  final _pacer = HintPacer();
  EventOrPoll? _watch;

  OmrCamera? _cam;
  bool _starting = true, _capturing = false, _auto = true, _paused = false;
  OmrCameraIssue? _issue;
  int _gen = 0;
  OmrLiveHint? _hint;
  String? _note;

  /// The last photo needs the person (retake / already scanned): hints and auto-capture wait.
  MarkPageOutcome? _problem;
  int _sent = 0, _read = 0, _waiting = 0;

  bool get _holding => _capturing || _paused || _problem != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read = widget.session.counts.read;
    _waiting = widget.session.counts.pending;
    _sent = _read + _waiting;
    _watch = EventOrPoll(
      kind: kMarkSessionJobKind,
      id: '${widget.session.id}',
      every: const Duration(seconds: 4),
      fallbackEvery: const Duration(seconds: 15),
      poll: _refreshCounts,
    )..start();
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch?.dispose();
    _gen++;
    final cam = _cam;
    _cam = null;
    if (cam != null) unawaited(cam.dispose());
    super.dispose();
  }

  Future<void> _refreshCounts() async {
    final r = await _api.get(widget.session.id);
    if (!mounted || !r.ok) return;
    final s = MarkSession.fromJson(r.map);
    setState(() {
      _read = s.counts.read;
      _waiting = s.counts.pending;
      if (_sent < _read + _waiting) _sent = _read + _waiting;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
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

  Future<void> _start() async {
    _starting = true;
    _issue = null;
    Future.microtask(() {
      if (mounted) setState(() {});
    });
    final old = _cam;
    _cam = null;
    _gen++;
    if (old != null) await old.dispose();
    final cam = (widget.camera ?? createOmrCamera)();
    try {
      await cam.open();
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
    unawaited(_hints(++_gen));
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

  /// The live-hint loop (≤ 2.5 frames / s): the server's tip steers, a steady run captures by itself.
  Future<void> _hints(int gen) async {
    String? prev;
    while (mounted && gen == _gen) {
      final cam = _cam;
      if (cam == null) return;
      if (_holding) {
        prev = null;
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
      final r = await _api.liveHint(widget.session.id, f.jpeg, prev: prev);
      if (!mounted || gen != _gen) return;
      if (_holding) continue;
      Duration wait;
      if (r.ok) {
        final h = OmrLiveHint.fromJson(markHintToOmr(r.map), frameW: f.width, frameH: f.height);
        prev = h.stat;
        final fire = _auto && _gate.feed(h, DateTime.now());
        setState(() {
          _hint = h;
          _note = null;
        });
        if (fire) unawaited(_shoot());
        wait = _pacer.afterOk(sw.elapsed);
      } else if (r.status == 503 || r.status == 429) {
        setState(() => _note = t('الخادم مشغول — تعمل الكاميرا يدويًا', 'The server is busy — the shutter still works'));
        wait = r.status == 429 ? _pacer.afterRateLimit(retryAfterOf(r)) : _pacer.afterBusy(retryAfterOf(r));
      } else {
        prev = null;
        setState(() => _note = t('لا اتصال — تعمل الكاميرا يدويًا', 'No connection — the shutter still works'));
        wait = _pacer.afterError();
      }
      await _wait(wait, gen);
    }
  }

  Future<void> _shoot() async {
    final cam = _cam;
    if (_capturing || _problem != null || cam == null) return;
    setState(() => _capturing = true);
    _gate.captured();
    final photo = await cam.photo();
    if (!mounted) return;
    if (photo == null || photo.isEmpty) {
      setState(() => _capturing = false);
      _gate.reset();
      showAppNotice(t('تعذّر التقاط الصورة — حاول مرة أخرى', 'The photo could not be taken — try again'), error: true);
      return;
    }
    final out = await omrUploadPhoto(photo);
    if (!mounted) return;
    await _send(out, camera: true);
  }

  /// One page to the server; true = queued.
  Future<bool> _send(Uint8List image, {required bool camera, String? name}) async {
    final r = await _api.addPage(widget.session.id, image, camera: camera, name: name);
    if (!mounted) return false;
    final o = markPageOutcome(r, arabic: AppConfig.lang == 'ar');
    if (o.ok) {
      setState(() {
        _capturing = false;
        _sent++;
        _waiting++;
        _problem = null;
      });
      unawaited(HapticFeedback.mediumImpact());
      return true;
    }
    _gate.reset();
    setState(() {
      _capturing = false;
      if (o.kind == MarkPageKind.error) {
        _problem = null;
      } else {
        _problem = o;
      }
    });
    unawaited(HapticFeedback.heavyImpact());
    if (o.kind == MarkPageKind.error) showAppNotice(gradeOutcomeText(o), error: true);
    return false;
  }

  /// The problem is acknowledged: the camera goes on (a refused photo stored nothing, so the next shot is the retake).
  void _retake() {
    _gate.reset();
    setState(() => _problem = null);
  }

  Future<void> _pickAndUpload() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty || !mounted) return;
    var okCount = 0;
    for (final f in files) {
      if (!mounted) return;
      if ((f.lengthSync() ?? 0) > OmrLimits.maxFileBytes) {
        showAppNotice(t('${f.name}: الملف كبير جدًا', '${f.name}: the file is too large'), error: true);
        continue;
      }
      setState(() => _capturing = true);
      final ok = await _send(await f.readAsBytes(), camera: false, name: f.name);
      if (ok) {
        okCount++;
      } else if (_problem != null) {
        // stop at the first photo that needs a person; the rest wait for the next pick
        showAppNotice('${f.name}: ${gradeOutcomeText(_problem!)}', error: true);
        _problem = null;
      }
    }
    if (mounted) setState(() => _capturing = false);
    if (okCount > 0) showAppNotice(t('أُرسلت $okCount صورة', '$okCount image(s) sent'));
  }

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

  void _finish() {
    if (widget.onDone != null) {
      widget.onDone!(context);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  (String, OmrHintTone, IconData?) _message() {
    if (_starting) return (t('تشغيل الكاميرا…', 'Starting the camera…'), OmrHintTone.neutral, Icons.photo_camera_outlined);
    if (_capturing) return (t('جارٍ فحص الصورة…', 'Checking the photo…'), OmrHintTone.neutral, Icons.hourglass_top_rounded);
    if (_problem != null) return ('', OmrHintTone.neutral, null);
    if (!_gate.armed && _sent > 0) return (t('أبعد الورقة وضع الورقة التالية', 'Take the paper away and place the next one'), OmrHintTone.neutral, Icons.swap_horiz_rounded);
    if (_note != null) return (_note!, OmrHintTone.warn, Icons.cloud_queue_rounded);
    final h = _hint;
    if (h == null || h.text.isEmpty) return (t('وجّه الكاميرا إلى ورقة الدرجات', 'Point the camera at the marks sheet'), OmrHintTone.neutral, null);
    return (h.text, omrHintTone(h.code, blocking: h.blocking), null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = widget.session.mode == MarkMode.review ? t('مراجعة الدرجات', 'Review grades') : t('استيراد الدرجات', 'Import marks');
    if (_issue != null) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: Text(title), actions: [
          TextButton(onPressed: _finish, child: Text(t('النتائج', 'Results'))),
        ]),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: GradeCaptureHud(sheets: _sent, read: _read, waiting: _waiting, problem: _problem, onRetake: _retake, onDismiss: _retake, checking: _capturing),
          ),
          Expanded(
            child: CameraProblemView(issue: _issue!, web: kIsWeb, onRetry: _start, onSettings: kIsWeb ? null : () => openAppSettings(), onUpload: _pickAndUpload),
          ),
        ]),
      );
    }
    final cam = _cam;
    final (msg, tone, icon) = _message();
    return Scaffold(
      backgroundColor: c.charcoalDark,
      body: Stack(children: [
        Positioned.fill(child: cam == null ? const SizedBox.shrink() : cam.preview()),
        Positioned.fill(
          child: ScannerOverlay(
            message: msg,
            tone: tone,
            icon: icon,
            quarters: (_holding ? null : _hint?.cornerQuarters) ?? const [false, false, false, false],
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ScannerTopBar(
                title: title,
                onClose: () => Navigator.of(context).maybePop(),
                torchOn: cam?.torchOn ?? false,
                onTorch: (cam?.canTorch ?? false) ? _toggleTorch : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: GradeCaptureHud(sheets: _sent, read: _read, waiting: _waiting, checking: _capturing),
              ),
            ]),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                  child: GradeCaptureHud(sheets: _sent, read: _read, waiting: _waiting, problem: _problem, onRetake: _retake, onDismiss: _retake, showCounter: false),
                )
              else
                ScannerControls(
                  onShutter: cam == null || _starting ? null : _shoot,
                  busy: _capturing,
                  onFinish: _finish,
                  finishLabel: t('النتائج ($_sent)', 'Results ($_sent)'),
                  onSwitch: (cam?.canSwitch ?? false) ? _switch : null,
                  autoOn: _auto,
                  onAuto: (v) => setState(() {
                    _auto = v;
                    _gate.reset();
                  }),
                ),
              if (_problem == null)
                TextButton.icon(
                  onPressed: _capturing ? null : _pickAndUpload,
                  icon: Icon(Icons.upload_file_rounded, color: c.onHero),
                  label: Text(t('رفع صور بدلًا من الكاميرا', 'Upload images instead'), style: appText(13, c: c.onHero)),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
