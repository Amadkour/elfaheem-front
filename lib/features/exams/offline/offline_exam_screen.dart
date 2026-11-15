// Offline sittings, student side: the list of exams kept on the phone, the flow that opens one (key from the server
// when online, else from a nearby phone), the taking screen (no network at all) and the status after finishing.
//
// Statuses the student sees: downloaded → in progress → saved on this phone → waiting to sync → submitted.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/core/screen_security.dart';
import 'package:flutter_education_app/core/live_focus.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asMap, t;
import 'package:flutter_education_app/features/attendance/relay_host_provider.dart';
import 'package:flutter_education_app/features/exams/exam_integrity.dart';
import 'package:flutter_education_app/features/exams/exam_taking.dart';
import 'package:flutter_education_app/features/exams/exam_page_width.dart';
import 'package:flutter_education_app/features/exams/exam_taking_screen.dart' show ExamNavBar, ExamProgressBar, ExamQuestionCard, ExamQuestionSwap, ExamTimerChip;
import 'package:flutter_education_app/features/exams/offline/offline_exam_core.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_relay.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_service.dart';

final _store = OfflineExamStore.instance;
final _sync = OfflineExamSync.instance;

/// The relay host, to keep this phone visible to classmates while an offline exam screen is open, so it can hand the
/// exam on and carry their answers (the attendance relay). Null when there is none (tests, the web).
RelayHostProvider? _hostOf(BuildContext context) {
  if (!offlineExamsSupported) return null;
  try {
    return context.read<RelayHostProvider>();
  } catch (_) {
    return null;
  }
}

Future<int?> _studentId() => offlineStudentId();

/// A sitting already begun on this phone for [exam] (an online start would cost the student a second attempt): the
/// list opens it instead. Null when there is none.
Future<OfflinePackage?> offlineSittingFor(int examId) async {
  if (!offlineExamsSupported) return null;
  final sid = await _studentId();
  final s = sid == null ? null : await _store.sitting(examId, sid);
  if (s == null || s.stage == OfflineStage.downloaded) return null;
  return _store.package(s.examId, s.n);
}

// ═══════════════════════════════════════════ opening a sitting ═══════════════════════════════════════════════

/// The one entry point: resume, show the status, or get the key and start.
Future<void> openOfflineExam(BuildContext context, OfflinePackage p) async {
  final sid = await _studentId();
  if (!context.mounted) return;
  if (sid == null) return appToast(t('سجّل الدخول مرة واحدة متصلاً بالإنترنت أولاً', 'Sign in once while online first'), error: true);
  final s = await _store.sitting(p.examId, sid);
  if (!context.mounted) return;
  if (s != null && s.stage != OfflineStage.downloaded) {
    if (s.stage == OfflineStage.inProgress) return _resume(context, s);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => OfflineExamStatusScreen(sitting: s, title: p.title)));
    return;
  }
  var key = await _store.examKey(p.examId, p.n);
  if (key == null) {
    final r = await _sync.api.package(p.examId);           // online: the server releases the key inside the window
    final fresh = r.ok ? await _sync.savePackageReply(r.map, from: 'server') : null;
    if (fresh != null && fresh.n != p.n && context.mounted) return openOfflineExam(context, fresh);   // the exam changed: the new copy
    key = await _store.examKey(p.examId, p.n);
  }
  if (key == null && context.mounted) {
    final got = await _fetchNearby(context, examId: p.examId, expectedHash: p.hash);
    if (got?.package != null && got!.package!.n == p.n) key = await _store.examKey(p.examId, p.n);
  }
  if (!context.mounted) return;
  if (key == null) {
    final now = DateTime.now();
    return appToast(offlineCodeText(p.startsAt != null && now.isBefore(p.startsAt!) ? 'not_started' : 'no_key'), error: true);
  }
  if (p.endsAt != null && !DateTime.now().isBefore(p.endsAt!)) return appToast(offlineCodeText('exam_ended'), error: true);
  final go = await appConfirm(context,
      message: t('بدء الاختبار الآن؟ يبدأ المؤقت وتُحفظ إجاباتك على هذا الجهاز حتى تُرسل.', 'Start the exam now? The timer starts and your answers are kept on this phone until they are sent.'),
      confirmLabel: t('ابدأ', 'Start'));
  if (!go || !context.mounted) return;
  final from = asMap(p.json['_from']), keyFrom = asMap(p.json['_key_from']);
  final sitting = OfflineSitting(examId: p.examId, n: p.n, packageHash: p.hash, studentId: sid, bundleId: newBundleId(),
      stage: OfflineStage.inProgress, clock: OfflineClock(startedWallMs: DateTime.now().millisecondsSinceEpoch))
    ..step('package', from: '${from['from'] ?? 'server'}', by: from['by'] as int?)
    ..step('key', from: '${keyFrom['from'] ?? 'server'}', by: keyFrom['by'] as int?)
    ..step('started');
  await _store.saveSitting(sitting);
  if (context.mounted) await _resume(context, sitting);
}

