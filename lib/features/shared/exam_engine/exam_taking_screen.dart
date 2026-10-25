// Taking an Exam Engine exam (Phase 5, D-018): server timer, autosave with resume, one-way sections, integrity events.
//
// Flow: `openEngineExam(context, exam)` → consent (if not accepted) → start / resume → this screen → result screen.
// The screen talks to the engine through [ExamEngineApi]; the pure pieces live in exam_taking.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asInt, asMap, t;
import '../../student/courses/security/device_id_service.dart';
import 'exam_consent_screen.dart';
import 'exam_engine_api.dart';
import 'exam_integrity.dart';
import 'exam_result_screen.dart';
import 'exam_taking.dart';

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
        await Navigator.push(ctx, MaterialPageRoute(builder: (_) => ExamConsentScreen(examId: examId, onAccepted: (c2) async {
              Navigator.pop(c2);
              await start(ctx);
            })));
        return;
      }
      appToast(examCodeText(r.code ?? '') == (r.code ?? '') ? r.message : examCodeText(r.code ?? ''), error: true);
      return;
    }
    await Navigator.push(ctx, MaterialPageRoute(builder: (_) => ExamTakingScreen(examTitle: title, startReply: r.map, deviceId: deviceId)));
  }

  await start(context);
}

class ExamTakingScreen extends StatefulWidget {
  const ExamTakingScreen({super.key, required this.examTitle, required this.startReply, required this.deviceId});
  final String examTitle;
  final Map<String, dynamic> startReply;   // {attempt, exam_session, resumed, accommodation}
  final String deviceId;

  @override
  State<ExamTakingScreen> createState() => _ExamTakingScreenState();
}

