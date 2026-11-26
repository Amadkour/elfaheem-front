// lib/features/courses/student/details/subject_panels.dart
//
// The subject page's chat, assistant and schedule panels (SubjectProfile rows 11-16 and 19-22; BK). They open
// through the subject page's panel frame (`showSubjectPanel`, S-B): a tall sheet on a phone, a drawer on a wide
// window.
//
//   chat       "راسل المعلم": the one private chat with the teacher (S-C's ChatThreadView, embedded as it is), started
//              for this course; kill switch `chat`
//   assistant  "المساعد الذكي": the course's library assistant (POST /rag/ask with the course), gated by
//              GET /me/assistant/subject (on, or locked with the server's reason); kill switches `rag.assistant`,
//              `rag.subject_bot`
//   schedule   "جدول حصصي": the month of the student's own calendar (GET /me/calendar through S-C's CalendarStore),
//              this subject's classes only, or every subject with "اعرض حصص المواد الثانية"; times through AppTime
//
// Privacy: the chat is one to one with the teacher; the assistant answers only the student.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/booking/booking_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/calendar/schedule_store.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_panel.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_page.dart' show ChatThreadView, chatApi, chatErrorText, kChatFeatureKey;
import 'package:flutter_education_app/features/rag/rag_chat.dart' show RagApi, RagAnswer;

/// The kill switches of the subject's assistant.
const String kSubjectBotKey = 'rag.subject_bot';

bool subjectBotOff() =>
    AppConfig.disableList.contains('rag.assistant') || AppConfig.disableList.contains(kSubjectBotKey);

bool subjectChatOff() => AppConfig.disableList.contains(kChatFeatureKey);

// ═════════════════════════════════════════════════════════════════════════════
// Chat
// ═════════════════════════════════════════════════════════════════════════════

/// "راسل المعلم": the teacher's private chat for this course, in the panel.
Future<void> openSubjectChatPanel(BuildContext context, {required int teacherId, required String teacherName, int? courseId}) {
  final phone = MediaQuery.sizeOf(context).width < Breakpoints.mobile;
  return showAppSheet<void>(
    context,
    (ctx) => AppAreaScope(
      area: AppArea.chat,
      child: SizedBox(
        height: phone ? MediaQuery.sizeOf(ctx).height * kSubjectPanelPhoneHeight : null,
        child: SubjectChatPanel(teacherId: teacherId, courseId: courseId, onClose: () => Navigator.of(ctx).maybePop()),
      ),
    ),
    mode: phone ? AppSheetMode.bottom : AppSheetMode.side,
    width: kSubjectPanelNarrow,
  );
}

class SubjectChatPanel extends StatefulWidget {
  const SubjectChatPanel({super.key, required this.teacherId, this.courseId, required this.onClose});

  final int teacherId;
  final int? courseId;
  final VoidCallback onClose;

  @override
  State<SubjectChatPanel> createState() => _SubjectChatPanelState();
}