Future<void> _resume(BuildContext context, OfflineSitting s) async {
  final p = await _store.package(s.examId, s.n);
  final key = await _store.examKey(s.examId, s.n);
  if (p == null || key == null) return appToast(offlineCodeText('bad_package'), error: true);
  final Map<String, dynamic> content;
  try {
    content = await openPackage(p, key);
  } catch (_) {
    return appToast(offlineCodeText('bad_key'), error: true);
  }
  if (!context.mounted) return;
  // the sitting is full-screen: on the root navigator, above any tab bar (D-081)
  await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => OfflineExamTakingScreen(package: p, content: content, sitting: s)));
}

/// Looks for a nearby phone with this exam (and its key) while a small progress dialog is shown.
Future<NearbyExam?> _fetchNearby(BuildContext context, {int? examId, String? expectedHash}) async {
  final progress = ValueNotifier<double?>(null);
  BuildContext? dialog;
  var finished = false;
  void close() {
    final d = dialog;
    dialog = null;
    if (d != null && d.mounted) Navigator.of(d).pop();
  }

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      if (dialog == null && !finished) dialog = ctx;       // the builder may run again: remember the first context only
      if (finished) WidgetsBinding.instance.addPostFrameCallback((_) => ctx.mounted ? Navigator.of(ctx).pop() : null);
      return AlertDialog(
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: v),
            const SizedBox(height: 14),
            Text(v == null ? t('البحث عن جهاز قريب لديه الاختبار…', 'Looking for a nearby phone that has the exam…') : t('جارٍ الاستلام…', 'Receiving…'),
                textAlign: TextAlign.center),
          ]),
        ),
      );
    },
  ));
  final r = await OfflineExamRelayClient().fetch(examId: examId, expectedHash: expectedHash, progress: (v) => progress.value = v);
  if (r.package != null) {
    // where it came from is part of the delivery chain the teacher sees
    final from = {'from': r.role == 'teacher' ? 'teacher' : 'peer', 'by': r.by};
    final j = r.package!.json;
    j['_from'] ??= from;
    if (r.keyed) j['_key_from'] ??= from;
    await _store.savePackage(r.package!);
  }
  finished = true;
  close();
  if (r.code != null && r.code != 'no_key' && context.mounted) appToast(offlineCodeText(r.code), error: r.package == null);
  return r;
}

// ═══════════════════════════════════════════ the list ════════════════════════════════════════════════════════

