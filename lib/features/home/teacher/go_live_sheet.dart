// lib/features/home/teacher/go_live_sheet.dart — "Go live" on the instructor home (D-091): the button and the sheet.
//
//   GoLiveButton     the header's red pill ("Go live" / "Return to live" while a room of mine runs), plain values;
//                    `onHero`: the greeting hero's paper call to action (D-631) — red again only while a room runs
//   GoLiveEntry      the home's wiring: the button + LiveRoomHost (a minimized room → back to it) + the sheet
//   GoLiveSheetView  the sheet's content over plain values (layout-tested: test/ui/go_live_layout_test.dart):
//                      course (horizontal cards) · session (the one scheduled now first, or "New live session now"
//                      with an optional title) · Record · camera / microphone · the big "Go live" · "Meet now"
//   openGoLive       tap → the sheet (a dialog from 720 px) → PreJoinPage, where the teacher presses Join (D-106)
//
// Data: nothing is asked when the home opens; the sheet asks GET /courses/{id}/sessions for the course it shows
// (cached per course while it is open). Pure logic: go_live.dart. Renders: test/visual/go_live_golden_test.dart.
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeBar;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase, AppPressScale;
import 'package:flutter_education_app/design/home_kit.dart' show homeDurationText;
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart' show startQuickMeeting;
import 'package:flutter_education_app/features/live/live_room_host.dart';
import 'package:flutter_education_app/features/live/room/join_args.dart';
import 'package:flutter_education_app/features/home/teacher/go_live.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  The header pill
// ─────────────────────────────────────────────────────────────────────────────

/// The "Go live" pill (a 48 px tap target around a 40 px pill): the primary with a small live-red dot (red stays for
/// what is live, D-630). [live] → "Return to live" with a ringed red dot. [compact] → the round icon only (narrow
/// headers). [onHero] → the greeting hero's call to action: a full-height cream pill in the primary ink.
class GoLiveButton extends StatelessWidget {
  const GoLiveButton({super.key, this.live = false, this.onTap, this.busy = false, this.compact = false, this.onHero = false, this.block = false});

  /// T1 (Tea1Home): the hero's one call to action as a full-width live-red pill with the white dot ("Go live" /
  /// "Back to the live").
  final bool block;

  final bool live;
  final VoidCallback? onTap;
  final bool busy;
  final bool compact;
  final bool onHero;

  Widget _blockButton(BuildContext context) {
    final c = context.colors;
    final label = live ? 't1_hm_go_back'.tr : 't1_hm_go_live'.tr;
    final ink = c.onHero;
    final dot = busy
        ? SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: ink))
        : Container(
            width: AppSpace.sm,
            height: AppSpace.sm,
            decoration: BoxDecoration(color: ink, shape: BoxShape.circle, boxShadow: [BoxShadow(color: ink.withValues(alpha: .35), spreadRadius: AppSpace.xxs)]),
          );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: AppPressScale(
        enabled: !busy && onTap != null,
        scale: 0.98,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c.danger, Color.lerp(c.danger, c.onHero, .12)!]),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: [BoxShadow(color: c.danger.withValues(alpha: .35), blurRadius: AppSpace.md, offset: const Offset(0, AppSpace.xs))],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const ValueKey('t1_home.go_live'),
              onTap: busy ? null : onTap,
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min + AppSpace.xs),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: ink))),
                    const SizedBox(width: AppSpace.sm),
                    dot,
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String labelFor(bool live) => live ? t('العودة للبث', 'Return to live') : t('ابدأ البث', 'Go live');

  /// The pill's height inside its 48 px target.
  static const double _pill = AppTouch.min - AppSpace.xs;

  @override
  Widget build(BuildContext context) {
    if (block) return _blockButton(context);
    final c = context.colors;
    // the primary action in emerald, not a solid live red (D-630: red only where it means something): on the forest
    // hero (the greeting hero's call to action, or inside a ChromeBar) a cream plate in emerald ink, elsewhere the
    // solid primary in cream; the small red dot says "live"
    final hero = onHero || ChromeBar.of(context);
    // D-649: the greeting hero's call to action is THE gold highlight (accent2 → lighter, a dark ink); a ChromeBar
    // plate stays cream
    final gold = onHero && !live;
    final fill = hero ? c.onHero : c.primary;
    final ink = gold
        ? AppBrandLayer.of(context).goldInk
        : hero
            ? ensureContrast(c.primary, [fill])
            : ensureContrast(c.onHero, [fill]);
    final label = labelFor(live);
    final icon = busy
        ? SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: ink))
        : live
            ? _RingDot(color: c.danger)
            : _LiveDot(color: c.danger, ring: c.onHero);
    final height = onHero ? AppTouch.min : _pill;
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: gold ? null : fill,
        gradient: gold ? AppBrandLayer.gold(context) : null,
        boxShadow: gold ? AppBrandLayer.goldShadow(context) : null,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: SizedBox(
        height: height,
        width: compact ? height : null,
        child: compact
            ? Center(child: icon)
            : Padding(
                padding: onHero
                    ? const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.lg, 0)
                    : const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, 0, AppSpace.md, 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  icon,
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
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
        child: AppPressScale(
          enabled: !busy && onTap != null,
          scale: 0.97,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: busy ? null : onTap,
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
                child: Center(widthFactor: 1, child: pill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small red dot of "go live" (static), ringed in [ring] so it parts from an emerald fill.
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color, required this.ring});
  final Color color, ring;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: AppIconSize.sm,
        child: Center(
          child: Container(
            width: AppSpace.xs + AppSpace.xxs / 2,
            height: AppSpace.xs + AppSpace.xxs / 2,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: ring, width: AppBorder.hairline)),
          ),
        ),
      );
}