class _SubjectChatPanelState extends State<SubjectChatPanel> {
  int? _conversation;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final conv = await chatApi().start(peerId: widget.teacherId, courseId: widget.courseId);
      if (mounted) setState(() => _conversation = conv.id);
    } catch (e) {
      if (mounted) setState(() => _error = chatErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _conversation;
    if (id != null) {
      // the thread's own header (the teacher, the info menu) with its back arrow closing the panel
      return ChatThreadView(conversationId: id, onBack: widget.onClose, onLeave: widget.onClose);
    }
    return SubjectPanelFrame(
      title: 'sb_subj_message_teacher'.tr,
      onClose: widget.onClose,
      child: _error == null
          ? const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 4))
          : AppErrorState(message: _error, onRetry: _start),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// The subject's assistant
// ═════════════════════════════════════════════════════════════════════════════

Future<void> openSubjectBotPanel(BuildContext context, {required int courseId, required String subjectTitle}) =>
    showSubjectPanel<void>(
      context,
      title: 'bk_bot_title'.tr,
      child: (_) => AppAreaScope(area: AppArea.learn, child: SubjectBotPanel(courseId: courseId, subjectTitle: subjectTitle)),
    );

/// One question and its answer in the panel.
class BkBotTurn {
  BkBotTurn({required this.question, this.answer, this.failed = false});

  final String question;
  String? answer;
  bool failed;

  bool get waiting => answer == null && !failed;
}

class SubjectBotPanel extends StatefulWidget {
  const SubjectBotPanel({
    super.key,
    required this.courseId,
    required this.subjectTitle,
    this.gate,
    this.initialTurns = const [],
    this.api,
  });

  final int courseId;
  final String subjectTitle;

  /// Goldens: the gate's answer without a call.
  final BkAssistantGate? gate;
  final List<BkBotTurn> initialTurns;
  final RagApi? api;

  @override
  State<SubjectBotPanel> createState() => _SubjectBotPanelState();
}

class _SubjectBotPanelState extends State<SubjectBotPanel> {
  late final RagApi _api = widget.api ?? RagApi();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final List<BkBotTurn> _turns = [...widget.initialTurns];
  BkAssistantGate? _gate;
  bool _gateFailed = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _gate = widget.gate;
    if (_gate == null) _loadGate();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadGate() async {
    if (subjectBotOff()) {
      setState(() => _gate = const BkAssistantGate(on: false, reason: 'feature_off'));
      return;
    }
    try {
      final g = await fetchSubjectAssistant(widget.courseId);
      if (mounted) setState(() => _gate = g);
    } catch (_) {
      if (mounted) setState(() => _gateFailed = true);
    }
  }

  bool get _on => _gate?.on == true;

  Future<void> _ask(String text) async {
    final q = text.trim();
    if (q.isEmpty || _sending || !_on) return;
    final turn = BkBotTurn(question: q);
    setState(() {
      _turns.add(turn);
      _sending = true;
      _input.clear();
    });
    _toEnd();
    final r = await _api.ask(q, courseId: _gate?.courseId ?? widget.courseId, orgId: _gate?.orgId);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        turn.failed = true;
        _sending = false;
      });
      return;
    }
    final pending = RagAnswer.fromJson(r.map);
    final done = await _api.waitForLive(pending.id, r.map, onUpdate: (a) {
      if (!mounted) return;
      final part = a.partial;
      if (part != null && part.isNotEmpty) setState(() => turn.answer = part);
    });
    if (!mounted) return;
    setState(() {
      _sending = false;
      final a = done.ok ? RagAnswer.fromJson(done.map) : null;
      if (a != null && a.answer.trim().isNotEmpty) {
        turn.answer = a.answer.trim();
      } else {
        turn.failed = true;
      }
    });
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: AppMotion.of(context).base, curve: AppEase.out);
        }
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final gate = _gate;
    final locked = gate != null && !gate.on;
    final chips = ['bk_bot_chip_example'.tr, 'bk_bot_chip_quiz'.tr, 'bk_bot_chip_summary'.tr];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(AppSpace.md),
          children: [
            _BotHead(title: bkFillText('bk_bot_head', {'subject': gate?.title ?? widget.subjectTitle})),
            const SizedBox(height: AppSpace.md),
            if (gate == null && !_gateFailed)
              const AppListSkeleton(items: 2, withAvatar: false)
            else if (_gateFailed)
              AppErrorState(compact: true, onRetry: () {
                setState(() => _gateFailed = false);
                _loadGate();
              })
            else if (locked)
              _LockedNote(message: gate.message)
            else
              for (final (i, t) in _turns.indexed) ...[
                if (i > 0) const SizedBox(height: AppSpace.sm),
                _Bubble(text: t.question, mine: true),
                const SizedBox(height: AppSpace.sm),
                if (t.waiting)
                  const _Typing()
                else
                  _Bubble(text: t.failed ? 'bk_bot_failed'.tr : t.answer!, mine: false, failed: t.failed),
              ],
            if (gate != null) ...[
              const SizedBox(height: AppSpace.md),
              Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                for (final (i, s) in chips.indexed)
                  _SuggestChip(label: s, enabled: !locked && !_sending, onTap: () => _ask(s), index: i),
              ]),
            ],
          ],
        ),
      ),
      SubjectPanelFooter(children: [
        Expanded(
          child: TextField(
            controller: _input,
            enabled: _on && !_sending,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: _ask,
            style: AppType.body(context),
            decoration: InputDecoration(
              hintText: locked ? 'bk_bot_locked_hint'.tr : 'bk_bot_hint'.tr,
              filled: true,
              fillColor: kit.well,
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: BorderSide(color: kit.line, width: AppBorder.strong),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: BorderSide(color: kit.line, width: AppBorder.strong),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: BorderSide(color: kit.line, width: AppBorder.strong),
              ),
            ),
          ),
        ),
        _SendButton(enabled: _on && !_sending, onTap: () => _ask(_input.text)),
      ]),
    ]);
  }
}

