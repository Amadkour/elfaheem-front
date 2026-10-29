// lib/features/teacher/home/go_live_sheet.dart — "Go live" on the instructor home (D-091): the button and the sheet.
//
//   GoLiveButton     the header's red pill ("Go live" / "Return to live" while a room of mine runs), plain values
//   GoLiveEntry      the home's wiring: the button + LiveRoomHost (a minimized room → back to it) + the sheet
//   GoLiveSheetView  the sheet's content over plain values (layout-tested: test/ui/go_live_layout_test.dart):
//                      course (horizontal cards) · session (the one scheduled now first, or "New live session now"
//                      with an optional title) · Record · camera / microphone · the big "Go live" · "Meet now"
//   openGoLive       tap → the sheet (a dialog from 720 px) → PreJoinPage with autoJoin, straight into the room
//
// Data: nothing is asked when the home opens; the sheet asks GET /courses/{id}/sessions for the course it shows
// (cached per course while it is open). Pure logic: go_live.dart. Renders: test/visual/go_live_golden_test.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../core/app_mode.dart';
import '../../../design/app_contrast.dart' show ensureContrast;
import '../../../design/app_kit.dart';
import '../../../design/home_kit.dart' show homeDurationText;
import '../../../utils/widget/app_network_image.dart';
import '../../admin/admin_common.dart' show t;
import '../../auth/auth_provider.dart';
import '../../shared/calendar/calendar_meeting.dart' show startQuickMeeting;
import '../../shared/live/live_room_host.dart';
import '../sessions/live/prejoin.dart';
import 'go_live.dart';
import 'teacher_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  The header pill
// ─────────────────────────────────────────────────────────────────────────────

/// The red "Go live" pill (a 48 px tap target around a 40 px pill). [live] → "Return to live" with a ringed dot.
/// [compact] → the round icon only (narrow headers).
class GoLiveButton extends StatelessWidget {
  const GoLiveButton({super.key, this.live = false, this.onTap, this.busy = false, this.compact = false});

  final bool live;
  final VoidCallback? onTap;
  final bool busy;
  final bool compact;

  static String labelFor(bool live) => live ? t('العودة للبث', 'Return to live') : t('ابدأ البث', 'Go live');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = ensureContrast(c.danger, [c.onHero]);
    final deep = Color.lerp(fill, Colors.black, 0.18)!;
    final label = labelFor(live);
    final icon = busy
        ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.onHero))
        : live
            ? _RingDot(color: c.onHero)
            : Icon(Icons.sensors_rounded, size: 19, color: c.onHero);
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [fill, deep], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [BoxShadow(color: fill.withValues(alpha: c.isDark ? 0.28 : 0.32), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: SizedBox(
        height: 40,
        width: compact ? 40 : null,
        child: compact
            ? Center(child: icon)
            : Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 16, 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  icon,
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appText(13.5, w: FontWeight.w800, c: c.onHero).copyWith(letterSpacing: 0.1)),
                  ),
                ]),
              ),
      ),
    );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: busy ? null : onTap,
            customBorder: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: Center(widthFactor: 1, child: pill),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dot inside a ring — "you are live" (static: it tells, it does not decorate).
class _RingDot extends StatelessWidget {
  const _RingDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.55), width: 2)),
        child: Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  The home's wiring
// ─────────────────────────────────────────────────────────────────────────────