/// A dot inside a ring — "you are live" (static: it tells, it does not decorate).
class _RingDot extends StatelessWidget {
  const _RingDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: AppIconSize.sm,
        height: AppIconSize.sm,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.55), width: AppBorder.focus)),
        child: Container(
          width: AppSpace.xs - 1,
          height: AppSpace.xs - 1,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
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
  const GoLiveEntry({super.key, required this.courses, required this.schedule, this.loading = false, this.onDone, this.onNewCourse, this.onHero = false, this.block = false});

  /// The T1 hero's full-width live-red call to action ([GoLiveButton.block]).
  final bool block;

  /// Drawn as the greeting hero's call to action ([GoLiveButton.onHero]).
  final bool onHero;

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
          onHero: widget.onHero,
          block: widget.block,
          onTap: _tap,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Flow
// ─────────────────────────────────────────────────────────────────────────────

/// A course's students on its card: "طالب واحد" / "طالبان" / "4 طلاب" / "12 طالبًا" (compact above 999: "1.3K طالب").
String goLiveStudentsText(int n) => countText(n,
        ar0: 'لا طلاب بعد', ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالبًا',
        en0: 'No students yet', en1: '1 student', en: '{n} students')
    .replaceFirst('$n', appCompactNumber(n));

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

/// The app's sheet: a bottom sheet on phones, the side panel on wide windows (D-360).
Future<Object?> showGoLiveSheet(BuildContext context, Widget sheet) => showAppSheet<Object>(context, (_) => sheet);

/// The pre-join page of the chosen session, with the sheet's camera / microphone choice. It waits for the teacher
/// to press Join (D-106), which starts (or resumes) the session and opens the room.
Future<void> launchGoLive(BuildContext context, GoLiveLaunch go, {GoLiveApi? api}) async {
  final a = api ?? RemoteGoLiveApi();
  final user = context.read<MyAuthProvider>().currentUser;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => deferredPreJoin(
      startMic: go.mic,
      startCam: go.camera,
      args: JoinArgs(
        sessionId: go.sessionId,
        courseId: go.courseId,
        isTeacher: true,
        userName: user?.name ?? 'Teacher',
        userId: user?.id ?? 0,
        sessionName: go.title,
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
        id = await widget.api.create(courseId: courseId, title: '', startsAt: s.startsAt, minutes: s.minutes > 0 ? s.minutes : 60, record: record);
      } else {
        final typed = _title.text.trim();
        title = typed.isEmpty ? goLiveDefaultTitle(_now) : typed;
        id = await widget.api.create(courseId: courseId, title: typed, startsAt: _now, record: record);
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
    this.record = false,
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
        _Label(t('الدورة', 'Course')),
        _CoursePicker(courses: courses, selected: courseId, onPick: onCourse),
        _Label(t('الحصة', 'Session'), first: false),
        if (loadingSessions)
          const AppShimmer(child: AppSkeletonBox(width: double.infinity, height: AppTouch.min * 1.5, radius: AppRadius.card))
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
              badgeTone: s.live ? AppTone.danger : AppTone.success,
            ),
            const SizedBox(height: AppSpace.xs),
          ],
          _Option(
            selected: !useSuggestion || s == null,
            onTap: onUseSuggestion == null || s == null ? null : () => onUseSuggestion!(false),
            icon: Icons.bolt_rounded,
            tone: c.primary,
            title: t('حصة مباشرة جديدة الحين', 'New live session now'),
            subtitle: t('تُضاف إلى حصص الكورس وتبدأ فورًا', "Added to the course's sessions, starts right away"),
            child: !useSuggestion || s == null
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpace.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                      AppFieldLabel(t('العنوان (اختياري)', 'Title (optional)')),
                      // the label above is drawn for the eye only: the field says it to a screen reader
                      Semantics(
                        label: t('العنوان (اختياري)', 'Title (optional)'),
                        child: TextField(
                          controller: title,
                          enabled: !busy,
                          textInputAction: TextInputAction.go,
                          maxLength: 120,
                          style: appFieldTextStyle(context),
                          // the default title shows as the hint at once: an empty field is a valid answer
                          decoration: appFieldDecoration(context, hint: titleHint, icon: Icons.edit_rounded, enabled: !busy)
                              .copyWith(counterText: ''),
                        ),
                      ),
                    ]),
                  )
                : null,
          ),
        ],
        _Label(t('قبل تدخل', 'Before you go in'), first: false),
        if (!rejoin)
          AppSwitchTile(
            icon: Icons.fiber_manual_record_rounded,
            // the switch keeps the app's primary track (M22); only the small dot says "recording" in red
            iconColor: record ? c.danger : c.textLight,
            title: t('سجّل الحصة', 'Record this session'),
            subtitle: t('يشوفها الطلاب بعدين من صفحة الدورة', 'Students can watch it later from the course'),
            value: record,
            onChanged: busy ? null : onRecord,
          ),
        const SizedBox(height: AppSpace.xs),
        Row(children: [
          Expanded(
            child: _DeviceToggle(
              on: camera,
              iconOn: Icons.videocam_rounded,
              iconOff: Icons.videocam_off_rounded,
              label: camera ? t('الكاميرا شغّالة', 'Camera on') : t('الكاميرا مغلقة', 'Camera off'),
              onChanged: busy ? null : onCamera,
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: _DeviceToggle(
              on: mic,
              iconOn: Icons.mic_rounded,
              iconOff: Icons.mic_off_rounded,
              label: mic ? t('المايك شغّال', 'Mic on') : t('المايك مغلق', 'Mic off'),
              onChanged: busy ? null : onMic,
            ),
          ),
        ]),
        if (error != null) ...[
          const SizedBox(height: AppSpace.md),
          AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
        ],
      ],
    ];

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(onClose: onClose),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          // the course row runs edge to edge (it scrolls sideways); everything else keeps the sheet's gutter
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final w in body) w is _CoursePicker ? w : Padding(padding: _kSheetSides, child: w),
          ]),
        ),
      ),
      // the action stays in view: the big button, then the secondary way (a meeting without a course)
      DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_kSheetInset, AppSpace.sm, _kSheetInset, AppSpace.xs),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (courses.isNotEmpty) _GoButton(label: rejoin ? t('ارجع للبث', 'Rejoin the live') : t('ابدأ البث الحين', 'Go live now'), busy: busy, onPressed: onGo),
            if (onMeetNow != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Center(
                  child: AppButton.ghost(
                    label: t('اجتماع مباشر بدون دورة', 'Meet now, without a course'),
                    icon: Icons.video_call_rounded,
                    onPressed: busy ? null : onMeetNow,
                  ),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

/// The sheet's side gutter (in line with the kit's sheet header).
const double _kSheetInset = AppSpace.md + AppSpace.xxs;
const EdgeInsets _kSheetSides = EdgeInsets.symmetric(horizontal: _kSheetInset);

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

/// The sheet's masthead: a live-red mark on its own tint, the editorial title, one line of direction, Close. No
/// wash behind it: the mark carries the colour (D-612).
class _Header extends StatelessWidget {
  const _Header({this.onClose});
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = appTintOn(context, c.danger);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(_kSheetInset, AppSpace.lg, AppSpace.sm, AppSpace.md),
      child: Row(children: [
        Container(
          width: AppTouch.min,
          height: AppTouch.min,
          decoration: BoxDecoration(color: tint, borderRadius: AppRadius.controlAll),
          child: Icon(Icons.sensors_rounded, color: appInkOn(context, c.danger, tint), size: AppIconSize.lg),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Semantics(
              header: true,
              child: Text(t('ابدأ بث مباشر', 'Go live'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.headline(context)),
            ),
            Text(t('اختر الدورة والحصة، وجهّز الكاميرا والمايك قبل تدخل', 'Pick the course and the session, set up camera and mic before you go in'),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        IconButton(
          tooltip: t('إغلاق', 'Close'),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          style: IconButton.styleFrom(backgroundColor: c.inputBg),
          onPressed: onClose,
          icon: Icon(Icons.close_rounded, color: c.textMedium, size: AppIconSize.md),
        ),
      ]),
    );
  }
}

/// A group's name in the sheet (sentence case, the label role): 24 above it from the group before, 8 under it.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.first = true});
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: first ? 0 : AppSpace.lg, bottom: AppSpace.xs),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.label(context).copyWith(color: context.colors.textMedium, fontWeight: FontWeight.w600)),
      );
}

