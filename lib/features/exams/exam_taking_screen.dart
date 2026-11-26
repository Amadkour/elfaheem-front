// Taking an Exam Engine exam (Phase 5, D-018): server timer, autosave with resume, one-way sections, integrity events.
//
// Flow: `openEngineExam(context, exam)` → consent (if not accepted) → start / resume → this screen → result screen.
// The screen talks to the engine through [ExamEngineApi]; the pure pieces live in exam_taking.dart.
import 'dart:async';

import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_education_app/features/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase, AppFill;
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppJelly, AppPop;
import 'package:flutter_education_app/core/display/app_fonts.dart' show AppFonts;
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/core/screen_security.dart';
import 'package:flutter_education_app/core/live_focus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, t, asMapList;
import 'package:flutter_education_app/features/admin/admin_money_p8.dart' show p8SaveBytes;
import 'package:flutter_education_app/features/courses/student/security/device_id_service.dart';
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show categoryLabel;
import 'package:flutter_education_app/features/exams/exam_consent_screen.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/exam_integrity.dart';
import 'package:flutter_education_app/features/exams/exam_result_screen.dart';
import 'package:flutter_education_app/features/exams/exam_media.dart';
import 'package:flutter_education_app/features/exams/exam_taking.dart';
import 'package:flutter_education_app/features/exams/exam_page_width.dart';
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistant;
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/api_client.dart';

/// Entry point from an exam list: consent → attempt → taking screen. Shows the server's refusal when there is one.
Future<void> openEngineExam(BuildContext context, Map<String, dynamic> exam, {String? passcode}) async {
  final api = ExamEngineApi();
  final examId = asInt(exam['id']);
  final title = '${exam['title'] ?? ''}';
  final deviceId = await DeviceIdService.instance.id();
  final platform = DeviceIdService.platform == 'web' ? 'web' : 'mobile';
  if (!context.mounted) return;

  Future<void> start(BuildContext ctx) async {
    final r = await api.start(examId, platform: platform, deviceId: deviceId, passcode: passcode);
    if (!ctx.mounted) return;
    if (!r.ok) {
      if (r.code == 'consent_required') {
        await Navigator.push(ctx, MaterialPageRoute(builder: (_) => ExamConsentScreen(examId: examId, exam: exam, onAccepted: (c2) async {
              Navigator.pop(c2);
              await start(ctx);
            })));
        return;
      }
      // never a silent tap: when it opens, the app's text for the code, or the server's own words (round 3 e2e)
      showAppNotice(examRefusalText(r.code, r.message, r.detail), error: true);
      return;
    }
    // the sitting is full-screen: on the root navigator, above any tab bar (D-081)
    await Navigator.of(ctx, rootNavigator: true).push(MaterialPageRoute(builder: (_) => ExamTakingScreen(examTitle: title, startReply: r.map, deviceId: deviceId,
        examId: examId, hasPaperFile: exam['has_paper_file'] == true, paperFile: exam['paper_file'] is Map ? asMap(exam['paper_file']) : null)));
  }

  await start(context);
}

class ExamTakingScreen extends StatefulWidget {
  const ExamTakingScreen({super.key, required this.examTitle, required this.startReply, required this.deviceId, this.examId, this.hasPaperFile = false, this.paperFile});
  final String examTitle;
  final Map<String, dynamic> startReply;   // {attempt, exam_session, resumed, accommodation}
  final String deviceId;
  final int? examId;

  /// The exam is given as a file (quick exam): the app bar offers it for download.
  final bool hasPaperFile;
  final Map<String, dynamic>? paperFile;   // {name, content_type, size}

  @override
  State<ExamTakingScreen> createState() => _ExamTakingScreenState();
}

class _ExamTakingScreenState extends State<ExamTakingScreen> with WidgetsBindingObserver {
  final _api = ExamEngineApi();
  late int _attemptId;
  late String _session;
  late Paper _paper;
  late ServerClock _clock;
  final _queue = AutosaveQueue();
  final _events = EventBuffer();
  late final ExamIntegrity _integrity;
  Timer? _ticker;
  Timer? _saver;
  int _index = 0;
  bool _locked = false;
  String? _lockReason;
  bool _submitting = false;
  bool _finished = false;
  String? _warning;

  @override
  void initState() {
    super.initState();
    AppAssistant.hide(); // full screen: no floating assistant bubble
    final attempt = asMap(widget.startReply['attempt']);
    _attemptId = asInt(attempt['id']);
    _session = '${widget.startReply['exam_session']}';
    _paper = Paper.fromJson(asMap(attempt['paper']));
    _clock = ServerClock.fromAttempt(attempt, DateTime.now(), elapsed: ServerClock.monotonic())!;
    _locked = attempt['locked'] == true;
    _lockReason = attempt['lock_reason'] as String?;
    _integrity = ExamIntegrity((kind, meta) {
      _events.add(kind, meta: meta);
      if (_events.hasUrgent) _flushEvents();
    })..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _saver = Timer.periodic(const Duration(seconds: 4), (_) => _flush());
    _restorePending();
    _protectScreen(true);
    LiveFocus.enterExam(this); // no must-acknowledge card over a live exam (D-977)
    WidgetsBinding.instance.addObserver(this);
  }