/// A weekly slot of the home's schedule, dated ("HH:MM" is UTC on the server).
GoLiveSlot goLiveSlotOf(ScheduleSession s) {
  DateTime at(String hhmm) {
    final p = hhmm.split(':');
    final d = s.scheduledDate;
    return DateTime.utc(d.year, d.month, d.day, int.tryParse(p[0]) ?? 0, p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  final start = at(s.startTime);
  final end = at(s.endTime);
  return GoLiveSlot(
    courseId: s.courseId,
    startsAt: start,
    minutes: end.isAfter(start) ? end.difference(start).inMinutes : s.durationMinutes,
    title: s.courseName,
    sessionId: s.sessionId,
    live: s.isLive,
  );
}

/// The course as the sheet draws it (the title in the app's language, the other one when it is empty).
GoLiveCourse goLiveCourseOf(TeacherCourse x) {
  final ar = x.titleAr ?? '', en = x.titleEn ?? '';
  return GoLiveCourse(
    id: x.id,
    title: AppConfig.lang == 'ar' ? (ar.isEmpty ? en : ar) : (en.isEmpty ? ar : en),
    imageUrl: x.imageUrl,
    students: x.studentsCount,
    published: x.isPublished,
    type: x.type,
  );
}

/// The header's "Go live": follows the open room ([LiveRoomHost]) and the home's live sessions.
class GoLiveEntry extends StatefulWidget {
  const GoLiveEntry({super.key, required this.courses, required this.schedule, this.loading = false, this.onDone, this.onNewCourse});

  /// The home is still loading its courses: the pill spins and waits.
  final bool loading;

  final List<TeacherCourse> courses;
  final List<ScheduleSession> schedule;

  /// After the room (or the sheet's "Meet now"): reload the home quietly.
  final VoidCallback? onDone;
  final VoidCallback? onNewCourse;

  @override
  State<GoLiveEntry> createState() => _GoLiveEntryState();
}

class _GoLiveEntryState extends State<GoLiveEntry> {
  bool _busy = false;

  ScheduleSession? get _liveSlot =>
      widget.schedule.where((s) => s.isLive && s.sessionId != null).firstOrNull;

  Future<void> _tap() async {
    if (_busy) return;
    if (LiveRoomHost.isOpen) {
      LiveRoomHost.expand(); // the room is minimized (or behind a page): back to it
      return;
    }
    setState(() => _busy = true);
    try {
      final live = _liveSlot;
      if (live != null) {
        // a room of mine runs (I left it): straight back in — /live-sessions/start resumes it
        await launchGoLive(context, GoLiveLaunch(sessionId: live.sessionId!, courseId: live.courseId, title: live.courseName));
      } else {
        await openGoLive(
          context,
          courses: [for (final x in widget.courses) goLiveCourseOf(x)],
          slots: [for (final s in widget.schedule) goLiveSlotOf(s)],
          onNewCourse: widget.onNewCourse,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: LiveRoomHost.listenable,
        builder: (context, _) => GoLiveButton(
          live: LiveRoomHost.isOpen || _liveSlot != null,
          busy: _busy || widget.loading,
          compact: MediaQuery.sizeOf(context).width < 340,
          onTap: _tap,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Flow
// ─────────────────────────────────────────────────────────────────────────────

Future<GoLivePrefs> _loadPrefs(int? userId) async {
  try {
    return GoLivePrefs.decode((await SharedPreferences.getInstance()).getString(GoLivePrefs.key(userId)));
  } catch (_) {
    return const GoLivePrefs();
  }
}

Future<void> _savePrefs(int? userId, GoLivePrefs p) async {
  try {
    await (await SharedPreferences.getInstance()).setString(GoLivePrefs.key(userId), p.encode());
  } catch (_) {}
}

/// The sheet (phones) or a dialog (from 720 px), then the room.
Future<void> openGoLive(
  BuildContext context, {
  required List<GoLiveCourse> courses,
  List<GoLiveSlot> slots = const [],
  GoLiveApi? api,
  VoidCallback? onNewCourse,
}) async {
  final userId = context.read<MyAuthProvider>().currentUser?.id;
  final prefs = await _loadPrefs(userId);
  if (!context.mounted) return;
  final now = DateTime.now().toUtc();
  final ordered = goLiveCourseOrder(courses);
  final sheet = GoLiveSheet(
    courses: ordered,
    initialCourseId: pickGoLiveCourse(courses: ordered, remembered: prefs.courseId, slots: slots, now: now),
    slots: slots,
    prefs: prefs,
    api: api ?? RemoteGoLiveApi(),
    onSave: (p) => _savePrefs(userId, p),
  );
  final result = await showGoLiveSheet(context, sheet);
  if (!context.mounted) return;
  if (result is GoLiveLaunch) {
    await launchGoLive(context, result, api: api);
  } else if (result == GoLiveSheet.meetNow) {
    final mode = AppModeController.instance;
    await startQuickMeeting(context, orgId: mode.isOrg ? mode.currentOrgId : null);
  } else if (result == GoLiveSheet.newCourse) {
    onNewCourse?.call();
  }
}

/// A bottom sheet on phones, a centered dialog from 720 px (a full-width sheet on a desktop reads as a banner).
Future<Object?> showGoLiveSheet(BuildContext context, Widget sheet) {
  if (MediaQuery.sizeOf(context).width < 720) return showAppSheet<Object>(context, (_) => sheet);
  return showDialog<Object>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: ctx.colors.cardBg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760), child: sheet),
    ),
  );
}

/// The pre-join page with autoJoin: it starts (or resumes) the session and presses Join by itself.
Future<void> launchGoLive(BuildContext context, GoLiveLaunch go, {GoLiveApi? api}) async {
  final a = api ?? RemoteGoLiveApi();
  final user = context.read<MyAuthProvider>().currentUser;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => PreJoinPage(
      startMic: go.mic,
      startCam: go.camera,
      args: JoinArgs(
        sessionId: go.sessionId,
        courseId: go.courseId,
        isTeacher: true,
        userName: user?.name ?? 'Teacher',
        userId: user?.id ?? 0,
        sessionName: go.title,
        autoJoin: true,
        apiClient: ApiClient(),
        onStart: () => a.start(go.sessionId, record: go.record),
        onEnd: () async {
          try {
            await a.end(go.sessionId);
          } catch (_) {}
        },
      ),
    ),
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
//  The sheet (state)
// ─────────────────────────────────────────────────────────────────────────────

class GoLiveSheet extends StatefulWidget {
  const GoLiveSheet({
    super.key,
    required this.courses,
    required this.initialCourseId,
    required this.api,
    this.slots = const [],
    this.prefs = const GoLivePrefs(),
    this.onSave,
    this.now,
  });

  /// Popped instead of a [GoLiveLaunch]: open "Meet now" / the course form.
  static const meetNow = 'meet_now';
  static const newCourse = 'new_course';

  final List<GoLiveCourse> courses;
  final int? initialCourseId;
  final GoLiveApi api;
  final List<GoLiveSlot> slots;
  final GoLivePrefs prefs;
  final ValueChanged<GoLivePrefs>? onSave;

  /// A fixed clock (tests / renders); null = the device clock.
  final DateTime? now;

  @override
  State<GoLiveSheet> createState() => _GoLiveSheetState();
}

class _GoLiveSheetState extends State<GoLiveSheet> {
  late int? _courseId = widget.initialCourseId;
  final Map<int, List<GoLiveSession>> _sessions = {};
  final Set<int> _failed = {};
  final _title = TextEditingController();
  late bool _camera = widget.prefs.camera;
  late bool _mic = widget.prefs.mic;
  bool? _record; // null until the teacher touches it → the default of what is selected
  bool _useSuggestion = true;
  bool _busy = false;
  String? _error;

  DateTime get _now => widget.now ?? DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _courseId;
    if (id == null || _sessions.containsKey(id)) return;
    _failed.remove(id);
    try {
      final list = await widget.api.sessions(id);
      if (!mounted) return;
      setState(() => _sessions[id] = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed.add(id)); // the sheet still offers a new session
    }
  }

  void _pickCourse(int id) {
    if (id == _courseId) return;
    setState(() {
      _courseId = id;
      _record = null;
      _useSuggestion = true;
      _error = null;
    });
    _load();
  }

  GoLiveSuggestion? get _suggestion {
    final id = _courseId;
    final list = id == null ? null : _sessions[id];
    if (id == null || (list == null && !_failed.contains(id))) return null;
    return suggestGoLive(sessions: list ?? const [], slots: [for (final s in widget.slots) if (s.courseId == id) s], now: _now);
  }

  Future<void> _go() async {
    final courseId = _courseId;
    if (courseId == null || _busy) return;
    final s = _useSuggestion ? _suggestion : null;
    final record = _record ?? goLiveDefaultRecord(s, _sessions[courseId] ?? const []);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      late final int id;
      late final String title;
      bool? sendRecord = record;
      if (s != null && s.sessionId != null) {
        id = s.sessionId!;
        title = s.title;
        if (s.live) {
          sendRecord = null; // a running room keeps its own recording
        } else if (record && !s.recordEnabled) {
          await widget.api.setRecord(id, true); // `enable_recording` may only turn it off
        }
      } else if (s != null) {
        // this hour's timetable slot has no session yet: create it at the slot's start (the home then matches it)
        title = goLiveDefaultTitle(s.startsAt);
        id = await widget.api.create(courseId: courseId, title: title, startsAt: s.startsAt, minutes: s.minutes > 0 ? s.minutes : 60, record: record);
      } else {
        final typed = _title.text.trim();
        title = typed.isEmpty ? goLiveDefaultTitle(_now) : typed;
        id = await widget.api.create(courseId: courseId, title: title, startsAt: _now, record: record);
      }
      widget.onSave?.call(widget.prefs.copyWith(courseId: courseId, camera: _camera, mic: _mic));
      if (!mounted) return;
      Navigator.of(context).pop(GoLiveLaunch(sessionId: id, courseId: courseId, title: title, record: sendRecord, camera: _camera, mic: _mic));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = ApiException.from(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _courseId;
    final loading = id != null && !_sessions.containsKey(id) && !_failed.contains(id);
    final s = _suggestion;
    final useS = _useSuggestion && s != null;
    final meetNow = !AppConfig.disableList.contains('live.quick_meeting');
    return GoLiveSheetView(
      courses: widget.courses,
      courseId: id,
      onCourse: _pickCourse,
      loadingSessions: loading,
      suggestion: s,
      useSuggestion: useS,
      onUseSuggestion: (v) => setState(() {
        _useSuggestion = v;
        _record = null;
      }),
      title: _title,
      titleHint: goLiveDefaultTitle(_now),
      record: _record ?? goLiveDefaultRecord(useS ? s : null, id == null ? const [] : _sessions[id] ?? const []),
      onRecord: (v) => setState(() => _record = v),
      camera: _camera,
      mic: _mic,
      onCamera: (v) => setState(() => _camera = v),
      onMic: (v) => setState(() => _mic = v),
      busy: _busy,
      error: _error,
      now: _now,
      onGo: id == null ? null : _go,
      onClose: () => Navigator.of(context).maybePop(),
      onMeetNow: meetNow ? () => Navigator.of(context).pop(GoLiveSheet.meetNow) : null,
      onNewCourse: () => Navigator.of(context).pop(GoLiveSheet.newCourse),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The sheet (look, plain values)
// ─────────────────────────────────────────────────────────────────────────────

class GoLiveSheetView extends StatelessWidget {
  const GoLiveSheetView({
    super.key,
    required this.courses,
    required this.courseId,
    required this.onCourse,
    required this.title,
    required this.titleHint,
    this.loadingSessions = false,
    this.suggestion,
    this.useSuggestion = false,
    this.onUseSuggestion,
    this.record = true,
    this.onRecord,
    this.camera = true,
    this.mic = true,
    this.onCamera,
    this.onMic,
    this.busy = false,
    this.error,
    this.onGo,
    this.onClose,
    this.onMeetNow,
    this.onNewCourse,
    this.now,
  });

  final List<GoLiveCourse> courses;
  final int? courseId;
  final ValueChanged<int> onCourse;
  final bool loadingSessions;
  final GoLiveSuggestion? suggestion;

  /// The suggested session is the one selected (else "New live session now").
  final bool useSuggestion;
  final ValueChanged<bool>? onUseSuggestion;
  final TextEditingController title;
  final String titleHint;
  final bool record;
  final ValueChanged<bool>? onRecord;
  final bool camera, mic;
  final ValueChanged<bool>? onCamera, onMic;
  final bool busy;
  final String? error;
  final VoidCallback? onGo, onClose, onMeetNow, onNewCourse;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = suggestion;
    final rejoin = useSuggestion && s != null && s.live;
    final body = <Widget>[
      if (courses.isEmpty)
        _NoCourse(onNewCourse: onNewCourse)
      else ...[
        _Label(t('الكورس', 'Course')),
        const SizedBox(height: 8),
        _CoursePicker(courses: courses, selected: courseId, onPick: onCourse),
        const SizedBox(height: 18),
        _Label(t('الحصة', 'Session')),
        const SizedBox(height: 8),
        if (loadingSessions)
          const AppShimmer(child: AppSkeletonBox(width: double.infinity, height: 72, radius: 18))
        else ...[
          if (s != null) ...[
            _Option(
              selected: useSuggestion,
              onTap: onUseSuggestion == null ? null : () => onUseSuggestion!(true),
              icon: s.live ? Icons.sensors_rounded : Icons.event_available_rounded,
              tone: s.live ? c.danger : c.primary,
              title: s.title.isEmpty ? t('حصة اليوم', "Today's class") : s.title,
              subtitle: _suggestionLine(s, now ?? DateTime.now().toUtc()),
              badge: s.live ? t('مباشر الآن', 'Live now') : t('في موعدها', 'On schedule'),
            ),
            const SizedBox(height: 10),
          ],
          _Option(
            selected: !useSuggestion || s == null,
            onTap: onUseSuggestion == null || s == null ? null : () => onUseSuggestion!(false),
            icon: Icons.bolt_rounded,
            tone: c.accent2,
            title: t('حصة مباشرة جديدة الآن', 'New live session now'),
            subtitle: t('تُضاف إلى حصص الكورس وتبدأ فورًا', "Added to the course's sessions, starts right away"),
            child: !useSuggestion || s == null
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: title,
                      enabled: !busy,
                      textInputAction: TextInputAction.go,
                      maxLength: 120,
                      style: appText(14, w: FontWeight.w600, c: c.textDark),
                      decoration: InputDecoration(
                        isDense: true,
                        counterText: '',
                        // the default title shows as the hint at once: an empty field is a valid answer
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        labelText: t('العنوان (اختياري)', 'Title (optional)'),
                        hintText: titleHint,
                        prefixIcon: Icon(Icons.edit_rounded, size: 18, color: c.textLight),
                      ),
                    ),
                  )
                : null,
          ),
        ],
        const SizedBox(height: 18),
        _Label(t('قبل الدخول', 'Before you go in')),
        const SizedBox(height: 4),
        if (!rejoin)
          AppSwitchTile(
            icon: Icons.fiber_manual_record_rounded,
            activeColor: c.danger,
            title: t('تسجيل الحصة', 'Record this session'),
            subtitle: t('يشاهدها الطلاب لاحقًا من صفحة الكورس', 'Students can watch it later from the course'),
            value: record,
            onChanged: busy ? null : onRecord,
          ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: _DeviceToggle(
              on: camera,
              iconOn: Icons.videocam_rounded,
              iconOff: Icons.videocam_off_rounded,
              label: camera ? t('الكاميرا تعمل', 'Camera on') : t('الكاميرا مغلقة', 'Camera off'),
              onChanged: busy ? null : onCamera,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DeviceToggle(
              on: mic,
              iconOn: Icons.mic_rounded,
              iconOff: Icons.mic_off_rounded,
              label: mic ? t('الميكروفون يعمل', 'Mic on') : t('الميكروفون مغلق', 'Mic off'),
              onChanged: busy ? null : onMic,
            ),
          ),
        ]),
        if (error != null) ...[
          const SizedBox(height: 14),
          AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
        ],
      ],
    ];

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(onClose: onClose),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
          // the course row runs edge to edge (it scrolls sideways); everything else keeps the 20 px gutter
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final w in body) w is _CoursePicker ? w : Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: w),
          ]),
        ),
      ),
      // the action stays in view: the big button, then the secondary way (a meeting without a course)
      DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (courses.isNotEmpty) _GoButton(label: rejoin ? t('العودة إلى البث', 'Rejoin the live') : t('ابدأ البث الآن', 'Go live now'), busy: busy, onPressed: onGo),
            if (onMeetNow != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: TextButton.icon(
                  onPressed: busy ? null : onMeetNow,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: appInk(context, c.primary)),
                  icon: const Icon(Icons.video_call_rounded, size: 20),
                  label: Text(t('اجتماع مباشر بدون كورس', 'Meet now, without a course'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: appInk(context, c.primary))),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

/// "On schedule · 10:00 – 11:30 · in 12 min" / "Live · since 10:02".
String _suggestionLine(GoLiveSuggestion s, DateTime now) {
  final start = AppTime.time(s.startsAt);
  if (s.live) return '${t('بدأت', 'Started')} $start';
  final end = s.endsAt;
  final range = end == null ? start : '$start – ${AppTime.time(end)}';
  final mins = s.startsAt.difference(now).inMinutes;
  final when = mins > 0
      ? t('بعد {d}', 'in {d}').replaceAll('{d}', homeDurationText(mins))
      : (end != null && now.isBefore(end)
          ? t('جارية الآن', 'running now')
          : t('منذ {d}', '{d} ago').replaceAll('{d}', homeDurationText(mins.abs().clamp(1, 600))));
  return '$range · $when';
}

class _Header extends StatelessWidget {
  const _Header({this.onClose});
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = ensureContrast(c.danger, [c.onHero]);
    // a soft live-red wash behind the title, fading into the card
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fill.withValues(alpha: c.isDark ? 0.14 : 0.07), fill.withValues(alpha: 0)],
        ),
      ),
      child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 14),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [fill, Color.lerp(fill, Colors.black, 0.2)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: fill.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Icon(Icons.sensors_rounded, color: c.onHero, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(t('ابدأ بثًا مباشرًا', 'Go live'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(20, w: FontWeight.w900, c: c.textDark, h: 1.2)),
            const SizedBox(height: 2),
            Text(t('اختر الكورس وستكون في الغرفة خلال ثوانٍ', "Pick the course, you'll be in the room in seconds"),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium, h: 1.35)),
          ]),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: t('إغلاق', 'Close'),
          style: IconButton.styleFrom(backgroundColor: c.inputBg, minimumSize: const Size(44, 44)),
          onPressed: onClose,
          icon: Icon(Icons.close_rounded, color: c.textMedium, size: 20),
        ),
      ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: appText(12.5, w: FontWeight.w800, c: context.colors.textMedium).copyWith(letterSpacing: 0.2));
}