/// Plain-values card of one exam kept on the phone (under the layout harness).
class OfflineExamCard extends StatelessWidget {
  const OfflineExamCard({super.key, required this.title, required this.stage, required this.hasKey, required this.questions,
      this.durationMinutes, this.startsAt, this.onTap});
  final String title;
  final OfflineStage stage;
  final bool hasKey;
  final int questions;
  final int? durationMinutes;
  final DateTime? startsAt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = switch (stage) {
      OfflineStage.submitted => AppTone.success,
      OfflineStage.rejected => AppTone.danger,
      OfflineStage.waitingToSync => AppTone.warning,
      _ => AppTone.brand,
    };
    final color = appToneColor(context, tone);
    final tint = appTintOn(context, color);
    final meta = AppType.meta(context);
    return AppCard(
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: AppTouch.min, height: AppTouch.min, alignment: Alignment.center,
          decoration: BoxDecoration(color: tint, borderRadius: AppRadius.controlAll),
          child: Icon(switch (stage) {
            OfflineStage.submitted => Icons.cloud_done_rounded,
            OfflineStage.rejected => Icons.error_outline_rounded,
            OfflineStage.waitingToSync => Icons.cloud_upload_rounded,
            _ => Icons.offline_pin_rounded,
          }, size: AppIconSize.lg, color: appInkOn(context, color, tint)),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
              Text(t('$questions سؤال', '$questions questions'), style: meta),
              if (durationMinutes != null) Text(t('$durationMinutes دقيقة', '$durationMinutes min'), style: meta),
              if (startsAt != null) Text(AppTime.dateTime(startsAt!), style: meta),
            ]),
            const SizedBox(height: AppSpace.sm),
            Align(alignment: AlignmentDirectional.centerStart, child: AppStatusBadge(label: offlineStageText(stage, hasKey: hasKey), tone: tone)),
          ]),
        ),
      ]),
    );
  }
}

/// Every exam kept on this phone (optionally one course's), with "get an exam from a nearby phone". Used by the
/// Downloads screen and under a course's exams when there is no connection.
class OfflineExamsList extends StatefulWidget {
  const OfflineExamsList({super.key, this.courseId, this.shrinkWrap = false});
  final int? courseId;
  final bool shrinkWrap;

  @override
  State<OfflineExamsList> createState() => _OfflineExamsListState();
}

class _OfflineExamsListState extends State<OfflineExamsList> {
  List<(OfflinePackage, OfflineSitting?, bool)>? _rows;
  late final RelayHostProvider? _host = _hostOf(context);

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _host?.holdForCheckIn() : null);
  }

  @override
  void dispose() {
    _host?.releaseCheckIn();
    super.dispose();
  }

  Future<void> _load() async {
    if (!offlineExamsSupported) return;                      // the web keeps nothing on the device
    final sid = await _studentId();
    final rows = <(OfflinePackage, OfflineSitting?, bool)>[];
    for (final p in await _store.packages()) {
      if (widget.courseId != null && p.courseId != widget.courseId) continue;
      final s = sid == null ? null : await _store.sitting(p.examId, sid);
      rows.add((p, s, await _store.examKey(p.examId, p.n) != null));
    }
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _nearby() async {
    final r = await _fetchNearby(context);
    if (r?.package != null) await _load();
  }

  Future<void> _open(OfflinePackage p) async {
    await openOfflineExam(context, p);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!offlineExamsSupported) return const SizedBox.shrink();
    final rows = _rows;
    if (rows == null) return const AppListSkeleton(items: 2);
    final children = [
      AppSectionTitle(t('اختبارات دون اتصال', 'Offline exams'),
          subtitle: t('تُحل دون إنترنت وتُرسل عند الاتصال', 'Solved without internet, sent when online')),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppBanner(icon: Icons.info_outline_rounded,
              text: t('لا يوجد اختبار محفوظ على هذا الجهاز. اقترب من زميل أو من المعلم لاستلامه.',
                  'No exam is kept on this phone. Move close to a classmate or the teacher to receive it.')),
        ),
      for (final (i, (p, s, keyed)) in rows.indexed)
        AppReveal(
          index: i,
          group: 'exam.offline.list',
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: OfflineExamCard(title: p.title, stage: s?.stage ?? OfflineStage.downloaded, hasKey: keyed, questions: p.questions,
                durationMinutes: p.durationMinutes, startsAt: p.startsAt, onTap: () => _open(p)),
          ),
        ),
      AppButton.secondary(
        onPressed: _nearby,
        expand: true,
        icon: Icons.bluetooth_searching_rounded,
        label: t('استلام اختبار من جهاز قريب', 'Get an exam from a nearby phone'),
      ),
    ];
    if (widget.shrinkWrap) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl), physics: const AlwaysScrollableScrollPhysics(), children: children),
    );
  }
}