  /// Back from the background (the phone may have slept, its clock may have moved): the server's clock again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resyncClock();
    // back in the app during a timed sitting: a calm word that the time kept running (redesign S-C)
    if (state == AppLifecycleState.resumed && !_finished && _clock.timed) showAppNotice(t('رجعت؟ كمّل، وقتك ماشي', 'Back? Carry on, your time is running'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _saver?.cancel();
    _integrity.stop();
    _protectScreen(false);
    LiveFocus.leaveExam(this);
    _persistPending();                                  // finished → the stored copy is removed
    AppAssistant.release();
    super.dispose();
  }

  // ── answers that must survive an app kill or a reload (Phase 9) ──
  String get _storeKey => 'exam.pending.$_attemptId';
  int _restored = 0;                                 // bumps the question cards' keys after a restore

  Future<void> _restorePending() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = _queue.restore(p.getString(_storeKey), _paper);
      if (n > 0 && mounted) {
        setState(() => _restored++);
        _flush();
      }
    } catch (_) {}                                          // no device storage: the server copy stands
  }

  Future<void> _persistPending() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_queue.isEmpty || _finished) {
        await p.remove(_storeKey);
      } else {
        await p.setString(_storeKey, _queue.toJson());
      }
    } catch (_) {}
  }

  /// No screenshots / recording of the paper on phones while the attempt is open (Android FLAG_SECURE, iOS blur).
  /// The web cannot prevent it — the consent screen says so.
  /// Owned through ScreenSecurity (D-083): another protected screen closing never switches this one off.
  Future<void> _protectScreen(bool on) =>
      on ? ScreenSecurity.instance.protect(this) : ScreenSecurity.instance.release(this);

  // ── timer ──
  void _tick() {
    if (!mounted || _finished) return;
    final left = _clock.remaining();
    setState(() {});
    if (left == null || left > 0) return;
    // zero on the wall clock only (a sleep, or a device clock set forward): the server decides, not this device
    if (_clock.wallAhead()) {
      _resyncClock();
    } else {
      _timeUp();
    }
  }

  bool _resyncing = false;
  final _sinceResync = Stopwatch();

  /// Re-reads the attempt's `remaining_seconds` from the server and restarts the clock from it (at most every 10 s,
  /// so an offline phone does not ask every tick; the server ends the attempt at its own deadline anyway).
  Future<void> _resyncClock() async {
    if (_resyncing || _finished || !_clock.timed) return;
    if (_sinceResync.isRunning && _sinceResync.elapsed < const Duration(seconds: 10)) return;
    _sinceResync..reset()..start();
    _resyncing = true;
    try {
      final r = await _api.attempt(_attemptId);
      if (!mounted || _finished || !r.ok) return;
      if (r.map['result'] != null) {
        _finished = true;
        _showResult(asMap(r.map['result']));
        return;
      }
      if (r.map['remaining_seconds'] == null) return;
      setState(() => _clock = ServerClock(remainingSeconds: asInt(r.map['remaining_seconds']), receivedAt: DateTime.now(),
          deadlineAt: _clock.deadlineAt, elapsed: ServerClock.monotonic()));
      if ((_clock.remaining() ?? 1) <= 0) _timeUp();
    } finally {
      _resyncing = false;
    }
  }

  Future<void> _timeUp() async {
    if (_finished) return;
    await _flush();                                  // the last answers, inside the server's grace
    _finished = true;
    await _api.submit(_attemptId, session: _session, deviceId: widget.deviceId);   // finalise now rather than wait for the sweeper
    final r = await _api.attempt(_attemptId);
    if (!mounted) return;
    appToast(examCodeText('deadline_passed'));
    _showResult(r.ok ? asMap(r.map['result']) : {'visible': false, 'state': 'auto_submitted'});
  }

  // ── autosave ──
  Future<void> _flush({bool retried = false}) async {
    if (_queue.isEmpty || _finished) return _flushEvents();
    final batch = _queue.batch();
    final r = await _api.save(_attemptId, batch, session: _session, deviceId: widget.deviceId);
    if (!mounted) return;
    if (!r.ok && r.code == 'exam_session_invalid' && !retried) {
      // the session expired between two flushes: renew and send the SAME batch again, so a submit that follows
      // never finalises without it
      await _renewSession();
      if (mounted) return _flush(retried: true);
      return;
    }
    if (r.ok) {
      _queue.ack(batch, [...(r.map['saved'] as List? ?? const []), ...(r.map['ignored'] as List? ?? const [])]);
      for (final rej in asMapList(r.map['rejected'])) {
        _queue.drop(asInt(rej['question_id']));          // refused for good (one-way): the queue moves on
        if ('${rej['code']}' == 'one_way_section') appToast(examCodeText('one_way_section'), error: true);
      }
      _persistPending();
      _clock = ServerClock(remainingSeconds: r.map['remaining_seconds'] == null ? null : asInt(r.map['remaining_seconds']), receivedAt: DateTime.now(),
          deadlineAt: _clock.deadlineAt, elapsed: ServerClock.monotonic());
    } else {
      await _handleFailure(r);
    }
    await _flushEvents();
  }

  Future<void> _flushEvents() async {
    if (_events.isEmpty || _finished) return;
    final events = _events.drain();
    final r = await _api.events(_attemptId, events, session: _session, deviceId: widget.deviceId);
    if (!mounted) return;
    if (!r.ok) {
      if (r.code == 'exam_session_invalid') await _renewSession();
      // transient (offline, expired session, throttled): the events wait for the next flush; a refusal the server
      // will repeat (not consented, unknown kind, too many) is dropped so it cannot block the buffer
      const permanent = {'event_not_consented', 'bad_event_kind', 'too_many_events', 'event_meta_too_large', 'bad_evidence_key'};
      if (!permanent.contains(r.code) && r.code != 'attempt_locked' && !(r.code ?? '').startsWith('attempt_')) _events.requeue(events);
      return;
    }
    for (final a in actionsOf(r.map)) {
      if (a.warns) {
        final what = integrityReasonText(a.category);
        setState(() => _warning = what == null
            ? t('تنبيه: سُجّل سلوك مخالف لقواعد الاختبار', 'Warning: something against the exam rules was recorded')
            : t('تنبيه: سُجّل $what', 'Warning: ${what.toLowerCase()} was recorded'));
      }
      if (a.locks) setState(() { _locked = true; _lockReason = a.category; });
      if (a.submits) {
        _finished = true;
        final res = await _api.attempt(_attemptId);
        if (!mounted) return;
        _showResult(res.ok ? asMap(res.map['result']) : {'visible': false, 'state': 'auto_submitted'});
        return;
      }
    }
    if ('${r.map['state']}' == 'locked' && !_locked) setState(() => _locked = true);
  }

  Future<void> _handleFailure(EngineResult r) async {
    switch (r.code) {
      case 'exam_session_invalid':
        await _renewSession();
      case 'deadline_passed':
        await _timeUp();
      case 'attempt_locked':
        setState(() { _locked = true; _lockReason = '${r.detail['reason'] ?? ''}'; });
      case 'attempt_rejected' || 'attempt_submitted' || 'attempt_auto_submitted' || 'attempt_void':
        _finished = true;
        final res = await _api.attempt(_attemptId);
        if (mounted) _showResult(res.ok ? asMap(res.map['result']) : {'visible': false, 'state': r.code!.substring(8)});
      case 'question_not_in_paper' || 'bad_answer' || 'answer_too_large':
        // this item can never be saved: drop it so the rest of the queue flows; the student is told when it is theirs to fix
        _queue.drop(asInt(r.detail['question_id']));
        if (r.code == 'answer_too_large') appToast(examCodeText('answer_too_large'), error: true);
      case 'too_many_requests':
        return;                                      // the next tick retries
      case 'one_way_section':
        appToast(examCodeText('one_way_section'), error: true);
      case 'device_mismatch':
        appToast(examCodeText('device_mismatch'), error: true);
      default:
        if (r.status == 0) return;                   // offline: the queue keeps the answers, next flush retries
        appToast(r.message, error: true);
    }
  }

  Future<void> _renewSession() async {
    final r = await _api.refreshSession(_attemptId, deviceId: widget.deviceId);
    if (r.ok && mounted) _session = '${r.map['exam_session']}';
  }

  // ── answers / navigation ──
  void _answer(PaperQuestion q, Map<String, dynamic> answer) {
    if (_locked || _finished) return;
    setState(() => _queue.put(q, answer));
    _persistPending();
  }

  /// A `file_upload` answer goes straight to the server (not through the autosave queue).
  Future<void> _uploadFile(PaperQuestion q) async {
    if (_locked || _finished) return;
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'docx', 'doc', 'png', 'jpg', 'jpeg']);
    if (f == null || !mounted) return;
    final bytes = kIsWeb || f.path == null ? await f.readAsBytes() : null;
    final r = await _api.uploadAnswerFile(_attemptId, q.questionId,
        fileName: f.name, bytes: bytes, path: kIsWeb ? null : f.path, session: _session, deviceId: widget.deviceId);
    if (!mounted) return;
    if (!r.ok) return appToast(examCodeText(r.code ?? '') == (r.code ?? '') ? r.message : examCodeText(r.code ?? ''), error: true);
    setState(() => q.answer = {'file': asMap(r.map['file'])});
    appToast(t('رُفع ملف إجابتك', 'Your answer file is uploaded'));
  }

  Future<void> _downloadPaper() async {
    try {
      final bytes = await _api.paperFile(widget.examId!);
      final f = widget.paperFile;
      await p8SaveBytes(bytes, '${f?['name'] ?? 'exam.pdf'}', mime: '${f?['content_type'] ?? 'application/octet-stream'}');
    } catch (e) {
      appToast(apiErrorText(ApiException.from(e)), error: true);
    }
  }

  void _goTo(int i) {
    final all = _paper.all;
    if (i < 0 || i >= all.length) return;
    if (!_paper.canNavigate(all[_index], all[i])) {
      appToast(examCodeText('one_way_section'), error: true);
      return;
    }
    setState(() => _index = i);
  }

  Future<void> _submit() async {
    if (_submitting || _finished) return;           // a second tap while the first is on its way never sends twice
    final all = _paper.all;
    final ok = await showAppSheet<bool>(
        context,
        (_) => ExamSubmitSheet(
              answered: _paper.answeredCount,
              left: _paper.onlineCount - _paper.answeredCount,
              firstLeft: [for (var i = 0; i < all.length; i++) if (!all[i].answered) i + 1].firstOrNull,
              remainingSeconds: _clock.timed ? _clock.remaining() : null,
            ));
    if (ok != true || !mounted || _submitting || _finished) return;
    setState(() => _submitting = true);
    for (var i = 0; i < 3 && !_queue.isEmpty && !_finished; i++) {
      await _flush();
    }
    if (!mounted) return;
    if (!_queue.isEmpty && !_finished) {
      // never finalise with answers still unsaved: the student is told and the queue keeps retrying
      setState(() => _submitting = false);
      appToast(t('لم تُحفظ كل إجاباتك بعد — تحقق من الاتصال ثم أعد التسليم', 'Not all your answers are saved yet — check the connection and submit again'), error: true);
      return;
    }
    final r = await _api.submit(_attemptId, session: _session, deviceId: widget.deviceId);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!r.ok) {
      if (r.code == 'attempt_submitted' || r.code == 'deadline_passed') {
        final res = await _api.attempt(_attemptId);
        if (mounted) _showResult(res.ok ? asMap(res.map['result']) : {'visible': false});
        return;
      }
      if (r.status == 0) {
        // D-1135: the connection dropped on the way. Never a silent tap: the answers are saved, the exam is still
        // open, and a second submit is safe (a submit that did reach the server answers attempt_submitted)
        appToast(t('انقطع الاتصال قبل التسليم — إجاباتك محفوظة. أعد التسليم عند عودة الاتصال',
            'The connection dropped before the exam was submitted — your answers are saved. Submit again when you are back online'), error: true);
        return;
      }
      await _handleFailure(r);
      return;
    }
    _finished = true;
    _showResult(asMap(r.map['result']));
  }

  void _showResult(Map<String, dynamic> result) {
    _ticker?.cancel();
    _saver?.cancel();
    _integrity.stop();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ExamResultScreen(result: result, examTitle: widget.examTitle)));
  }

  /// Which way the last move went: the next question comes in from the reading end, the previous one from the start.
  bool _forward = true;

  @override
  Widget build(BuildContext context) {
    final all = _paper.all;
    final q = all.isEmpty ? null : all[_index.clamp(0, all.length - 1)];
    final left = _clock.remaining();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await appConfirm(context, message: t('إجاباتك محفوظة ويمكنك المتابعة لاحقاً. الخروج الآن؟', 'Your answers are saved and you can continue later. Leave now?'));
        if (leave && context.mounted) {
          await _flush();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: AppAreaScope(area: AppArea.exam, child: BasePage(
        key: const ValueKey('exam.taking'),
        appBar: AppHeader(
          title: widget.examTitle,
          compact: true,
          actions: [
            const HelpInfoButton(pageId: 'exam.taking'),
            if (widget.hasPaperFile && widget.examId != null)
              AppIconButton(onPressed: _downloadPaper, icon: Icons.file_download_rounded, tooltip: t('ملف الامتحان', 'Exam file')),
            ExamTimerChip(remainingSeconds: left, timed: _clock.timed),
          ],
        ),
        child: q == null
            ? AppEmpty(icon: Icons.quiz_outlined, title: t('لا توجد أسئلة إلكترونية في هذه الورقة', 'No online questions in this paper'))
            : Column(children: [
                ExamProgressBar(index: _index, total: all.length, answered: _paper.answeredCount, locked: _locked, lockReason: _lockReason,
                    warning: _warning, pendingSaves: _queue.length, answeredFlags: [for (final x in all) x.answered]),
                Expanded(
                  // Enter in an answer box goes to the next question — never to "Submit" (web / desktop keyboards)
                  child: EnterSubmits(
                    onSubmit: _index < all.length - 1 ? () => _goTo(_index + 1) : null,
                    child: ExamQuestionSwap(
                      forward: _forward,
                      child: ExamQuestionCard(
                        key: ValueKey('q.${q.questionId}.$_restored'),
                        question: q,
                        number: _index + 1,
                        section: _paper.sections[q.sectionIndex],
                        enabled: !_locked && !_finished,
                        onAnswer: (a) => _answer(q, a),
                        onPickFile: () => _uploadFile(q),
                        attemptId: _attemptId,
                      ),
                    ),
                  ),
                ),
                ExamNavBar(
                  index: _index,
                  total: all.length,
                  canBack: _index > 0 && _paper.canNavigate(q, all[_index - 1]),
                  submitting: _submitting,
                  onBack: () => _move(_index - 1),
                  onNext: () => _move(_index + 1),
                  onJump: (i) => _move(i),
                  answered: {for (final x in all) x.questionId: x.answered},
                  questionIds: [for (final x in all) x.questionId],
                  onSubmit: _locked ? null : _submit,
                ),
              ]),
      )),
    );
  }

  /// [_goTo] that remembers the direction for the question's entrance.
  void _move(int i) {
    _forward = i >= _index;
    _goTo(i);
  }
}