/// The courses as a row of cards (scrolls sideways); one course → one full-width card.
class _CoursePicker extends StatelessWidget {
  const _CoursePicker({required this.courses, required this.selected, required this.onPick});
  final List<GoLiveCourse> courses;
  final int? selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    if (courses.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _CourseCard(course: courses.first, selected: true, onTap: null),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return AppHScroll(
      // a mouse needs the thumb; a finger swipes (the next card peeking at the edge says there is more)
      thumbVisibility: wide,
      padding: EdgeInsets.fromLTRB(20, 0, 20, wide ? 12 : 2),
      // every card as tall as the tallest (a two-line title must not make one card stick out)
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < courses.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            SizedBox(
              width: 224,
              child: _CourseCard(course: courses[i], selected: courses[i].id == selected, onTap: () => onPick(courses[i].id)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.selected, this.onTap});
  final GoLiveCourse course;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(18);
    final ink = appInk(context, c.primary);
    final initial = course.title.trim().isEmpty ? '·' : course.title.trim().characters.first.toUpperCase();
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: Material(
        color: selected ? Color.alphaBlend(c.primary.withValues(alpha: c.isDark ? 0.16 : 0.07), c.cardBg) : c.cardBg,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(10),
            alignment: AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 46,
                  child: course.imageUrl.isNotEmpty
                      ? AppNetworkImage(url: course.imageUrl, width: 46, height: 46)
                      : ColoredBox(
                          color: c.primaryTint,
                          child: Center(child: Text(initial, style: appText(18, w: FontWeight.w900, c: ink))),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(course.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w800, c: c.textDark, h: 1.25)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      t('{n} طالب', '{n} students').replaceAll('{n}', appCompactNumber(course.students)),
                      if (!course.published) t('مسودة', 'Draft'),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(11.5, w: FontWeight.w600, c: c.textMedium),
                  ),
                ]),
              ),
              const SizedBox(width: 6),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: ensureContrast(c.primary, [c.onHero])),
                  child: Icon(Icons.check_rounded, size: 15, color: c.onHero),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One way to go live (radio card): the suggested session or a new one; [child] shows under the selected one.