String bkFillText(String key, Map<String, Object> values) {
  var s = key.tr;
  values.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

class _BotHead extends StatelessWidget {
  const _BotHead({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final grape = c.kit.accent(AppAccent.grape);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.tile + AppSpace.xxs),
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [grape.tint, c.cardBg],
        ),
      ),
      child: Row(children: [
        const _Mascot(),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.section(context)),
            const SizedBox(height: AppSpace.xxs),
            Text('bk_bot_sub'.tr, style: AppType.body(context).copyWith(color: c.textMedium)),
          ]),
        ),
      ]),
    );
  }
}

/// The assistant's face: a round gradient with two eyes and a smile (drawn, no image).
class _Mascot extends StatelessWidget {
  const _Mascot();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    return ExcludeSemantics(
      child: Container(
        width: AppDashSize.disc,
        height: AppDashSize.disc,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.cardBg, width: AppBorder.focus + 1),
          gradient: SweepGradient(colors: [kit.hotA, kit.accent(AppAccent.grape).color, kit.accent(AppAccent.sky).color, kit.hotA]),
          boxShadow: AppElevation.of(context, 2),
        ),
        child: Icon(Icons.sentiment_satisfied_alt_rounded, size: AppIconSize.xl, color: c.onHero),
      ),
    );
  }
}

class _LockedNote extends StatelessWidget {
  const _LockedNote({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final warm = context.colors.kit.warmTone;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: warm.tint,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: Color.lerp(warm.tint, warm.color, .35)!, width: AppBorder.strong),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: AppIconSize.lg, color: warm.ink),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message ?? 'bk_bot_locked'.tr, style: AppType.bodyStrong(context).copyWith(color: warm.ink)),
            const SizedBox(height: AppSpace.xxs),
            Text('bk_bot_locked_text'.tr, style: AppType.body(context).copyWith(color: warm.ink)),
          ]),
        ),
      ]),
    );
  }
}

/// A chat bubble: the student's on the hot gradient (its tail at the end), the assistant's on the grape tint (M3,
/// its tail at the start).
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine, this.failed = false});

  final String text;
  final bool mine, failed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final grape = kit.accent(AppAccent.grape);
    const r = Radius.circular(AppRadius.tile + AppSpace.xxs);
    const tail = Radius.circular(AppRadius.chip);
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(
          gradient: mine ? kit.hotButton : null,
          color: mine ? null : (failed ? kit.warmTone.tint : grape.tint),
          borderRadius: BorderRadiusDirectional.only(
            topStart: mine ? r : tail,
            topEnd: mine ? tail : r,
            bottomStart: r,
            bottomEnd: r,
          ),
        ),
        child: Text(text, style: AppType.body(context).copyWith(color: mine ? kit.hotFg : c.textDark)),
      ),
    );
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: AppPop(alignment: mine ? Alignment.bottomRight : Alignment.bottomLeft, child: bubble),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final grape = context.colors.kit.accent(AppAccent.grape);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(color: grape.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
        child: Text('bk_bot_thinking'.tr, style: AppType.body(context).copyWith(color: grape.ink)),
      ),
    );
  }
}