// ═══════════════════════════════════════════ taking (no network) ═════════════════════════════════════════════

class OfflineExamTakingScreen extends StatefulWidget {
  const OfflineExamTakingScreen({super.key, required this.package, required this.content, required this.sitting});
  final OfflinePackage package;
  final Map<String, dynamic> content;
  final OfflineSitting sitting;

  @override
  State<OfflineExamTakingScreen> createState() => _OfflineExamTakingScreenState();
}

class _OfflineExamTakingScreenState extends State<OfflineExamTakingScreen> {
  late final Paper _paper;
  late final PackageMedia _media = PackageMedia.fromContent(widget.content);
  late final OfflineSitting _s;
  late final ExamIntegrity _integrity;
  final _sw = Stopwatch()..start();
  int _lastMono = 0;
  Timer? _ticker;
  int _ticks = 0;
  int _index = 0;
  bool _finishing = false;
  late final RelayHostProvider? _host = _hostOf(context);

  @override
  void initState() {
    super.initState();
    _s = widget.sitting;
    // one copy for the hall, a paper per student: pool, question and option order from "<package>|<student>"
    _paper = Paper.fromJson(studentPaper(asMap(widget.content['paper']), widget.package.packageId, _s.studentId));
    for (final q in _paper.all) {
      q.answer = _s.answers[q.questionId];
      q.saveSeq = _s.seq[q.questionId] ?? 0;
    }
    final clock = _s.clock ??= OfflineClock(startedWallMs: DateTime.now().millisecondsSinceEpoch);
    if (clock.elapsedMs > 0) {
      _s.event('resumed');
      final ev = clock.resume(wallNowMs: DateTime.now().millisecondsSinceEpoch);
      if (ev != null) _s.events.add(ev);
    }
    _integrity = ExamIntegrity((kind, meta) => _s.event(kind, meta: meta))..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _protect(true);
    LiveFocus.enterExam(this); // no must-acknowledge card over a live exam (D-977)
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _host?.holdForCheckIn() : null);
    _save();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _integrity.stop();
    _protect(false);
    LiveFocus.leaveExam(this);
    _host?.releaseCheckIn();
    _save();
    super.dispose();
  }

  /// Owned through ScreenSecurity (D-083): another protected screen closing never switches this one off.
  Future<void> _protect(bool on) => on ? ScreenSecurity.instance.protect(this) : ScreenSecurity.instance.release(this);

  Future<void> _save() => _store.saveSitting(_s);

  int? get _left => _s.clock!.remainingSeconds(durationMinutes: widget.package.durationMinutes, endsAt: widget.package.endsAt, wallNow: DateTime.now());

  void _tick() {
    if (!mounted || _finishing) return;
    final mono = _sw.elapsedMilliseconds;
    final ev = _s.clock!.tick(monoDeltaMs: mono - _lastMono, wallNowMs: DateTime.now().millisecondsSinceEpoch);
    _lastMono = mono;
    if (ev != null) _s.events.add(ev);
    if (++_ticks % 5 == 0) _save();
    setState(() {});
    final left = _left;
    if (left != null && left <= 0) _finish('time_up');
  }

  void _answer(PaperQuestion q, Map<String, dynamic> a) {
    if (_finishing) return;
    setState(() {
      q.answer = a;
      _s.put(q.questionId, a);
    });
    _save();
  }

  /// Which way the last move went (the question's entrance follows it).
  bool _forward = true;

  void _move(int i) {
    _forward = i >= _index;
    _goTo(i);
  }

  void _goTo(int i) {
    final all = _paper.all;
    if (i < 0 || i >= all.length) return;
    if (!_paper.canNavigate(all[_index], all[i])) return appToast(examCodeText('one_way_section'), error: true);
    setState(() => _index = i);
  }

  Future<void> _submit() async {
    final unanswered = _paper.onlineCount - _paper.answeredCount;
    final ok = await appConfirm(context,
        message: unanswered > 0
            ? t('لديك $unanswered سؤالاً بلا إجابة. إنهاء الاختبار؟', 'You have $unanswered unanswered question(s). Finish the exam?')
            : t('إنهاء الاختبار وتسليمه؟', 'Finish and hand in the exam?'),
        confirmLabel: t('تسليم', 'Hand in'));
    if (ok && mounted) await _finish('submitted');
  }

  /// Seals the answers with the student's key: from here on they cannot be changed, only sent.
  Future<void> _finish(String reason) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    _ticker?.cancel();
    _s
      ..finishedReason = reason
      ..finishedAt = DateTime.now()
      ..step('finished', note: reason);
    final key = await _store.studentKey();
    _s.bundle = await sealBundle(bundleId: _s.bundleId, examId: _s.examId, studentId: _s.studentId, n: _s.n, payload: _s.payload(),
        studentKeyHex: key != null && key.userId == _s.studentId ? key.key : null);
    _s.stage = OfflineStage.waitingToSync;
    await _save();
    if (!mounted) return;
    if (reason == 'time_up') appToast(t('انتهى الوقت — حُفظت إجاباتك وستُرسل', 'Time is up — your answers are saved and will be sent'));
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OfflineExamStatusScreen(sitting: _s, title: widget.package.title, sendNow: true)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = _paper.all;
    final q = all.isEmpty ? null : all[_index.clamp(0, all.length - 1)];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await appConfirm(context,
            message: t('إجاباتك محفوظة على هذا الجهاز. المؤقت يستمر أثناء خروجك. الخروج الآن؟',
                'Your answers are saved on this phone. The timer keeps running while you are away. Leave now?'));
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: BasePage(
        key: const ValueKey('exam.offline'),
        appBar: AppHeader(
          title: widget.package.title,
          compact: true,
          actions: [ExamTimerChip(remainingSeconds: _left, timed: widget.package.durationMinutes != null || widget.package.endsAt != null)],
        ),
        child: q == null
            ? AppEmpty(icon: Icons.quiz_outlined, title: t('لا توجد أسئلة إلكترونية في هذه الورقة', 'No online questions in this paper'))
            : Column(children: [
                ExamPageWidth(
                  width: AppWidth.reading,
                  builder: (side) => Padding(
                    padding: EdgeInsets.fromLTRB(side, AppSpace.xs, side, 0),
                    child: AppBanner(icon: Icons.offline_pin_rounded, color: c.primary,
                        text: t('دون اتصال — كل إجابة تُحفظ على هذا الجهاز فوراً', 'Offline — every answer is saved on this phone at once')),
                  ),
                ),
                ExamProgressBar(index: _index, total: all.length, answered: _paper.answeredCount, locked: false, pendingSaves: 0,
                    answeredFlags: [for (final x in all) x.answered]),
                Expanded(
                  child: ExamQuestionSwap(
                    forward: _forward,
                    child: ExamQuestionCard(
                      key: ValueKey('oq.${q.questionId}'),
                      question: q,
                      number: _index + 1,
                      section: _paper.sections[q.sectionIndex],
                      enabled: !_finishing,
                      imageBytes: q.image == null ? null : _media.of(q.image!.id),
                      imageOmitted: q.image != null && _media.isOmitted(q.image!.id),
                      onAnswer: (a) => _answer(q, a),
                    ),
                  ),
                ),
                ExamNavBar(
                  index: _index,
                  total: all.length,
                  canBack: _index > 0 && _paper.canNavigate(q, all[_index - 1]),
                  submitting: _finishing,
                  onBack: () => _move(_index - 1),
                  onNext: () => _move(_index + 1),
                  onJump: _move,
                  answered: {for (final x in all) x.questionId: x.answered},
                  questionIds: [for (final x in all) x.questionId],
                  onSubmit: _submit,
                ),
              ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════ status after finishing ══════════════════════════════════════════

/// The five steps as the student sees them (plain values; under the layout harness).
class OfflineStepsView extends StatelessWidget {
  const OfflineStepsView({super.key, required this.stage, this.code});
  final OfflineStage stage;
  final String? code;

  static int reached(OfflineStage s) => switch (s) {
        OfflineStage.downloaded => 0,
        OfflineStage.inProgress => 2,
        OfflineStage.waitingToSync || OfflineStage.rejected => 3,
        OfflineStage.submitted => 4,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = [
      t('تم التنزيل', 'Downloaded'),
      t('قيد الحل', 'In progress'),
      t('محفوظ على الجهاز', 'Saved on this phone'),
      t('بانتظار الإرسال', 'Waiting to sync'),
      t('تم التسليم', 'Submitted'),
    ];
    final at = reached(stage);
    final rejected = stage == OfflineStage.rejected;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < labels.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // the rail: a disc per step, joined by a line that is solid where the sitting has already been
            SizedBox(
              width: _disc,
              child: Column(children: [
                _StepDisc(done: i < at || (i == at && stage == OfflineStage.submitted), current: i == at, failed: rejected && i == at),
                if (i < labels.length - 1)
                  Expanded(
                    child: Center(
                      child: Container(width: AppBorder.strong, constraints: const BoxConstraints(minHeight: AppSpace.sm), color: i < at ? c.success : c.divider),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: AppSpace.xxs, bottom: i < labels.length - 1 ? AppSpace.md : 0),
                child: Text(labels[i],
                    style: (i == at ? AppType.bodyStrong(context) : AppType.body(context)).copyWith(color: i <= at ? c.textDark : c.textLight)),
              ),
            ),
          ]),
        ),
      if (code != null && code!.isNotEmpty && stage != OfflineStage.submitted)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: AppBanner(icon: stage == OfflineStage.rejected ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              color: stage == OfflineStage.rejected ? c.danger : c.warning, text: offlineCodeText(code)),
        ),
    ]);
  }

  static const double _disc = AppSpace.lg + AppSpace.xxs;
}