class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    this.badge,
    this.onTap,
    this.child,
  });

  final bool selected;
  final IconData icon;
  final Color tone;
  final String title, subtitle;
  final String? badge;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(18);
    final ink = appInk(context, tone);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? Color.alphaBlend(tone.withValues(alpha: c.isDark ? 0.14 : 0.06), c.cardBg) : c.cardBg,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: r, border: Border.all(color: selected ? tone : c.divider, width: selected ? 1.6 : 1)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: tone.withValues(alpha: c.isDark ? 0.22 : 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 21, color: ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (badge != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: tone.withValues(alpha: c.isDark ? 0.24 : 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text(badge!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: FontWeight.w800, c: ink)),
                      ),
                      const SizedBox(height: 5),
                    ],
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w800, c: c.textDark, h: 1.25)),
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium, h: 1.35)),
                  ]),
                ),
                const SizedBox(width: 10),
                _Radio(on: selected, tone: tone),
              ]),
              ?child,
            ]),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on, required this.tone});
  final bool on;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = ensureContrast(tone, [c.cardBg], min: 3);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? ink : c.textLight.withValues(alpha: 0.6), width: 2)),
      child: on ? Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: ink)) : null,
    );
  }
}

/// Camera / microphone to start with: a tinted tile when on, a quiet one when off.
class _DeviceToggle extends StatelessWidget {
  const _DeviceToggle({required this.on, required this.iconOn, required this.iconOff, required this.label, this.onChanged});
  final bool on;
  final IconData iconOn, iconOff;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(14);
    final ink = on ? appInk(context, c.primary) : c.textMedium;
    return Semantics(
      toggled: on,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: on ? Color.alphaBlend(c.primary.withValues(alpha: c.isDark ? 0.16 : 0.08), c.cardBg) : c.inputBg,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          onTap: onChanged == null ? null : () => onChanged!(!on),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(borderRadius: r, border: Border.all(color: on ? c.primary.withValues(alpha: 0.45) : c.divider)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(on ? iconOn : iconOff, size: 19, color: ink),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w700, c: ink)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GoButton extends StatelessWidget {
  const _GoButton({required this.label, required this.busy, this.onPressed});
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = ensureContrast(c.danger, [c.onHero]);
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: c.onHero,
          disabledBackgroundColor: fill.withValues(alpha: 0.55),
          disabledForegroundColor: c.onHero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (busy)
            SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.onHero))
          else
            Icon(Icons.sensors_rounded, size: 22, color: c.onHero),
          const SizedBox(width: 10),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w900, c: c.onHero)),
          ),
        ]),
      ),
    );
  }
}

class _NoCourse extends StatelessWidget {
  const _NoCourse({this.onNewCourse});
  final VoidCallback? onNewCourse;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AppEmpty(
          icon: Icons.auto_stories_rounded,
          title: t('لا يوجد كورس بعد', 'No course yet'),
          message: t('أنشئ كورسًا لتبث لطلابه مباشرة، أو ابدأ اجتماعًا بدون كورس.',
              'Create a course to go live with its students, or start a meeting without one.'),
          actionLabel: onNewCourse == null ? null : t('إضافة كورس', 'Add a course'),
          onAction: onNewCourse,
        ),
      );
}