class _ExamTakingScreenState extends State<ExamTakingScreen> {
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
    final attempt = asMap(widget.startReply['attempt']);
    _attemptId = asInt(attempt['id']);
    _session = '${widget.startReply['exam_session']}';
    _paper = Paper.fromJson(asMap(attempt['paper']));
    _clock = ServerClock.fromAttempt(attempt, DateTime.now())!;
    _locked = attempt['locked'] == true;
    _lockReason = attempt['lock_reason'] as String?;
    _integrity = ExamIntegrity((kind, meta) {
      _events.add(kind, meta: meta);
      if (_events.hasUrgent) _flushEvents();
    })..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _saver = Timer.periodic(const Duration(seconds: 4), (_) => _flush());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _saver?.cancel();
    _integrity.stop();
    super.dispose();
  }

  // ── timer ──
  void _tick() {
    if (!mounted || _finished) return;
    final left = _clock.remainingAt(DateTime.now());
    setState(() {});
    if (left != null && left <= 0) _timeUp();
  }

  Future<void> _timeUp() async {
    if (_finished) return;
    _finished = true;
    await _flush();
    final r = await _api.attempt(_attemptId);
    if (!mounted) return;
    appToast(examCodeText('deadline_passed'));
    _showResult(r.ok ? asMap(r.map['result']) : {'visible': false, 'state': 'auto_submitted'});
  }

  // ── autosave ──
  Future<void> _flush() async {
    if (_queue.isEmpty || _finished) return _flushEvents();
    final batch = _queue.batch();
    final r = await _api.save(_attemptId, batch, session: _session, deviceId: widget.deviceId);
    if (!mounted) return;
    if (r.ok) {
      _queue.ack(batch, [...(r.map['saved'] as List? ?? const []), ...(r.map['ignored'] as List? ?? const [])]);
      _clock = ServerClock(remainingSeconds: r.map['remaining_seconds'] == null ? null : asInt(r.map['remaining_seconds']), receivedAt: DateTime.now(),
          deadlineAt: _clock.deadlineAt);
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
      return;
    }
    for (final a in actionsOf(r.map)) {
      if (a.warns) setState(() => _warning = t('تنبيه: تم تسجيل ${a.category}', 'Warning: ${a.category} was recorded'));
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
        setState(() { _locked = true; _lockReason = '${(r.map['detail'] ?? {})['reason'] ?? ''}'; });
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
    final unanswered = _paper.onlineCount - _paper.answeredCount;
    final ok = await appConfirm(context,
        message: unanswered > 0
            ? t('لديك $unanswered سؤالاً بلا إجابة. تسليم الاختبار؟', 'You have $unanswered unanswered question(s). Submit the exam?')
            : t('تسليم الاختبار الآن؟', 'Submit the exam now?'),
        confirmLabel: t('تسليم', 'Submit'));
    if (!ok || !mounted) return;
    setState(() => _submitting = true);
    await _flush();
    final r = await _api.submit(_attemptId, session: _session, deviceId: widget.deviceId);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!r.ok) {
      if (r.code == 'attempt_submitted' || r.code == 'deadline_passed') {
        final res = await _api.attempt(_attemptId);
        if (mounted) _showResult(res.ok ? asMap(res.map['result']) : {'visible': false});
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

  @override
  Widget build(BuildContext context) {
    final all = _paper.all;
    final q = all.isEmpty ? null : all[_index.clamp(0, all.length - 1)];
    final left = _clock.remainingAt(DateTime.now());
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
      child: BasePage(
        key: const ValueKey('exam.taking'),
        appBar: AppBar(
          title: Text(widget.examTitle, overflow: TextOverflow.ellipsis),
          actions: [ExamTimerChip(remainingSeconds: left, timed: _clock.timed)],
        ),
        child: q == null
            ? AppEmpty(icon: Icons.quiz_outlined, title: t('لا توجد أسئلة إلكترونية في هذه الورقة', 'No online questions in this paper'))
            : Column(children: [
                ExamProgressBar(index: _index, total: all.length, answered: _paper.answeredCount, locked: _locked, lockReason: _lockReason,
                    warning: _warning, pendingSaves: _queue.length),
                Expanded(
                  child: ExamQuestionCard(
                    key: ValueKey('q.${q.questionId}'),
                    question: q,
                    section: _paper.sections[q.sectionIndex],
                    enabled: !_locked && !_finished,
                    onAnswer: (a) => _answer(q, a),
                  ),
                ),
                ExamNavBar(
                  index: _index,
                  total: all.length,
                  canBack: _index > 0 && _paper.canNavigate(q, all[_index - 1]),
                  submitting: _submitting,
                  onBack: () => _goTo(_index - 1),
                  onNext: () => _goTo(_index + 1),
                  onJump: (i) => _goTo(i),
                  answered: {for (final x in all) x.questionId: x.answered},
                  questionIds: [for (final x in all) x.questionId],
                  onSubmit: _locked ? null : _submit,
                ),
              ]),
      ),
    );
  }
}

// ═══════════════════════════ presentational pieces (plain values; under the layout harness) ═══════════════════════

class ExamTimerChip extends StatelessWidget {
  const ExamTimerChip({super.key, required this.remainingSeconds, required this.timed});
  final int? remainingSeconds;
  final bool timed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!timed || remainingSeconds == null) return const SizedBox.shrink();
    final urgent = remainingSeconds! <= 300;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: (urgent ? c.warning : c.primary).withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_outlined, size: 16, color: urgent ? c.warning : c.primary),
          const SizedBox(width: 4),
          Text(clockText(remainingSeconds!), key: const ValueKey('exam.timer'), style: appText(13.5, w: FontWeight.w800, c: urgent ? c.warning : c.primary)),
        ]),
      ),
    );
  }
}

class ExamProgressBar extends StatelessWidget {
  const ExamProgressBar({super.key, required this.index, required this.total, required this.answered, required this.locked, this.lockReason,
      this.warning, required this.pendingSaves});
  final int index;
  final int total;
  final int answered;
  final bool locked;
  final String? lockReason;
  final String? warning;
  final int pendingSaves;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Expanded(child: Text(t('سؤال ${index + 1} من $total', 'Question ${index + 1} of $total'), style: appText(13, w: FontWeight.w700, c: c.textDark))),
          Text(t('أُجيب $answered', '$answered answered'), style: appText(12.5, c: c.textMedium)),
          const SizedBox(width: 8),
          Icon(pendingSaves == 0 ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded, size: 16, color: pendingSaves == 0 ? c.success : c.textLight),
        ]),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: AppProgressBar(value: total == 0 ? 0 : answered / total)),
      if (locked)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: AppBanner(icon: Icons.lock_rounded, color: c.warning, text: '${examCodeText('attempt_locked')}${lockReason == null || lockReason!.isEmpty ? '' : ' ($lockReason)'}'),
        )
      else if (warning != null)
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: AppBanner(icon: Icons.warning_amber_rounded, color: c.warning, text: warning!)),
    ]);
  }
}