// ═══════════════════════════ presentational pieces (plain values; under the layout harness) ═══════════════════════

/// The time left: a paper pill in the header with tabular digits; the last five minutes on the warning tint, the last
/// minute on the danger tint, each with its own glyph so the colour is never the only signal.
class ExamTimerChip extends StatelessWidget {
  const ExamTimerChip({super.key, required this.remainingSeconds, required this.timed});
  final int? remainingSeconds;
  final bool timed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!timed || remainingSeconds == null) return const SizedBox.shrink();
    final urgent = remainingSeconds! <= 300;
    final last = remainingSeconds! <= 60;
    final mins = (remainingSeconds! / 60).ceil();
    final tone = last ? c.danger : (urgent ? c.warning : null);
    final fill = tone == null ? c.cardBg : appTintOn(context, tone);
    final ink = tone == null ? c.textDark : appInkOn(context, tone, fill);
    // screen readers hear the time left once a minute (the label changes per minute), not every second
    return Semantics(
      label: t('الوقت المتبقي $mins دقيقة', '$mins minutes left'),
      liveRegion: urgent,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xxs),
        child: Center(
          child: AnimatedContainer(
            duration: AppMotion.of(context).base,
            curve: AppEase.out,
            constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
            padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.sm),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: tone == null ? c.divider : fill, width: AppBorder.hairline),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(last ? Icons.hourglass_bottom_rounded : (urgent ? Icons.hourglass_top_rounded : Icons.timer_outlined),
                  size: AppIconSize.sm, color: ink),
              const SizedBox(width: AppSpace.xs),
              Text(clockText(remainingSeconds!),
                  key: const ValueKey('exam.timer'),
                  textDirection: TextDirection.ltr,
                  style: AppType.label(context).copyWith(
                      color: ink, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Where the student is: "Question 3 of 7", how many are answered, whether every answer reached the server, and a
/// strip with one segment per question (answered filled, the open one ringed) — or one bar on a very long paper.
class ExamProgressBar extends StatelessWidget {
  const ExamProgressBar({super.key, required this.index, required this.total, required this.answered, required this.locked, this.lockReason,
      this.warning, required this.pendingSaves, this.answeredFlags});
  final int index;
  final int total;
  final int answered;
  final bool locked;
  final String? lockReason;
  final String? warning;
  final int pendingSaves;

  /// One flag per question in paper order: drawn as segments (null = a single bar).
  final List<bool>? answeredFlags;

  /// Past this many questions the segments get too thin to read: one bar instead.
  static const int maxSegments = 60;

  /// The answered count never takes more than this from the "Question 3 of 7" line.
  static const double maxCountWidth = AppTouch.min * 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final saved = pendingSaves == 0;
    final flags = answeredFlags;
    return ExamPageWidth(width: AppWidth.reading, builder: (side) => Padding(
      padding: EdgeInsetsDirectional.fromSTEB(side, AppSpace.sm, side, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(t('سؤال ${index + 1} من $total', 'Question ${index + 1} of $total'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: AppSpace.xs),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxCountWidth),
            child: Text(t('أُجيب $answered', '$answered answered'),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: AppType.meta(context)),
          ),
          const SizedBox(width: AppSpace.xs),
          Icon(saved ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded, size: AppIconSize.sm, color: saved ? c.success : c.textLight,
              semanticLabel: saved ? t('كل الإجابات محفوظة', 'All answers saved') : t('جارٍ حفظ $pendingSaves إجابة', 'Saving $pendingSaves answers')),
        ]),
        const SizedBox(height: AppSpace.xs),
        ExcludeSemantics(
          child: flags != null && flags.length == total && total <= maxSegments
              ? _SegmentStrip(flags: flags, current: index)
              : AppFill(
                  value: total == 0 ? 0 : answered / total,
                  builder: (_, v) => _SegmentStrip.bar(context, v),
                ),
        ),
        if (locked)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: AppBanner(icon: Icons.lock_rounded, color: c.warning, text: '${examCodeText('attempt_locked')}${integrityReasonText(lockReason) == null ? '' : ' (${integrityReasonText(lockReason)})'}'),
          )
        else if (warning != null)
          Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: AppBanner(icon: Icons.warning_amber_rounded, color: c.warning, text: warning!)),
      ]),
    ));
  }
}