/// One step's disc: a check on the success tint once passed, a ring on the current one (a cross on the danger tint
/// when the server refused it), a hairline circle ahead.
class _StepDisc extends StatelessWidget {
  const _StepDisc({required this.done, required this.current, required this.failed});
  final bool done;
  final bool current;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = failed ? c.danger : c.success;
    final tint = appTintOn(context, col);
    final filled = done || failed;
    return Container(
      width: OfflineStepsView._disc,
      height: OfflineStepsView._disc,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? tint : c.cardBg,
        border: Border.all(color: filled ? tint : (current ? c.textDark : c.divider), width: current && !filled ? AppBorder.focus : AppBorder.hairline),
      ),
      child: filled
          ? Icon(failed ? Icons.close_rounded : Icons.check_rounded, size: AppIconSize.sm, color: appInkOn(context, col, tint))
          : (current ? Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: c.textDark, shape: BoxShape.circle)) : null),
    );
  }
}

class OfflineExamStatusScreen extends StatefulWidget {
  const OfflineExamStatusScreen({super.key, required this.sitting, required this.title, this.sendNow = false});
  final OfflineSitting sitting;
  final String title;
  final bool sendNow;

  @override
  State<OfflineExamStatusScreen> createState() => _OfflineExamStatusScreenState();
}