class ExamQuestionCard extends StatefulWidget {
  const ExamQuestionCard({super.key, required this.question, required this.section, required this.enabled, required this.onAnswer});
  final PaperQuestion question;
  final PaperSection section;
  final bool enabled;
  final void Function(Map<String, dynamic> answer) onAnswer;

  @override
  State<ExamQuestionCard> createState() => _ExamQuestionCardState();
}

class _ExamQuestionCardState extends State<ExamQuestionCard> {
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
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (widget.section.title.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
          Expanded(child: Text(widget.section.title, style: appText(12.5, w: FontWeight.w700, c: c.primary))),
          if (widget.section.oneWay) AppBadgePill(t('اتجاه واحد', 'one way'), icon: Icons.arrow_forward_rounded),
        ])),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(q.prompt, style: appText(16, w: FontWeight.w700, c: c.textDark, h: 1.5))),
            const SizedBox(width: 8),
            Text(t('${q.points} د', '${q.points} pt'), style: appText(12.5, c: c.textLight)),
          ]),
          const SizedBox(height: 14),
          ..._body(context, q, a),
        ]),
      ),
    ]);
  }

  List<Widget> _body(BuildContext context, PaperQuestion q, Map<String, dynamic> a) {
    final enabled = widget.enabled;
    switch (q.type) {
      case 'mcq_single':
        return [for (final o in q.options) _optionTile(context, '${o['text'] ?? o['id']}', selected: '${a['option'] ?? ''}' == '${o['id']}',
            onTap: enabled ? () => widget.onAnswer(encodeSingle('${o['id']}')) : null)];
      case 'mcq_multi':
        final chosen = ((a['options'] as List?) ?? const []).map((e) => '$e').toSet();
        return [for (final o in q.options) _optionTile(context, '${o['text'] ?? o['id']}', selected: chosen.contains('${o['id']}'), multi: true,
            onTap: enabled ? () {
              final next = Set<String>.from(chosen);
              next.contains('${o['id']}') ? next.remove('${o['id']}') : next.add('${o['id']}');
              widget.onAnswer(encodeMulti(next));
            } : null)];
      case 'true_false':
        return [Row(children: [
          Expanded(child: _optionTile(context, t('صح', 'True'), selected: a['value'] == true, onTap: enabled ? () => widget.onAnswer(encodeTrueFalse(true)) : null)),
          const SizedBox(width: 10),
          Expanded(child: _optionTile(context, t('خطأ', 'False'), selected: a['value'] == false, onTap: enabled ? () => widget.onAnswer(encodeTrueFalse(false)) : null)),
        ])];
      case 'fill_blank':
        return [for (var i = 0; i < _blanks.length; i++)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(
            controller: _blanks[i], enabled: enabled,
            decoration: InputDecoration(labelText: t('الفراغ ${i + 1}', 'Blank ${i + 1}')),
            onChanged: (_) => widget.onAnswer(encodeBlanks([for (final b in _blanks) b.text])),
          ))];
      case 'matching':
        final left = ((q.body['left'] as List?) ?? const []).map((e) => '$e').toList();
        final right = ((q.body['right'] as List?) ?? const []).map((e) => '$e').toList();
        final pairs = Map<String, String>.from(((a['pairs'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')));
        return [for (final l in left)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
            Expanded(child: Text(l, style: appText(14))),
            const SizedBox(width: 8),
            Expanded(child: AppDropdown<String>(
              value: pairs[l],
              items: [for (final r in right) DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))],
              onChanged: enabled ? (v) { if (v != null) widget.onAnswer(encodeMatching({...pairs, l: v})); } : null,
            )),
          ]))];
      case 'ordering':
        final items = ((q.body['items'] as List?) ?? const []).map((e) => '$e').toList();
        final order = ((a['order'] as List?) ?? items).map((e) => '$e').toList();
        return [SizedBox(
          height: (order.length * 56).toDouble().clamp(56, 420),
          child: ReorderableListView(
            buildDefaultDragHandles: enabled,
            onReorder: (from, to) {
              final next = List<String>.from(order);
              final item = next.removeAt(from);
              next.insert(to > from ? to - 1 : to, item);
              widget.onAnswer(encodeOrdering(next));
            },
            children: [for (var i = 0; i < order.length; i++) ListTile(key: ValueKey('ord.${order[i]}'), leading: Text('${i + 1}'), title: Text(order[i]), trailing: const Icon(Icons.drag_handle_rounded))],
          ),
        )];
      case 'numeric':
        final units = ((q.body['units'] as List?) ?? const []).map((e) => '$e').toList();
        return [Row(children: [
          Expanded(child: TextField(controller: _text, enabled: enabled, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: t('القيمة', 'Value')),
              onChanged: (v) => widget.onAnswer(encodeNumeric(v, unit: _unit.text)))),
          if (units.isNotEmpty) ...[
            const SizedBox(width: 8),
            SizedBox(width: 120, child: AppDropdown<String>(
              value: _unit.text.isEmpty ? null : _unit.text,
              items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: enabled ? (u) { _unit.text = u ?? ''; widget.onAnswer(encodeNumeric(_text.text, unit: _unit.text)); } : null,
            )),
          ],
        ])];
      case 'short_answer':
      case 'essay':
        return [TextField(controller: _text, enabled: enabled, minLines: q.type == 'essay' ? 6 : 2, maxLines: q.type == 'essay' ? 20 : 4,
            decoration: InputDecoration(hintText: t('اكتب إجابتك هنا', 'Write your answer here')),
            onChanged: (v) => widget.onAnswer(encodeText(v)))];
      default:
        return [AppBanner(icon: Icons.info_outline_rounded, text: t('هذا النوع من الأسئلة يُجاب عليه ورقياً أو برفع ملف (قريباً)', 'This question type is answered on paper or by file upload (coming soon)'))];
    }
  }

  Widget _optionTile(BuildContext context, String text, {required bool selected, bool multi = false, VoidCallback? onTap}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
            color: selected ? c.primary.withValues(alpha: .08) : null,
          ),
          child: Row(children: [
            Icon(multi ? (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded) : (selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
                color: selected ? c.primary : c.textLight, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: appText(14, c: c.textDark))),
          ]),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final last = index >= total - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(children: [
          IconButton(onPressed: canBack ? onBack : null, icon: const Icon(Icons.chevron_left_rounded), tooltip: t('السابق', 'Back')),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showAppSheet<void>(context, (_) => ExamQuestionGrid(answered: answered, questionIds: questionIds, current: index, onJump: (i) {
                    Navigator.pop(context);
                    onJump(i);
                  })),
              icon: const Icon(Icons.grid_view_rounded, size: 18),
              label: Text(t('الأسئلة', 'Questions')),
            ),
          ),
          const SizedBox(width: 8),
          if (!last)
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded), tooltip: t('التالي', 'Next'))
          else
            FilledButton.icon(
              key: const ValueKey('exam.submit'),
              onPressed: submitting ? null : onSubmit,
              icon: submitting ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 18),
              label: Text(t('تسليم', 'Submit')),
            ),
        ]),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < questionIds.length; i++)
          InkWell(
            onTap: () => onJump(i),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 44, height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: answered[questionIds[i]] == true ? c.primary.withValues(alpha: .15) : c.surface,
                border: Border.all(color: i == current ? c.primary : c.divider, width: i == current ? 2 : 1),
              ),
              child: Text('${i + 1}', style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
            ),
          ),
      ]),
    );
  }
}