/// What an integrity category means, in words (D-1135: the raw key such as "other_app" reached the student); null for
/// an empty or unknown one, so the caller leaves it out rather than show a code.
String? integrityReasonText(String? category) {
  final c = (category ?? '').trim();
  if (c.isEmpty) return null;
  final label = categoryLabel(c);
  return label == c ? null : label;
}

/// The progress strip: a segment per question, answered = the primary, unanswered = the hairline tone, the open one
/// drawn in ink so it reads without colour.
class _SegmentStrip extends StatelessWidget {
  const _SegmentStrip({required this.flags, required this.current});
  final List<bool> flags;
  final int current;

  static const double height = AppSpace.xs;

  /// A single bar at [fraction] (very long papers).
  static Widget bar(BuildContext context, double fraction) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Positioned.fill(child: ColoredBox(color: c.kit.track)),
          FractionallySizedBox(alignment: AlignmentDirectional.centerStart, widthFactor: fraction.clamp(0.0, 1.0), heightFactor: 1, child: ColoredBox(color: AppAreaScope.of(context).a)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final done = Color.lerp(set.tint, set.a, .35)!;
    return SizedBox(
      height: height,
      child: Row(children: [
        for (var i = 0; i < flags.length; i++) ...[
          if (i > 0) const SizedBox(width: AppBorder.focus),
          Expanded(
            child: AnimatedContainer(
              duration: AppMotion.of(context).fast,
              curve: AppEase.out,
              decoration: BoxDecoration(
                color: i == current ? set.a : (flags[i] ? done : c.kit.track),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// A question's entrance: the next one comes in a short way from the reading end while the last one leaves, the
/// previous one from the start (it follows Next / Back). One move, 220 ms, nothing under Reduce motion.
class ExamQuestionSwap extends StatelessWidget {
  const ExamQuestionSwap({super.key, required this.forward, required this.child});
  final bool forward;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // the share of the width the question travels: enough to read as a page turn, short enough to never feel slow
    const travel = 0.06;
    final from = (forward ? travel : -travel) * (rtl ? -1 : 1);
    return AnimatedSwitcher(
      duration: AppMotion.of(context).base,
      switchInCurve: AppEase.out,
      switchOutCurve: AppEase.out,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        final entering = child.key == this.child.key;
        final offset = Tween<Offset>(begin: Offset(entering ? from : -from, 0), end: Offset.zero).animate(animation);
        return FadeTransition(opacity: animation, child: SlideTransition(position: offset, child: child));
      },
      child: child,
    );
  }
}

/// The letter that marks an option: أ ب ج … in Arabic, A B C … in English, a number past the alphabet.
String examOptionMark(int i) {
  const ar = ['أ', 'ب', 'ج', 'د', 'هـ', 'و', 'ز', 'ح', 'ط', 'ي'];
  return t(i < ar.length ? ar[i] : '${i + 1}', i < 26 ? String.fromCharCode(65 + i) : '${i + 1}');
}

class ExamQuestionCard extends StatefulWidget {
  const ExamQuestionCard({super.key, required this.question, required this.section, required this.enabled, required this.onAnswer, this.onPickFile, this.attemptId, this.mediaApi, this.imageBytes, this.imageOmitted = false, this.number});
  final PaperQuestion question;
  final PaperSection section;
  final bool enabled;
  final void Function(Map<String, dynamic> answer) onAnswer;

  /// `file_upload`: pick and upload the answer file.
  final VoidCallback? onPickFile;

  /// The attempt the paper belongs to: with it the question's image is shown (null = no image, e.g. offline sittings).
  final int? attemptId;
  final QuestionMediaApi? mediaApi;

  /// Offline sittings: the image's bytes handed in directly (from the decrypted package), and [imageOmitted] when the
  /// package left the image out, which shows its alt text. Used only when [attemptId] is null.
  final Uint8List? imageBytes;
  final bool imageOmitted;

  /// The question's number on the whole paper (null = its place in its section).
  final int? number;

  @override
  State<ExamQuestionCard> createState() => _ExamQuestionCardState();
}

class _ExamQuestionCardState extends State<ExamQuestionCard> {
  /// An ordering list taller than this many rows scrolls inside the sheet.
  static const double _orderRowsShown = 6.5;

  /// The unit picker beside a numeric answer.
  static const double _unitWidth = AppTouch.min * 2.5;

  late TextEditingController _text;
  late List<TextEditingController> _blanks;
  late TextEditingController _unit;

  @override
  void initState() {
    super.initState();
    final a = widget.question.answer ?? const {};
    _text = TextEditingController(text: '${a['text'] ?? a['value'] ?? ''}');
    _unit = TextEditingController(text: '${a['unit'] ?? ''}');
    final n = (widget.question.body['blanks_count'] as num?)?.toInt() ?? RegExp(r'_{3,}').allMatches(widget.question.prompt).length.clamp(1, 20);
    final saved = (a['blanks'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    _blanks = List.generate(n, (i) => TextEditingController(text: i < saved.length ? saved[i] : ''));
  }

  @override
  void dispose() {
    _text.dispose();
    _unit.dispose();
    for (final b in _blanks) {
      b.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = widget.question;
    final a = q.answer ?? const {};
    final points = q.points == q.points.roundToDouble() ? q.points.toInt().toString() : q.points.toString();
    return ExamPageWidth(
      width: AppWidth.reading,
      builder: (side) => ListView(padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.xl), children: [
        if (widget.section.title.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, bottom: AppSpace.sm),
            child: Row(children: [
              Expanded(
                child: Text(widget.section.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
              ),
              if (widget.section.oneWay) ...[
                const SizedBox(width: AppSpace.xs),
                Flexible(child: AppStatusBadge(label: t('اتجاه واحد', 'one way'), icon: Icons.arrow_forward_rounded, dense: true)),
              ],
            ]),
          ),
        // the question on its own sheet of paper: the number in the editorial face, the marks, then the prompt
        Material(
          color: c.cardBg,
          elevation: 0,
          shadowColor: c.shadowTone,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.cardWide),
            side: BorderSide(color: c.kit.line, width: AppBorder.strong),
          ),
          child: Padding(
            padding: AppSpace.block,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                ExcludeSemantics(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: AppDashSize.glyph, minHeight: AppDashSize.glyph),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                    decoration: BoxDecoration(color: AppAreaScope.of(context).tint, borderRadius: BorderRadius.circular(AppRadius.glyph)),
                    child: Text(appDigits('${widget.number ?? q.index + 1}'),
                        style: AppType.label(context).copyWith(color: AppAreaScope.of(context).ink, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(examTypeHint(q.type, points),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(color: AppAreaScope.of(context).ink, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: AppSpace.md),
              Text(q.prompt, style: AppType.section(context).copyWith(fontFamilyFallback: AppFonts.fallback)),
              if (q.image != null && widget.attemptId != null) ...[
                const SizedBox(height: AppSpace.md),
                Center(child: QuestionImage.attempt(attemptId: widget.attemptId!, media: QuestionMedia(q.image!.id, q.image!.alt), api: widget.mediaApi)),
              ],
              if (q.image != null && widget.attemptId == null && (widget.imageBytes != null || widget.imageOmitted)) ...[
                const SizedBox(height: AppSpace.md),
                Center(child: _InlineQuestionImage(bytes: widget.imageBytes, alt: q.image!.alt)),
              ],
              const SizedBox(height: AppSpace.lg),
              ..._body(context, q, a),
            ]),
          ),
        ),
      ]),
    );
  }

  List<Widget> _body(BuildContext context, PaperQuestion q, Map<String, dynamic> a) {
    final enabled = widget.enabled;
    switch (q.type) {
      case 'mcq_single':
        return [
          for (final (i, o) in q.options.indexed)
            ExamOptionTile(text: '${o['text'] ?? o['id']}', mark: examOptionMark(i), selected: '${a['option'] ?? ''}' == '${o['id']}',
                onTap: enabled ? () => widget.onAnswer(encodeSingle('${o['id']}')) : null),
        ];
      case 'mcq_multi':
        final chosen = ((a['options'] as List?) ?? const []).map((e) => '$e').toSet();
        return [
          for (final (i, o) in q.options.indexed)
            ExamOptionTile(text: '${o['text'] ?? o['id']}', mark: examOptionMark(i), selected: chosen.contains('${o['id']}'), multi: true,
                onTap: enabled ? () {
                  final next = Set<String>.from(chosen);
                  next.contains('${o['id']}') ? next.remove('${o['id']}') : next.add('${o['id']}');
                  widget.onAnswer(encodeMulti(next));
                } : null),
        ];
      case 'true_false':
        return [Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ExamOptionTile(text: t('صح', 'True'), markIcon: Icons.check_rounded, selected: a['value'] == true,
              onTap: enabled ? () => widget.onAnswer(encodeTrueFalse(true)) : null)),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: ExamOptionTile(text: t('خطأ', 'False'), markIcon: Icons.close_rounded, selected: a['value'] == false,
              onTap: enabled ? () => widget.onAnswer(encodeTrueFalse(false)) : null)),
        ])];
      case 'fill_blank':
        return [
          for (var i = 0; i < _blanks.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: AppField(
                controller: _blanks[i],
                enabled: enabled,
                label: t('الفراغ ${i + 1}', 'Blank ${i + 1}'),
                onChanged: (_) => widget.onAnswer(encodeBlanks([for (final b in _blanks) b.text])),
              ),
            ),
        ];
      case 'matching':
        final left = ((q.body['left'] as List?) ?? const []).map((e) => '$e').toList();
        final right = ((q.body['right'] as List?) ?? const []).map((e) => '$e').toList();
        final pairs = Map<String, String>.from(((a['pairs'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')));
        return [
          for (final l in left)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Row(children: [
                Expanded(child: Text(l, style: AppType.row(context))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                  child: Icon(Icons.arrow_forward_rounded, size: AppIconSize.sm, color: context.colors.textLight),
                ),
                Expanded(child: AppDropdown<String>(
                  value: pairs[l],
                  items: [for (final r in right) DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))],
                  onChanged: enabled ? (v) { if (v != null) widget.onAnswer(encodeMatching({...pairs, l: v})); } : null,
                )),
              ]),
            ),
        ];
      case 'ordering':
        final items = ((q.body['items'] as List?) ?? const []).map((e) => '$e').toList();
        final order = ((a['order'] as List?) ?? items).map((e) => '$e').toList();
        const row = AppTouch.primary + AppSpace.xs;
        return [SizedBox(
          height: (order.length * row).toDouble().clamp(row, row * _orderRowsShown),
          child: ReorderableListView(
            buildDefaultDragHandles: enabled,
            onReorder: (from, to) {
              final next = List<String>.from(order);
              final item = next.removeAt(from);
              next.insert(to > from ? to - 1 : to, item);
              widget.onAnswer(encodeOrdering(next));
            },
            children: [
              for (var i = 0; i < order.length; i++)
                Padding(
                  key: ValueKey('ord.${order[i]}'),
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: _OrderRow(position: i + 1, text: order[i]),
                ),
            ],
          ),
        )];
      case 'numeric':
        final units = ((q.body['units'] as List?) ?? const []).map((e) => '$e').toList();
        return [Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: AppField(controller: _text, enabled: enabled, label: t('القيمة', 'Value'), ltr: true,
              keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: (v) => widget.onAnswer(encodeNumeric(v, unit: _unit.text)))),
          if (units.isNotEmpty) ...[
            const SizedBox(width: AppSpace.sm),
            SizedBox(width: _unitWidth, child: AppDropdown<String>(
              value: _unit.text.isEmpty ? null : _unit.text,
              items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: enabled ? (u) { _unit.text = u ?? ''; widget.onAnswer(encodeNumeric(_text.text, unit: _unit.text)); } : null,
            )),
          ],
        ])];
      case 'short_answer':
      case 'essay':
        return [TextField(controller: _text, enabled: enabled, minLines: q.type == 'essay' ? 6 : 2, maxLines: q.type == 'essay' ? 20 : 4,
            style: appFieldTextStyle(context),
            decoration: appFieldDecoration(context, hint: t('اكتب إجابتك هنا', 'Write your answer here'), enabled: enabled),
            onChanged: (v) => widget.onAnswer(encodeText(v)))];
      case 'file_upload':
        final file = a['file'] is Map ? asMap(a['file']) : null;
        return [
          if (file != null) ...[
            AppBanner(icon: Icons.task_alt_rounded, color: context.colors.success, text: '${file['name'] ?? ''}'),
            const SizedBox(height: AppSpace.sm),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.secondary(
              onPressed: enabled ? widget.onPickFile : null,
              icon: Icons.upload_file_rounded,
              label: file == null ? t('ارفع ملف إجابتك (PDF أو Word أو صورة)', 'Upload your answer (PDF, Word or a photo)') : t('استبدال الملف', 'Replace the file'),
            ),
          ),
        ];
      default:
        return [AppBanner(icon: Icons.info_outline_rounded, text: t('هذا النوع من الأسئلة يُجاب عليه ورقياً', 'This question type is answered on paper'))];
    }
  }
}

/// One choice of a question: a well on the paper with its letter (or [markIcon]) in a ring; chosen, the well takes
/// the primary tint and the ring fills with a check (a square box for a multi-choice question), so the choice reads
/// by shape as well as colour.
/// One choice of a question (redesign S-C, Stu2Exams?screen=take): its letter (or [markIcon]) in a box of the area
/// tint at the start, a ring at the end; chosen, the well takes the area tint on an area edge, the letter box fills
/// and the ring fills with a check that pops in (M3), so the choice reads by shape as well as colour (a square ring
/// for a multi-choice question). A press squashes (M9).
class ExamOptionTile extends StatelessWidget {
  const ExamOptionTile({super.key, required this.text, required this.selected, this.mark, this.markIcon, this.multi = false, this.onTap});
  final String text;
  final bool selected;
  final String? mark;
  final IconData? markIcon;
  final bool multi;
  final VoidCallback? onTap;

  static const double _markSize = AppSpace.xl + AppSpace.xxs;
  static const double _ringSize = AppSpace.lg + AppSpace.xxs;

  /// From this row width the ring at the end is drawn (below it the letter box carries the check).
  static const double _wideFrom = AppTouch.min * 7;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final motion = AppMotion.of(context);
    final enabled = onTap != null;
    final ringRadius = multi ? BorderRadius.circular(AppSpace.xs) : BorderRadius.circular(AppRadius.pill);
    final markBox = AnimatedContainer(
      duration: motion.fast,
      curve: AppEase.out,
      width: _markSize,
      height: _markSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: selected ? set.a : set.tint, borderRadius: BorderRadius.circular(AppRadius.glyph)),
      child: markIcon != null
          ? Icon(markIcon, size: AppIconSize.md, color: selected ? c.onHero : set.ink)
          : Text(mark ?? '', style: AppType.bodyStrong(context).copyWith(color: selected ? c.onHero : set.ink)),
    );
    // a narrow row keeps the words: the end ring folds into the letter box (it fills and the check shows there)
    Widget markFor(bool narrow) => !narrow || !selected
        ? markBox
        : AnimatedContainer(
            duration: motion.fast,
            width: _markSize,
            height: _markSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: set.a, borderRadius: BorderRadius.circular(AppRadius.glyph)),
            child: Icon(Icons.check_rounded, size: AppIconSize.md, color: c.onHero),
          );
    final ring = AnimatedContainer(
      duration: motion.fast,
      curve: AppEase.out,
      width: _ringSize,
      height: _ringSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? set.a : c.cardBg,
        borderRadius: ringRadius,
        border: Border.all(color: selected ? set.a : set.tint, width: AppBorder.focus),
      ),
      child: selected ? Icon(Icons.check_rounded, size: AppIconSize.sm, color: c.onHero) : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Semantics(
        container: true,
        button: true,
        enabled: enabled,
        checked: selected,
        inMutuallyExclusiveGroup: !multi,
        label: text,
        excludeSemantics: true,
        onTap: onTap,
        child: AppJelly(
          enabled: enabled,
          wide: true,
          child: AnimatedContainer(
            duration: motion.fast,
            curve: AppEase.out,
            decoration: BoxDecoration(
              color: selected ? set.tint : c.cardBg,
              borderRadius: BorderRadius.circular(AppRadius.tile),
              border: Border.all(color: selected ? set.a : c.kit.line, width: AppBorder.strong),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppRadius.tile),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.primary),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
                    child: LayoutBuilder(builder: (context, box) {
                      final narrow = box.maxWidth < _wideFrom;
                      return Row(children: [
                        markFor(narrow),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(text,
                              style: AppType.row(context).copyWith(
                                  color: enabled || selected ? c.textDark : c.textMedium, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                        ),
                        if (!narrow) ...[
                          const SizedBox(width: AppSpace.sm),
                          AppPop(trigger: selected, child: ring),
                        ],
                      ]);
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of an ordering question: its place, the text, the drag handle.
class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.position, required this.text});
  final int position;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: AppTouch.primary),
      padding: const EdgeInsetsDirectional.only(start: AppSpace.md, end: AppSpace.xs),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.controlAll, border: Border.all(color: c.divider, width: AppBorder.hairline)),
      child: Row(children: [
        Text('$position', style: AppType.figure(context).copyWith(color: c.textMedium, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
        Icon(Icons.drag_handle_rounded, color: c.textLight),
      ]),
    );
  }
}

class ExamNavBar extends StatelessWidget {
  const ExamNavBar({super.key, required this.index, required this.total, required this.canBack, required this.submitting, required this.onBack,
      required this.onNext, required this.onJump, required this.answered, required this.questionIds, required this.onSubmit});
  final int index;
  final int total;
  final bool canBack;
  final bool submitting;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final void Function(int index) onJump;
  final Map<int, bool> answered;
  final List<int> questionIds;
  final VoidCallback? onSubmit;