class _OfflineExamStatusScreenState extends State<OfflineExamStatusScreen> {
  late final OfflineSitting _s = widget.sitting;
  String? _busy;

  @override
  void initState() {
    super.initState();
    if (widget.sendNow && _s.stage == OfflineStage.waitingToSync) WidgetsBinding.instance.addPostFrameCallback((_) => _send(nearbyToo: false));
  }

  /// Straight to the server when online; else through a nearby phone (only a verified receipt counts).
  Future<void> _send({bool nearbyToo = true}) async {
    if (_busy != null || _s.stage != OfflineStage.waitingToSync) return;
    setState(() => _busy = 'send');
    final direct = await _sync.sendOwn(_s);
    if (!direct.sent && direct.code == 'network' && nearbyToo && _s.bundle != null) {
      final r = await OfflineExamRelayClient().submit(_s.bundle!);
      if (r['t'] == 'exam_receipt') {
        await _sync.applyResult(_s, r, direct: false);
      } else {
        _s.code = '${r['code'] ?? 'no_relay'}';
        await _store.saveSitting(_s);
      }
    }
    if (!mounted) return;
    setState(() => _busy = null);
    if (_s.stage == OfflineStage.submitted) appToast(t('تم تسليم إجاباتك', 'Your answers were handed in'));
  }