class _SuggestChip extends StatelessWidget {
  const _SuggestChip({required this.label, required this.enabled, required this.onTap, required this.index});

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final grape = c.kit.accent(AppAccent.grape);
    final chip = Container(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: enabled ? grape.tint : c.kit.line, width: AppBorder.strong),
      ),
      child: Text(label, style: AppType.bodyStrong(context).copyWith(color: enabled ? grape.ink : c.textLight)),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: AppJelly(
        enabled: enabled,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: enabled ? AppPop(delay: Duration(milliseconds: 80 * index), child: chip) : chip,
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'bk_send'.tr,
      child: AppJelly(
        enabled: enabled,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Container(
            width: AppTouch.primary,
            height: AppTouch.primary,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: enabled ? kit.hotButton : null,
              color: enabled ? null : kit.lock,
            ),
            child: Icon(Icons.send_rounded, size: AppIconSize.md, color: enabled ? kit.hotFg : context.colors.onHero),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Schedule
// ═════════════════════════════════════════════════════════════════════════════

Future<void> openSubjectSchedulePanel(BuildContext context, {required int courseId, required String subjectTitle, String? subjectKey}) =>
    showSubjectPanel<void>(
      context,
      title: 'bk_cal_title'.tr,
      wide: true,
      child: (_) => AppAreaScope(
        area: AppArea.sched,
        child: SubjectSchedulePanel(courseId: courseId, subjectTitle: subjectTitle, subjectKey: subjectKey),
      ),
    );

/// One class on the month: a plain value the grid draws.
class BkCalItem {
  const BkCalItem({required this.courseId, required this.title, required this.start, required this.end});

  final int? courseId;
  final String title;
  final DateTime start, end; // UTC
}

class SubjectSchedulePanel extends StatefulWidget {
  const SubjectSchedulePanel({
    super.key,
    required this.courseId,
    required this.subjectTitle,
    this.subjectKey,
    this.items,
    this.month,
    this.api,
  });

  final int courseId;
  final String subjectTitle;
  final String? subjectKey;

  /// Goldens: the classes without a call, and the month to show.
  final List<BkCalItem>? items;
  final DateTime? month;
  final CalendarApi? api;

  @override
  State<SubjectSchedulePanel> createState() => _SubjectSchedulePanelState();
}

class _SubjectSchedulePanelState extends State<SubjectSchedulePanel> {
  late DateTime _month = widget.month ?? _thisMonth();
  late DateTime? _day = _defaultDay();
  bool _all = false;
  List<BkCalItem>? _items;
  String? _error;
  bool _loading = false;

  static DateTime _thisMonth() {
    final n = AppTime.toZone(DateTime.now().toUtc());
    return DateTime(n.year, n.month);
  }

  DateTime? _defaultDay() {
    final n = AppTime.toZone(DateTime.now().toUtc());
    return n.year == _month.year && n.month == _month.month ? calDay(n) : null;
  }

  @override
  void initState() {
    super.initState();
    _items = widget.items;
    if (_items == null) _load();
    _pickFirstDay();
  }

  /// Another month than today's: its first day with a class of this subject is the one open.
  void _pickFirstDay() {
    if (_day != null) return;
    final mine = [
      for (final x in _items ?? const <BkCalItem>[])
        if (x.courseId == widget.courseId && AppTime.toZone(x.start).month == _month.month) calDay(AppTime.toZone(x.start)),
    ]..sort();
    _day = mine.firstOrNull;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (s, e) = calFetchRange(CalView.month, _month);
      int? uid;
      try {
        uid = context.read<MyAuthProvider>().currentUser?.id;
      } catch (_) {}
      final store = CalendarStore.instance;
      final scope = 'u${uid ?? 0}:me';
      final hit = store.cached(scope, s, e);
      final chunk = hit != null && store.fresh(hit)
          ? hit
          : await store.fetch(widget.api ?? const RemoteCalendarApi(), scope: scope, start: s, end: e);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final x in chunk.events)
            if (!x.cancelled && x.courseId != null)
              BkCalItem(courseId: x.courseId, title: x.subtitle ?? x.title, start: x.start, end: x.end),
        ];
        _loading = false;
        _pickFirstDay();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = bkErrorText(e);
          _loading = false;
        });
      }
    }
  }

  void _shift(int dir) {
    setState(() {
      _month = DateTime(_month.year, _month.month + dir);
      _day = _defaultDay();
    });
    if (widget.items == null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final items = [for (final x in _items ?? const <BkCalItem>[]) if (_all || x.courseId == widget.courseId) x];
    // one colour per course: this subject's own, the others from the accents in the order they appear
    final mine = subjectColors(context, widget.subjectKey ?? widget.subjectTitle).tone.color;
    final others = [AppAccent.grape, AppAccent.sky, AppAccent.mint, AppAccent.pink, AppAccent.sun, AppAccent.lime];
    final colorOf = <int?, Color>{widget.courseId: mine};
    final names = <int?, String>{widget.courseId: widget.subjectTitle};
    for (final x in items) {
      if (!colorOf.containsKey(x.courseId)) {
        colorOf[x.courseId] = kit.accent(others[(colorOf.length - 1) % others.length]).color;
        names[x.courseId] = x.title;
      }
    }
    final days = calVisibleDays(CalView.month, _month);
    final byDay = <DateTime, List<BkCalItem>>{};
    for (final x in items) {
      (byDay[calDay(AppTime.toZone(x.start))] ??= []).add(x);
    }
    final today = calDay(AppTime.toZone(DateTime.now().toUtc()));
    final selected = _day;
    final dayList = selected == null ? const <BkCalItem>[] : ((byDay[selected] ?? [])..sort((a, b) => a.start.compareTo(b.start)));
    final monthTitle = appDigits(AppTime.wall(_month, pattern: 'MMMM y'));

    Widget cell(DateTime d) {
      final inMonth = d.month == _month.month;
      if (!inMonth) {
        return Container(
          margin: const EdgeInsets.all(AppSpace.xxs),
          decoration: BoxDecoration(color: kit.well.withValues(alpha: .5), borderRadius: BorderRadius.circular(AppRadius.chip)),
        );
      }
      final list = byDay[d] ?? const <BkCalItem>[];
      final on = d == selected;
      final isToday = d == today;
      return Semantics(
        button: true,
        selected: on,
        label: '${AppTime.wall(d, pattern: 'EEEE d MMMM')}${list.isEmpty ? '' : '، ${list.length}'}',
        child: InkWell(
          onTap: () => setState(() => _day = d),
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Container(
            margin: const EdgeInsets.all(AppBorder.focus),
            padding: const EdgeInsets.all(AppSpace.xxs),
            decoration: BoxDecoration(
              color: on ? kit.warmTone.tint : kit.well,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(
                color: on ? kit.warmTone.color : (isToday ? kit.fieldEdge : kit.line),
                width: on ? AppBorder.strong : AppBorder.hairline,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(appDigits('${d.day}'), maxLines: 1,
                    style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
              ),
              for (final x in list.take(2))
                Container(
                  height: AppSpace.xxs + 1,
                  margin: const EdgeInsetsDirectional.only(top: AppBorder.focus),
                  decoration: BoxDecoration(color: colorOf[x.courseId], borderRadius: BorderRadius.circular(AppRadius.pill)),
                ),
            ]),
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      Row(children: [
        Expanded(child: Text(monthTitle, style: AppType.pageTitle(context))),
        AppIconButton(icon: Icons.chevron_left_rounded, tooltip: 'bk_cal_prev'.tr, onPressed: () => _shift(-1)),
        AppIconButton(icon: Icons.chevron_right_rounded, tooltip: 'bk_cal_next'.tr, onPressed: () => _shift(1)),
      ]),
      const SizedBox(height: AppSpace.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xxs, AppSpace.xs, AppSpace.xxs),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: kit.line, width: AppBorder.strong),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text('bk_cal_others'.tr, style: AppType.bodyStrong(context))),
            const SizedBox(width: AppSpace.sm),
            AppSwitch(value: _all, semanticLabel: 'bk_cal_others'.tr, onChanged: (v) => setState(() => _all = v)),
          ]),
        ),
      ),
      const SizedBox(height: AppSpace.md),
      Row(children: [
        for (var k = 0; k < 7; k++)
          Expanded(
            child: Text(
              AppTime.wall(days[k], pattern: 'EEEE').replaceFirst(RegExp(r'^ال'), ''),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: AppType.meta(context),
            ),
          ),
      ]),
      const SizedBox(height: AppSpace.xs),
      if (_loading && _items == null)
        const AppListSkeleton(items: 4, withAvatar: false)
      else if (_error != null && _items == null)
        AppErrorState(message: _error, onRetry: _load, compact: true)
      else
        for (var r = 0; r < 6; r++)
          if (days.sublist(r * 7, r * 7 + 7).any((d) => d.month == _month.month))
            SizedBox(
              height: AppDashSize.disc,
              child: Row(children: [
                for (var k = 0; k < 7; k++) Expanded(child: cell(days[r * 7 + k])),
              ]),
            ),
      const SizedBox(height: AppSpace.md),
      if (selected != null)
        AppFlipIn(
          key: ValueKey(selected),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: kit.well,
              borderRadius: BorderRadius.circular(AppRadius.tile),
              border: Border.all(color: kit.line, width: AppBorder.strong),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(appDigits(AppTime.wall(selected, pattern: 'EEEE d MMMM')), style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.sm),
              if (dayList.isEmpty)
                Text('bk_cal_empty_day'.tr, style: AppType.body(context).copyWith(color: c.textMedium))
              else
                for (final x in dayList)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                    child: Row(children: [
                      Container(
                        width: AppSpace.sm,
                        height: AppSpace.sm,
                        decoration: BoxDecoration(color: colorOf[x.courseId], borderRadius: BorderRadius.circular(AppRadius.chip)),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(child: Text(names[x.courseId] ?? x.title, style: AppType.body(context))),
                      Text(_range(x), style: AppType.body(context).copyWith(color: c.textMedium)),
                    ]),
                  ),
            ]),
          ),
        ),
      const SizedBox(height: AppSpace.md),
      Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, children: [
        for (final e in colorOf.entries)
          if (e.key == widget.courseId || _all)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: AppSpace.sm,
                height: AppSpace.sm,
                decoration: BoxDecoration(color: e.value, borderRadius: BorderRadius.circular(AppRadius.chip)),
              ),
              const SizedBox(width: AppSpace.xs),
              Text(names[e.key] ?? '', style: AppType.body(context).copyWith(color: c.textMedium)),
            ]),
      ]),
      if (AppTime.zoneId != AppTime.platformZoneId) ...[
        const SizedBox(height: AppSpace.sm),
        Text(bkFillText('bk_cal_zone', {'zone': AppTime.zoneId}), style: AppType.meta(context)),
      ],
    ]);
  }

  String _range(BkCalItem x) {
    final a = AppTime.time(x.start), b = AppTime.time(x.end);
    final pa = a.split(' '), pb = b.split(' ');
    final from = pa.length == 2 && pb.length == 2 && pa[1] == pb[1] ? pa[0] : a;
    return appDigits(bkFillText('bk_time_range', {'from': from, 'to': b}));
  }
}