/// The courses as a row of cards (scrolls sideways); one course → one full-width card.
class _CoursePicker extends StatelessWidget {
  const _CoursePicker({required this.courses, required this.selected, required this.onPick});
  final List<GoLiveCourse> courses;
  final int? selected;
  final ValueChanged<int> onPick;

  /// A card's width in the sideways row: two lines of a title and the next card peeking at a phone's edge.
  static const double _cardWidth = 150;

  @override
  Widget build(BuildContext context) {
    if (courses.length == 1) {
      return Padding(padding: _kSheetSides, child: _CourseCard(course: courses.first, selected: true, onTap: null));
    }
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return AppHScroll(
      // a mouse needs the thumb; a finger swipes (the next card peeking at the edge says there is more)
      thumbVisibility: wide,
      padding: EdgeInsets.fromLTRB(_kSheetInset, 0, _kSheetInset, wide ? AppSpace.sm : AppSpace.xxs),
      // every card as tall as the tallest (a two-line title must not make one card stick out)
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < courses.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.xs),
            SizedBox(
              width: _cardWidth,
              child: _CourseCard(course: courses[i], selected: courses[i].id == selected, onTap: () => onPick(courses[i].id)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// A course to pick: paper on a warm hairline; picked = the emerald ring and its check. A course without a cover
/// shows its initial on its own block tone (a course keeps its tone everywhere: [AppBlockTone.forKey]).
class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.selected, this.onTap});
  final GoLiveCourse course;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = AppRadius.cardAll;
    final ring = appInk(context, c.primary);
    final block = AppBlockColors.of(context, AppBlockTone.forKey('course:${course.id}'));
    final initial = course.title.trim().isEmpty ? '·' : course.title.trim().characters.first.toUpperCase();
    final motion = AppMotion.of(context).fast;
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: AppPressScale(
        enabled: onTap != null,
        child: Material(
          color: c.cardBg,
          borderRadius: r,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: AnimatedContainer(
              duration: motion,
              curve: AppMotion.curve,
              padding: const EdgeInsets.all(AppSpace.xs),
              decoration: BoxDecoration(
                borderRadius: r,
                border: Border.all(color: selected ? ring : c.divider, width: selected ? AppBorder.focus : AppBorder.hairline),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                // the cover (or the course's own block tone with its initial) with the check on it
                ClipRRect(
                  borderRadius: AppRadius.chipAll,
                  child: SizedBox(
                    height: AppTouch.min + AppSpace.md,
                    child: Stack(fit: StackFit.expand, children: [
                      course.imageUrl.isNotEmpty
                          ? AppNetworkImage(url: course.imageUrl, width: double.infinity, height: AppTouch.min + AppSpace.md)
                          : ColoredBox(
                              color: block.surface,
                              child: Center(child: Text(initial, style: AppType.headline(context).copyWith(color: block.ink))),
                            ),
                      PositionedDirectional(
                        top: AppSpace.xs,
                        start: AppSpace.xs,
                        child: AnimatedOpacity(
                          opacity: selected ? 1 : 0,
                          duration: motion,
                          child: Container(
                            width: AppIconSize.lg,
                            height: AppIconSize.lg,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: ensureContrast(c.primary, [c.onHero])),
                            child: Icon(Icons.check_rounded, size: AppIconSize.sm, color: c.onHero),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(course.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                const SizedBox(height: AppSpace.xxs / 2),
                Text(
                  [
                    goLiveStudentsText(course.students),
                    if (!course.published) t('مسودة', 'Draft'),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context),
                ),
              ]),
            ),
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
    this.badgeTone = AppTone.brand,
    this.onTap,
    this.child,
  });

  final bool selected;
  final IconData icon;
  final Color tone;
  final String title, subtitle;
  final String? badge;
  final AppTone badgeTone;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = AppRadius.cardAll;
    final well = appTintOn(context, tone);
    final ink = appInkOn(context, tone, well);
    final ring = ensureContrast(tone, [c.cardBg], min: 3);
    final motion = AppMotion.of(context).fast;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: c.cardBg,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: AnimatedContainer(
            duration: motion,
            curve: AppMotion.curve,
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: selected ? ring : c.divider, width: selected ? AppBorder.focus : AppBorder.hairline),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: AppSpace.xxl - AppSpace.xs,
                  height: AppSpace.xxl - AppSpace.xs,
                  decoration: BoxDecoration(color: well, borderRadius: AppRadius.chipAll),
                  child: Icon(icon, size: AppIconSize.md, color: ink),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (badge != null) ...[
                      AppStatusBadge(label: badge!, tone: badgeTone),
                      const SizedBox(height: AppSpace.xxs),
                    ],
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(height: 1.25)),
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ]),
                ),
                const SizedBox(width: AppSpace.sm),
                Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: _Radio(on: selected, ink: ring)),
              ]),
              // the title field opens under the picked option (the card grows, never jumps)
              AnimatedSize(duration: motion, curve: AppEase.out, alignment: AlignmentDirectional.topStart, child: child ?? const SizedBox(width: double.infinity)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on, required this.ink});
  final bool on;
  final Color ink;

  static const double _size = AppIconSize.md + 2;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: AppMotion.of(context).fast,
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? ink : c.textLight.withValues(alpha: 0.6), width: AppBorder.focus)),
      child: on ? Container(width: _size / 2 - 1, height: _size / 2 - 1, decoration: BoxDecoration(shape: BoxShape.circle, color: ink)) : null,
    );
  }
}