  /// Below this many touch targets of width (scaled with the text) the list of questions folds to its glyph.
  static const double narrowAt = 7;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = index >= total - 1;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
      child: SafeArea(
        top: false,
        child: ExamPageWidth(width: AppWidth.reading, builder: (side) => Padding(
          // in line with the question sheet above it (the icon button brings its own inset)
          padding: EdgeInsets.symmetric(horizontal: side - AppSpace.xxs, vertical: AppSpace.xs),
          child: LayoutBuilder(builder: (context, box) {
            // a narrow row (a small phone, large text): the question list keeps its glyph and tooltip, Next / Submit
            // keep their words
            final narrow = box.maxWidth < AppTouch.min * narrowAt * MediaQuery.textScalerOf(context).scale(1);
            void openGrid() => showAppSheet<void>(context, (_) => AppSheetContent(title: t('الأسئلة', 'Questions'), children: [
                  ExamQuestionGrid(answered: answered, questionIds: questionIds, current: index, onJump: (i) {
                    Navigator.pop(context);
                    onJump(i);
                  }),
                ]));
            final primary = !last
                ? AppButton.primary(onPressed: onNext, label: t('التالي', 'Next'), trailingIcon: Icons.chevron_right_rounded)
                : AppButton.hot(
                    key: const ValueKey('exam.submit'),
                    busy: submitting,
                    onPressed: submitting ? null : onSubmit,
                    icon: Icons.send_rounded,
                    label: t('سلّم الاختبار', 'Hand in the exam'),
                  );
            return Row(children: [
              AppIconButton(onPressed: canBack ? onBack : null, icon: Icons.chevron_left_rounded, tooltip: t('السابق', 'Back')),
              const SizedBox(width: AppSpace.xxs),
              if (narrow)
                AppIconButton(onPressed: openGrid, icon: Icons.grid_view_rounded, tooltip: t('الأسئلة', 'Questions'), variant: AppIconButtonVariant.tonal)
              else
                Expanded(
                  child: AppButton.secondary(expand: true, onPressed: openGrid, icon: Icons.grid_view_rounded, label: t('الأسئلة', 'Questions')),
                ),
              const SizedBox(width: AppSpace.xs),
              if (narrow)
                // the words never clip: on the narrowest rows the button scales down to the room it has
                Expanded(child: Align(alignment: AlignmentDirectional.centerEnd, child: FittedBox(fit: BoxFit.scaleDown, child: primary)))
              else
                // "Hand in the exam" is longer than Next: it never pushes the row past the edge
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                  child: FittedBox(fit: BoxFit.scaleDown, child: primary),
                ),
            ]);
          }),
        )),
      ),
    );
  }
}