  Future<void> _share() async {
    final b = _s.bundle;
    if (b == null) return;
    final name = 'exam_${_s.examId}_${_s.studentId}.$kAnswersFileExt';
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(utf8.encode(answersFile([b])), mimeType: 'application/json', name: name)],
        fileNameOverrides: [name]));
  }

  @override
  Widget build(BuildContext context) {
    final stage = _s.stage;
    // the page's one block: where the answers are now — emerald once handed in, peach while they wait on this phone
    final tone = stage == OfflineStage.submitted ? AppBlockTone.emerald : AppBlockTone.peach;
    final b = AppBlockColors.of(context, tone);
    final glyph = switch (stage) {
      OfflineStage.submitted => Icons.cloud_done_rounded,
      OfflineStage.rejected => Icons.error_outline_rounded,
      _ => Icons.offline_pin_rounded,
    };
    return BasePage(
      key: const ValueKey('exam.offline.status'),
      appBar: AppHeader(title: widget.title),
      child: ExamPageWidth(
        width: AppWidth.form,
        builder: (side) => ListView(padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.xl), children: [
          AppBlock(
            tone: tone,
            hero: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(glyph, size: AppIconSize.xl, color: stage == OfflineStage.rejected ? b.accentInk(context.colors.danger) : b.ink),
              const SizedBox(height: AppSpace.md),
              Text(offlineStageText(stage), style: AppType.headline(context).copyWith(color: b.ink)),
              const SizedBox(height: AppSpace.xxs),
              Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
            ]),
          ),
          AppSpace.gapMd,
          AppCard(padding: const EdgeInsets.all(AppSpace.lg), child: OfflineStepsView(stage: stage, code: _s.code)),
          AppSpace.gapLg,
          if (stage == OfflineStage.waitingToSync) ...[
            AppButton.primary(label: t('إرسال الآن', 'Send now'), icon: Icons.send_rounded, size: AppButtonSize.lg, expand: true,
                busy: _busy == 'send', onPressed: _busy == null ? _send : null),
            const SizedBox(height: AppSpace.xs),
            Text(t('يُرسل تلقائياً عند عودة الإنترنت، أو عبر جهاز قريب متصل.', 'Sent automatically when the internet is back, or through a nearby phone that is online.'),
                style: AppType.meta(context), textAlign: TextAlign.center),
            AppSpace.gapMd,
          ],
          if (_s.bundle != null && stage != OfflineStage.submitted)
            AppButton.secondary(
              onPressed: _share,
              expand: true,
              icon: Icons.ios_share_rounded,
              label: t('مشاركة ملف الإجابات مع المعلم', 'Share the answers file with the teacher'),
            ),
        ]),
      ),
    );
  }
}