/// Camera / microphone to start with: the emerald tint when on, the quiet input well when off.
class _DeviceToggle extends StatelessWidget {
  const _DeviceToggle({required this.on, required this.iconOn, required this.iconOff, required this.label, this.onChanged});
  final bool on;
  final IconData iconOn, iconOff;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = AppRadius.controlAll;
    final tint = appTintOn(context, c.primary);
    final ink = on ? appInkOn(context, c.primary, tint) : c.textMedium;
    return Semantics(
      toggled: on,
      button: true,
      label: label,
      excludeSemantics: true,
      child: AppPressScale(
        enabled: onChanged != null,
        child: Material(
          color: on ? tint : c.inputBg,
          borderRadius: r,
          child: InkWell(
            borderRadius: r,
            onTap: onChanged == null ? null : () => onChanged!(!on),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              decoration: BoxDecoration(borderRadius: r, border: Border.all(color: on ? ink.withValues(alpha: 0.35) : c.divider, width: AppBorder.hairline)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(on ? iconOn : iconOff, size: AppIconSize.md, color: ink),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet's one big action: the solid live red at the phone hero height (56), the label in the button role.
class _GoButton extends StatelessWidget {
  const _GoButton({required this.label, required this.busy, this.onPressed});
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppButton.danger(
        label: label,
        icon: Icons.sensors_rounded,
        size: AppButtonSize.lg,
        expand: true,
        busy: busy,
        onPressed: onPressed,
      );
}

class _NoCourse extends StatelessWidget {
  const _NoCourse({this.onNewCourse});
  final VoidCallback? onNewCourse;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
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