class ExamQuestionGrid extends StatelessWidget {
  const ExamQuestionGrid({super.key, required this.answered, required this.questionIds, required this.current, required this.onJump});
  final Map<int, bool> answered;
  final List<int> questionIds;
  final int current;
  final void Function(int index) onJump;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      for (var i = 0; i < questionIds.length; i++)
        Builder(builder: (context) {
          final done = answered[questionIds[i]] == true;
          final here = i == current;
          final fill = done ? appTintOn(context, c.primary) : c.cardBg;
          return Semantics(
            button: true,
            selected: here,
            label: done ? t('السؤال ${i + 1}، تمت الإجابة', 'Question ${i + 1}, answered')
                : t('السؤال ${i + 1}، بلا إجابة', 'Question ${i + 1}, not answered'),
            excludeSemantics: true,
            child: Material(
              color: fill,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.controlAll,
                side: BorderSide(color: here ? c.textDark : (done ? c.primary : c.divider), width: here ? AppBorder.focus : AppBorder.hairline),
              ),
              child: InkWell(
                onTap: () => onJump(i),
                customBorder: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
                child: SizedBox(
                  width: AppTouch.min + AppSpace.xs,
                  height: AppTouch.min + AppSpace.xs,
                  child: Stack(alignment: Alignment.center, children: [
                    Text('${i + 1}',
                        style: AppType.label(context).copyWith(
                            color: done ? appInkOn(context, c.primary, fill) : c.textDark,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    if (done)
                      PositionedDirectional(
                        top: AppSpace.xxs,
                        end: AppSpace.xxs,
                        child: Icon(Icons.check_rounded, size: AppIconSize.xs, color: appInkOn(context, c.primary, fill)),
                      ),
                  ]),
                ),
              ),
            ),
          );
        }),
    ]);
  }
}

/// An image given as bytes (no network): drawn at the same size as the online one; no bytes = the alt text in a calm tile.
class _InlineQuestionImage extends StatelessWidget {
  const _InlineQuestionImage({required this.bytes, required this.alt});
  final Uint8List? bytes;
  final String alt;

  static const double _maxHeight = 260;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = alt.isEmpty ? t('صورة السؤال', 'Question image') : alt;
    Widget missing() => Container(
          constraints: const BoxConstraints(minWidth: AppTouch.min * 2),
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.controlAll, border: Border.all(color: c.divider, width: AppBorder.hairline)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.image_not_supported_outlined, color: c.textLight),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: Text(alt.isEmpty ? t('الصورة غير متاحة دون اتصال', 'Image not available offline') : alt, style: AppType.meta(context), maxLines: 4, overflow: TextOverflow.ellipsis)),
          ]),
        );
    if (bytes == null) return missing();
    return ClipRRect(
      borderRadius: AppRadius.controlAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxHeight),
        // decoded at the box's height, not the photo's (a 4000 x 3000 picture is ~48 MB as pixels)
        child: Image.memory(bytes!, fit: BoxFit.contain, gaplessPlayback: true, height: _maxHeight, cacheHeight: (_maxHeight * MediaQuery.devicePixelRatioOf(context)).round(),
            semanticLabel: label, errorBuilder: (_, _, _) => missing()),
      ),
    );
  }
}

/// The line beside a question's number: what to do and what it is worth ("Choose, 2 marks").
String examTypeHint(String type, String points) {
  final what = switch (type) {
    'mcq_single' => t('اختر', 'Choose'),
    'mcq_multi' => t('اختر كل الصح', 'Choose all that apply'),
    'true_false' => t('صح أو خطأ', 'True or false'),
    'fill_blank' => t('أكمل الفراغ', 'Fill the blank'),
    'matching' => t('وصّل', 'Match'),
    'ordering' => t('رتّب', 'Put in order'),
    'numeric' => t('اكتب الرقم', 'Write the number'),
    'short_answer' || 'essay' => t('اكتب إجابتك', 'Write your answer'),
    'file_upload' => t('ارفع حلّك', 'Upload your answer'),
    _ => t('على الورق', 'On paper'),
  };
  final marks = points == '1' ? t('درجة', 'mark') : (points == '2' ? t('درجتين', '2 marks') : t('$points درجات', '$points marks'));
  return appDigits(t('$what، $marks', '$what, $marks'));
}

/// "Hand in now?" (redesign S-C, Stu2Exams?sheet=submit): answered · left, the first question left unanswered (it
/// counts as zero) and the time still left, then "Yes, hand in" (forward) and "Back to the questions". Pops true on
/// hand in.
class ExamSubmitSheet extends StatelessWidget {
  const ExamSubmitSheet({super.key, required this.answered, required this.left, this.firstLeft, this.remainingSeconds});

  final int answered;
  final int left;

  /// The number of the first question with no answer.
  final int? firstLeft;

  /// Null on an untimed exam.
  final int? remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final k = context.colors.kit;
    Widget figure(int n, String label, KitTone tone) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.md),
            decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
            child: Column(children: [
              Text(appDigits('$n'), style: AppType.figureLarge(context).copyWith(color: tone.ink)),
              const SizedBox(height: AppSpace.xxs),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: tone.ink)),
            ]),
          ),
        );
    Widget note(IconData icon, String text, KitTone tone) => Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
          child: Row(children: [
            Icon(icon, size: AppIconSize.md, color: tone.ink),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(appDigits(text), style: AppType.label(context).copyWith(color: tone.ink, fontWeight: FontWeight.w600))),
          ]),
        );
    final mins = remainingSeconds == null ? null : (remainingSeconds! / 60).ceil();
    return AppSheetContent(title: t('تسلّم الحين؟', 'Hand in now?'), children: [
      Row(children: [
        figure(answered, t('جاوبتها', 'Answered'), AppAreaScope.of(context).tone),
        const SizedBox(width: AppSpace.sm),
        figure(left, t('باقي', 'Left'), k.live),
      ]),
      if (firstLeft != null) ...[
        AppSpace.gapSm,
        note(Icons.warning_amber_rounded,
            left == 1
                ? t('سؤال $firstLeft ما جاوبته، ينحسب صفر', "Question $firstLeft has no answer, it counts as zero")
                : t('${countText(left, ar1: 'سؤال', ar2: 'سؤالين', arFew: '{n} أسئلة', arMany: '{n} سؤال', en1: '1 question', en: '{n} questions')} ما جاوبتها، تنحسب صفر',
                    '${countText(left, ar1: 'سؤال', ar2: 'سؤالين', arFew: '{n} أسئلة', arMany: '{n} سؤال', en1: '1 question', en: '{n} questions')} with no answer count as zero'),
            k.live),
      ],
      if (mins != null && mins > 0) ...[
        AppSpace.gapSm,
        note(
            Icons.schedule_rounded,
            t('باقي لك ${countText(mins, ar1: 'دقيقة', ar2: 'دقيقتين', arFew: '{n} دقائق', arMany: '{n} دقيقة', en1: '1 minute', en: '{n} minutes')}',
                '${countText(mins, ar1: '', arFew: '', en1: '1 minute', en: '{n} minutes')} left'),
            AppAreaScope.of(context).tone),
      ],
      AppSpace.gapMd,
      AppButton.hot(key: const ValueKey('exam.submit.confirm'), label: t('إيه، سلّم', 'Yes, hand in'), expand: true, onPressed: () => Navigator.pop(context, true)),
      AppSpace.gapXs,
      AppButton.secondary(label: t('ارجع للأسئلة', 'Back to the questions'), expand: true, onPressed: () => Navigator.pop(context, false)),
    ]);
  }
}
