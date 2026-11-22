// lib/features/calendar/schedule_page.dart — THE schedule page (D-085): "My schedule" and "My calendar" are
// one page. The student / teacher shell's Schedule tab, the top-bar calendar icon, '/calendar' (deep links,
// notification taps, AppNavigator's `calendar` / `live_lobby`) and the organization / department calendars all open it.
//
//   SchedulePage()                       everything I belong to: org timetables (with one-date changes), exams, course
//                                        live sessions, a personal course's weekly appointments, meetings
//   SchedulePage(orgId: o)               one organization (+ my personal meetings)
//   SchedulePage(deptId: d)              a department's calendar (its meetings; new ones belong to the department)
//   SchedulePage(asTab: true)            inside a role shell (no back arrow; on desktop the shell's top bar has the title)
//
//   Two tabs (D-321), the last one remembered on the device with the grid it was on:
//     Scheduled meetings (phone default): today's hero, Live now · Join on top, then what is coming by day ("Show the
//       next two weeks" reaches further); "Past and ended" flips the list to what has finished (its time passed or
//       the meeting was closed), newest first, fetched only when opened.
//     Calendar (desktop default): Day (week strip + time grid) · Week · Month (desktop: the big grid; phone, its
//       default: a month of dots + that day's list). The phone header's month title opens a mini month, "Today" jumps
//       back, a horizontal swipe moves the range on phones.
//   The desktop sidebar (both tabs): mini month (a day picked from the list opens it on the Calendar tab), up next,
//   invitations, filters. Filters: the four kinds + the organizations, as chips on phones, remembered on the device.
//   "New meeting" / "Meet now" are the primary actions.
//
//   Data: ONE GET /me/calendar?detail=true per visible range through CalendarStore (cached; the list and the day
//   view fetch whole weeks so switching views reuses it), plus — student / teacher only — the weekly appointments of
//   personal courses (GET /student|teacher/schedules, cached, never failing the page). Live: the store reloads on
//   `calendar_updated` / `meeting_live` / `session_live` / timetable `attention_changed`; the home's live rooms
//   (MeHomeService.liveNow, no extra request) turn rows into "Live now · Join". No polling timer (a one-minute clock
//   only redraws the "now" line).
//
// Pure parts: schedule_logic.dart; presentational parts: schedule_parts.dart, calendar_views.dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/features/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/core/live/live_events_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/org/org_member_changes.dart' show respondToChange, undoChange;
import 'package:flutter_education_app/features/org/org_member_pages.dart' show OrgTimetableScreen;
import 'package:flutter_education_app/features/org/org_my_exams.dart' show openMyExams;
import 'package:flutter_education_app/features/courses/student/details/course_live_join.dart' show openCourseLiveRoom;
import 'package:flutter_education_app/features/home/student/home_live.dart' show joinHomeLiveRoom;
import 'package:flutter_education_app/features/home/teacher/queue_work_items.dart' show openTeacherCourseSessions;
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_education_app/core/share/external_link.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t, asMap;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/meeting_links_page.dart' show MeetingLinksIcon, kMeetingLinksFeatureKey, openMeetingLinks;
import 'package:flutter_education_app/features/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart';
import 'package:flutter_education_app/features/calendar/calendar_models.dart';
import 'package:flutter_education_app/features/calendar/calendar_views.dart';
import 'package:flutter_education_app/features/calendar/schedule_logic.dart';
import 'package:flutter_education_app/features/calendar/schedule_parts.dart';
import 'package:flutter_education_app/features/calendar/schedule_store.dart';
import 'package:flutter_education_app/features/calendar/recurrence/series_actions.dart';

/// The width from which the page shows its sidebar (mini month, filters, up next, invitations).
const calWideBreakpoint = 1000.0;

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    this.orgId,
    this.deptId,
    this.openMeetingId,
    this.title,
    this.asTab = false,
    this.initialView,
    this.api = const RemoteCalendarApi(),
    this.store,
    this.now,
    this.liveKeys,
    this.weeklyGet,
    this.role,
  });

  final int? orgId, deptId, openMeetingId;
  final String? title;
  final bool asTab;
  final CalView? initialView;
  final CalendarApi api;

  /// Tests / renders: their own cache, a fixed clock (UTC), the live rooms, the weekly appointments' GET, the role.
  final CalendarStore? store;
  final DateTime? now;
  final Set<String>? liveKeys;
  final Future<dynamic> Function(String path)? weeklyGet;
  final String? role;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> with WidgetsBindingObserver {
  CalendarStore get _store => widget.store ?? CalendarStore.instance;

  CalView? _view;

  /// The view the Calendar tab goes back to (null: its default for the width).
  CalView? _gridView;

  /// The list tab is on "Past and ended"; how many days back it has fetched (0 until it is first opened).
  bool _showPast = false;
  int _pastDays = 0;

  /// The first day of the grids; the list always starts today.
  late DateTime _anchor = calDay(_nowWall);

  /// The rolling week's first day (D-101): the focused day is its second column; kept while the focus stays inside.
  late DateTime _weekFrom = calWeekFrom(_anchor);
  late DateTime _pickerMonth = DateTime(_anchor.year, _anchor.month);
  int _agendaDays = calAgendaDays;
  CalFilters _filters = const CalFilters();
  CalChunk? _chunk;
  List<CalWeeklySlot> _weekly = const [];
  bool _loading = false, _pickerOpen = false;
  String? _error;
  int _req = 0, _slide = 0;
  Timer? _clock;

  bool get _dept => widget.deptId != null;
  DateTime get _nowUtc => widget.now ?? DateTime.now().toUtc();
  DateTime get _nowWall => AppTime.toZone(_nowUtc);

  String? get _role {
    if (widget.role != null) return widget.role;
    try {
      return context.read<MyAuthProvider>().currentUser?.role;
    } catch (_) {
      return null;
    }
  }

  String get _scope {
    int? uid;
    try {
      uid = context.read<MyAuthProvider>().currentUser?.id;
    } catch (_) {}
    final where = _dept ? 'dept:${widget.deptId}' : (widget.orgId != null ? 'org:${widget.orgId}' : 'me');
    return 'u${uid ?? 0}:$where';
  }

  /// Weekly appointments of personal courses: the student's / teacher's own list, only on the overall calendar.
  String? get _weeklyPath {
    if (_dept || widget.orgId != null) return null;
    return switch (_role) {
      'teacher' => '/api/v1/teacher/schedules',
      'student' => '/api/v1/student/schedules',
      _ => null,
    };
  }

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    if (widget.initialView != CalView.agenda) _gridView = widget.initialView;
    WidgetsBinding.instance.addObserver(this);
    _store.bind();
    _store.changes.addListener(_onStoreChanged);
    if (widget.liveKeys == null) MeHomeService.instance.addListener(_onLiveRooms);
    if (widget.now == null) {
      LiveEventsClient.instance.bind();
      _clock = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    _restoreFilters();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.initialView == null) await _restoreView();
      if (!mounted) return;
      _view ??= MediaQuery.sizeOf(context).width >= calWideBreakpoint ? CalView.week : CalView.agenda;
      await _load();
      if (widget.openMeetingId != null && mounted) unawaited(_openMeeting(widget.openMeetingId!));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.changes.removeListener(_onStoreChanged);
    _store.release();
    if (widget.liveKeys == null) MeHomeService.instance.removeListener(_onLiveRooms);
    if (widget.now == null) LiveEventsClient.instance.release();
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && (_chunk == null || !_store.fresh(_chunk!))) _load();
  }

  void _onStoreChanged() {
    if (mounted) _load();
  }

  void _onLiveRooms() {
    if (mounted) setState(() {});
  }

  Set<String> get _liveKeys {
    if (widget.liveKeys != null) return widget.liveKeys!;
    return {
      for (final r in MeHomeService.instance.liveNow) ...[
        if (r.isMeeting) calLiveKeyMeeting(r.id) else calLiveKeySession(r.id),
        if (!r.isMeeting && r.courseId != null) calLiveKeyCourse(r.courseId!),
      ],
    };
  }

  // ── filters (device) ─────────────────────────────────────────────────────
  Future<void> _restoreFilters() async {
    try {
      final p = await SharedPreferences.getInstance();
      final f = CalFilters.decode(p.getString(calFiltersPrefKey));
      if (mounted && f != _filters) setState(() => _filters = f);
    } catch (_) {/* no storage (tests, private window): everything shows */}
  }

  void _setFilters(CalFilters f) {
    setState(() => _filters = f);
    () async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(calFiltersPrefKey, f.encode());
      } catch (_) {}
    }();
  }

  // ── the tab (device) ─────────────────────────────────────────────────────
  Future<void> _restoreView() async {
    try {
      final p = await SharedPreferences.getInstance();
      final (view, grid) = calViewDecode(p.getString(calViewPrefKey));
      if (mounted && view != null) {
        setState(() {
          _view = view;
          _gridView = grid ?? (view == CalView.agenda ? null : view);
        });
      }
    } catch (_) {/* no storage: the default for the width */}
  }

  void _saveView() {
    final v = _view;
    if (v == null) return;
    () async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(calViewPrefKey, calViewEncode(v, _gridView));
      } catch (_) {}
    }();
  }

  /// Flips between the two tabs; the grid keeps the date and the view it was on.
  void _setTab(int index, {required bool wide}) {
    if (index == 0 && _view != CalView.agenda) {
      _pickerOpen = false;
      _go(CalView.agenda, _anchor);
    } else if (index == 1 && _view == CalView.agenda) {
      _go(_gridView ?? (wide ? CalView.week : CalView.month), _anchor);
    }
  }

  /// "Past and ended": fetches the days before today the first time it opens.
  void _togglePast() {
    final open = !_showPast;
    setState(() {
      _showPast = open;
      if (open && _pastDays == 0) _pastDays = calPastStep;
    });
    if (open) _load();
  }

  // ── loading ──────────────────────────────────────────────────────────────
  /// The list starts today (and reaches back once "Past and ended" was opened); the grids follow their date.
  (DateTime, DateTime) get _range {
    final v = _view ?? CalView.week;
    if (v != CalView.agenda) return calFetchRange(v, _anchor, agendaDays: _agendaDays, weekFrom: _weekFrom);
    final today = calDay(_nowWall);
    final (s, e) = calFetchRange(CalView.agenda, today, agendaDays: _agendaDays);
    return (_pastDays == 0 ? s : AppTime.fromZone(DateTime(today.year, today.month, today.day - _pastDays)), e);
  }

  /// The days [v] shows now (the week is the rolling one).
  List<DateTime> _daysOf(CalView v) => calVisibleDays(v, _anchor, weekFrom: _weekFrom);

  Future<void> _load({bool force = false}) async {
    final (s, e) = _range;
    final n = ++_req;
    final scope = _scope;
    final hit = _store.cached(scope, s.toUtc(), e.toUtc());
    final path = _weeklyPath;
    if (path != null) {
      final w = _store.weeklyCached(path);
      if (w != null) _weekly = w;
      unawaited(_store.weekly(path, force: force, get: widget.weeklyGet).then((w) {
        if (mounted && n == _req) setState(() => _weekly = w);
      }));
    }
    if (hit != null) {
      setState(() {
        _chunk = hit;
        _error = null;
      });
      if (!force && _store.fresh(hit)) return;
    }
    setState(() {
      _loading = true;
      if (hit == null) _error = null;
    });
    try {
      final c = await _store.fetch(widget.api, scope: scope, start: s, end: e, orgId: widget.orgId, deptId: widget.deptId);
      if (!mounted || n != _req) return;
      setState(() {
        _chunk = c;
        _loading = false;
        _error = null;
      });
    } catch (err) {
      if (!mounted || n != _req) return;
      setState(() {
        _error = calErrorText(err);
        _loading = false;
      });
    }
  }

  Future<void> _refresh() => _load(force: true);

  /// Shows [anchor] in [v]. [page]: the week's arrows — the columns move by exactly 7 days; [reset]: Today — the
  /// focused day goes back to the second column even when it is already on screen.
  void _go(CalView v, DateTime anchor, {int dir = 0, bool page = false, bool reset = false}) {
    final changed = v != _view;
    setState(() {
      if (changed) _agendaDays = calAgendaDays;
      if (v != CalView.agenda) _gridView = v;
      _view = v;
      _anchor = calDay(anchor);
      _weekFrom = page
          ? DateTime(_weekFrom.year, _weekFrom.month, _weekFrom.day + 7 * dir)
          : calWeekFrom(_anchor, current: reset ? null : _weekFrom);
      _pickerMonth = DateTime(_anchor.year, _anchor.month);
      _slide = dir;
    });
    if (changed) _saveView();
    _load();
  }

  void _shift(int dir) => _go(_view!, calShift(_view!, _anchor, dir), dir: dir, page: _view == CalView.week);

  void _today() => _go(_view ?? CalView.agenda, _nowWall, reset: true);

  /// The page shows today the way it opens (today focused, and in the week as the second column).
  bool get _atToday {
    final today = calDay(_nowWall);
    return _anchor == today && (_view != CalView.week || _weekFrom == calWeekFrom(today));
  }

  // ── data for the views ───────────────────────────────────────────────────
  List<CalEvent> get _all {
    final c = _chunk;
    final events = c?.events ?? const <CalEvent>[];
    if (_weekly.isEmpty || c == null) return events;
    final s = AppTime.toZone(c.start), e = AppTime.toZone(c.end);
    return [...events, ...calWeeklyEvents(_weekly, from: s, to: e, existing: events, toUtc: AppTime.fromZone)]
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  List<CalPause> get _pauses => _chunk?.pauses ?? const [];

  List<Color> _dotsOf(List<CalEvent> shown, DateTime day) {
    final c = context.colors;
    final cats = <CalCat>{for (final e in calEventsOnDay(shown, day)) if (!e.cancelled) calCatOf(e)};
    return [for (final k in CalCat.values) if (cats.contains(k)) calCatColor(c, k)];
  }

  // ── actions ──────────────────────────────────────────────────────────────
  Future<void> _openMeeting(int id, {CalEvent? event}) async {
    final series = event?.seriesId;
    if (await showMeetingSheet(context,
        api: widget.api, meetingId: id, seriesId: series, occurrenceDate: series == null ? null : seriesDateOf(event!))) {
      _store.invalidate();
      unawaited(_refresh());
    }
  }

  /// A date of a repeating meeting with no meeting row yet (D-1572).
  Future<void> _openOccurrence(CalEvent e) async {
    if (await showSeriesOccurrenceSheet(context, api: widget.api, event: e)) {
      _store.invalidate();
      unawaited(_refresh());
    }
  }

  bool get _teacher => _role == 'teacher';

  void _openCourse(CalEvent e) {
    if (e.courseId == null) return;
    if (_teacher && (e.source == 'course_session' || e.source == 'course_weekly')) {
      openTeacherCourseSessions(context, e.courseId!);
    } else if (e.source == 'course_session' || e.source == 'course_weekly') {
      unawaited(AppNavigator.openCourse(e.courseId!));
    } else {
      unawaited(Navigator.of(context).pushNamed('/course-profile', arguments: e.courseId));
    }
  }

  Future<void> _tap(CalEvent e) async {
    if (e.meetingId != null) return _openMeeting(e.meetingId!, event: e);
    if (e.recurring) return _openOccurrence(e);
    final now = _nowUtc;
    final keys = _liveKeys;
    await showAppSheet<void>(
      context,
      (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        // the sheet follows my answer at once
        final cur = _all.firstWhere((x) => x.id == e.id, orElse: () => e);
        return CalEventSheet(
          event: cur,
          nowUtc: now,
          live: calIsLive(cur, now, liveKeys: keys),
          joinable: calJoinable(cur, now, liveKeys: keys),
          onJoin: () {
            Navigator.pop(ctx);
            _join(cur);
          },
          onCourseDetails: cur.courseId == null
              ? null
              : () {
                  Navigator.pop(ctx);
                  EntityNavigator.open(context, EntityRef(EntityKind.course, cur.courseId!));
                },
          onOpenCourse: cur.courseId == null
              ? null
              : () {
                  Navigator.pop(ctx);
                  _openCourse(cur);
                },
          onOpenExams: cur.source == 'exam'
              ? () {
                  Navigator.pop(ctx);
                  openMyExams(context, orgId: cur.orgId);
                }
              : null,
          onOpenTimetable: (cur.source == 'timetable' || cur.source == 'extra') && cur.orgId != null
              ? () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgTimetableScreen(orgId: cur.orgId)));
                }
              : null,
          onOpenLink: (cur.change?.onlineUrl ?? '').isEmpty ? null : () => _launch(cur.change!.onlineUrl!),
          onAnswer: (d) async {
            await _answerChange(cur, d);
            setSheet(() {});
          },
          onUndo: cur.change != null && cur.change!.canEdit && cur.orgId != null
              ? () async {
                  Navigator.pop(ctx);
                  if (await undoChange(cur.orgId!, cur.change!.id)) {
                    _store.invalidate();
                    unawaited(_refresh());
                  }
                }
              : null,
        );
      }),
    );
  }

  Future<void> _launch(String url) async {
    await openExternalLink(url, failText: t('تعذر فتح الرابط', 'Could not open the link'));
  }

  Future<void> _join(CalEvent e) async {
    if (e.meetingId == null && e.recurring) return joinSeriesOccurrence(context, widget.api, e);
    if (e.meetingId != null) {
      await openMeetingRoom(
        context,
        api: widget.api,
        meeting: {
          'id': e.meetingId,
          'title': e.title,
          'mode': 'online',
          'is_owner': e.isOwner,
          'starts_at': e.start.toIso8601String(),
        },
        canRecord: e.isOwner,
      );
      return;
    }
    if (e.sessionId != null && e.courseId != null) {
      await openCourseLiveRoom(context, sessionId: e.sessionId!, courseId: e.courseId!, sessionName: e.title);
      return;
    }
    if (e.source == 'course_weekly') {
      final room = MeHomeService.instance.liveNow.where((r) => !r.isMeeting && r.courseId == e.courseId).firstOrNull;
      if (room != null) return joinHomeLiveRoom(context, room);
      return _openCourse(e);
    }
    final url = e.change?.onlineUrl;
    if (url != null && url.isNotEmpty) await _launch(url);
  }

  Future<void> _rsvp(CalEvent e, String status) async {
    final id = e.meetingId;
    if (id == null) return;
    _store.patch((x) => x.id == e.id ? x.copyWith(myStatus: status) : x);
    setState(() => _chunk = _store.cached(_scope, _range.$1.toUtc(), _range.$2.toUtc()) ?? _chunk);
    try {
      await widget.api.respond(id, {'status': status});
      showAppNotice(status == 'accepted' ? t('قبلت الدعوة', 'Invitation accepted') : t('اعتذرت عن الاجتماع', 'You declined'));
    } catch (err) {
      showAppNotice(calErrorText(err), error: true);
    }
    _store.invalidate();
    unawaited(_refresh());
  }

  Future<void> _answerChange(CalEvent e, String decision) async {
    final ch = e.change;
    if (ch == null) return;
    if (!await respondToChange(ch.id, decision)) return;
    _store.patch((x) => x.id == e.id && x.change != null ? x.copyWith(change: x.change!.answered(decision)) : x);
    if (mounted) setState(() => _chunk = _store.cached(_scope, _range.$1.toUtc(), _range.$2.toUtc()) ?? _chunk);
  }

  Future<void> _add([DateTime? wall]) async {
    var start = wall;
    if (start == null) {
      final n = _nowWall;
      // today: the next sensible slot (never midnight, D-1661); another day: its 09:00
      start = _anchor == calDay(n) ? calNextSensibleSlot(n) : DateTime(_anchor.year, _anchor.month, _anchor.day, 9);
    }
    final r = await showMeetingForm(context, api: widget.api, start: start, orgId: widget.orgId, deptId: widget.deptId);
    if (r != null) {
      showAppNotice(r['visibility'] == 'private' ? t('أُضيف إلى جدولك', 'Added to your schedule') : t('أُرسلت الدعوات', 'Invitations sent'));
      _store.invalidate();
      unawaited(_refresh());
    }
  }

  Future<void> _move(CalEvent e, DateTime wallStart) async {
    final s = AppTime.fromZone(wallStart).toUtc();
    final en = s.add(e.duration);
    if (s == e.start || (e.meetingId == null && !e.recurring)) return;
    final clash = calConflicts(_filters.apply(_all), e, s, en);
    if (clash.isNotEmpty) {
      final ok = await appConfirm(context,
          message: '${t('يتعارض مع', 'This overlaps')}: ${clash.take(3).map((x) => x.title).join('، ')}'
              '${clash.length > 3 ? ' +${clash.length - 3}' : ''}',
          confirmLabel: t('انقل رغم ذلك', 'Move anyway'));
      if (!ok || !mounted) return;
    }
    if (e.recurring) {
      // a date of a repeating meeting: this one only, or the series' clock from today on (D-1573)
      if (await seriesMove(context, widget.api, seriesId: e.seriesId!, date: seriesDateOf(e), startUtc: s, endUtc: en)) {
        _store.invalidate();
        if (mounted) unawaited(_refresh());
      }
      return;
    }
    _store.patch((x) => x.id == e.id ? x.moved(s, en) : x);
    setState(() => _chunk = _store.cached(_scope, _range.$1.toUtc(), _range.$2.toUtc()) ?? _chunk);
    Future<void> send(bool force) => widget.api.update(e.meetingId!, {
          'starts_at': s.toIso8601String(),
          'ends_at': en.toIso8601String(),
          'force': force,
        });
    try {
      await send(false);
      showAppNotice(t('نُقل الاجتماع وأُبلغ المدعوون', 'Meeting moved — invitees notified'));
    } catch (err) {
      final busy = calBusyOf(err);
      if (busy.isNotEmpty && mounted) {
        final go = await appConfirm(context,
            message: '${t('مشغولون في هذا الوقت', 'Busy at this time')}: ${busy.map((b) => asMap(b['user'])['name']).join('، ')}',
            confirmLabel: t('انقل رغم ذلك', 'Move anyway'));
        if (go) {
          try {
            await send(true);
          } catch (e2) {
            showAppNotice(calErrorText(e2), error: true);
          }
        }
      } else {
        showAppNotice(calErrorText(err), error: true);
      }
    }
    _store.invalidate();
    if (mounted) unawaited(_refresh());
  }

  Future<void> _export() async {
    final (s, e) = _range;
    final events = calSlice(_filters.apply(_all), s.toUtc(), e.toUtc());
    if (events.where((x) => !x.cancelled).isEmpty) {
      showAppNotice(t('لا مواعيد في هذه الفترة', 'Nothing to export in this range'), error: true);
      return;
    }
    final name = '${t('جدولي', 'My schedule')} ${calTitleFor(_view ?? CalView.week, _anchor, weekFrom: _weekFrom)}';
    try {
      await FileSaver.instance.saveFile(
        name: name.replaceAll(RegExp(r'[\\/:*?"<>|–]'), '_'),
        bytes: Uint8List.fromList(utf8.encode(calIcs(events, name: name))),
        fileExtension: 'ics',
        mimeType: MimeType.text,
      );
      showAppNotice(t('حُفظ ملف التقويم — افتحه في تقويم جهازك', 'Calendar file saved — open it in your device calendar'));
    } catch (_) {
      showAppNotice(t('تعذر إنشاء الملف', 'Could not create the file'), error: true);
    }
  }

  CalTileActions get _actions => CalTileActions(onTap: _tap, onJoin: _join, onRsvp: _rsvp, onAnswerChange: _answerChange);

  // ═══════════════════════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= calWideBreakpoint;
      final view = _view ?? (wide ? CalView.week : CalView.agenda);
      final all = _all;
      final shown = _filters.apply(all);
      final main = _main(context, view, all, shown, wide: wide, width: box.maxWidth);
      if (!wide) {
        return BasePage(
          floatingActionButton: _dept ? null : _fab(context),
          child: SafeArea(
            bottom: false,
            child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: main),
          ),
        );
      }
      return BasePage(
        child: SafeArea(
          bottom: false,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 300, child: _sidebar(context, view, all, shown)),
            VerticalDivider(width: 1, color: context.colors.divider),
            Expanded(child: main),
          ]),
        ),
      );
    });
  }

  String get _pageTitle =>
      widget.title ?? (_dept ? t('تقويم الإدارة', 'Department calendar') : t('جدولي', 'My schedule'));

  /// The phone's ONE floating button (H10): a round "+" for a new meeting; "Meet now" is the header's video icon.
  /// Every list and time grid ends with [_fabRoomOf] of free space, so at the end it never sits on a row; while the
  /// person scrolls down through rows it slides away ([_onScroll]) and comes back on a scroll up or at the end.
  Widget? _fab(BuildContext context) {
    final c = context.colors;
    final hidden = _fabHidden;
    final dur = MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 200);
    return AnimatedSlide(
      offset: hidden ? const Offset(0, 1.6) : Offset.zero,
      duration: dur,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: dur,
        child: IgnorePointer(
          ignoring: hidden,
          child: ExcludeFocus(
            excluding: hidden,
            child: FloatingActionButton(
              key: const ValueKey('cal.new_meeting'),
              heroTag: 'cal_add',
              tooltip: t('اجتماع جديد', 'New meeting'),
              onPressed: () => _add(),
              backgroundColor: c.primary,
              foregroundColor: c.onHero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.block - AppSpace.xxs)),
              child: const Icon(Icons.add_rounded, size: AppIconSize.lg + 4),
            ),
          ),
        ),
      ),
    );
  }

  /// The floating button is out of the way (the person is scrolling down through rows).
  bool _fabHidden = false;

  /// A user's scroll down a list / grid tucks the floating button away; a scroll up, or reaching the end (where
  /// [_fabRoomOf] keeps the last row clear of it), brings it back. Horizontal scrolls (filter chips) are ignored.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || _dept) return false;
    var hide = _fabHidden;
    if (n is UserScrollNotification) {
      if (n.direction == ScrollDirection.reverse && n.metrics.extentAfter > 0) hide = true;
      if (n.direction == ScrollDirection.forward) hide = false;
    } else if (n is ScrollEndNotification && n.metrics.extentAfter <= 0) {
      hide = false;
    }
    if (hide != _fabHidden) setState(() => _fabHidden = hide);
    return false;
  }

  /// Free space under a phone list / grid for the floating button: its 56 + the 16 margin + 24 air, plus the
  /// bottom safe area the button sits above.
  static const double _fabRoom = 96;
  double _fabRoomOf(BuildContext context) => _fabRoom + MediaQuery.paddingOf(context).bottom;

  // ── desktop sidebar ──────────────────────────────────────────────────────
  Widget _sidebar(BuildContext context, CalView view, List<CalEvent> all, List<CalEvent> shown) {
    final c = context.colors;
    final now = _nowUtc;
    final keys = _liveKeys;
    final next = shown.where((e) => !e.cancelled && !e.declined && !calIsOver(e, now, liveKeys: keys)).toList()..sort((a, b) => a.start.compareTo(b.start));
    final invites = [for (final e in all) if (e.isMeeting && e.myStatus == 'pending' && !calIsOver(e, now)) e];
    final days = _daysOf(view);
    final list = view == CalView.agenda;
    return ColoredBox(
      color: c.cardBg,
      // a short column, built whole (a lazy list would leave the filters unbuilt below the fold)
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.lg - 6, AppSpace.md, AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!widget.asTab) ...[
            Row(children: [
              if (Navigator.of(context).canPop()) ...[
                const AppBackButton(),
                const SizedBox(width: AppSpace.xxs),
              ],
              Expanded(child: Semantics(header: true, child: Text(_pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)))),
              const HelpInfoButton(pageId: 'calendar'),
            ]),
            const SizedBox(height: AppSpace.xxs / 2),
          ],
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs / 2, bottom: AppSpace.md),
            child: Text(AppTime.date(now, pattern: 'EEEE d MMMM'), style: AppType.meta(context)),
          ),
          AppButton.primary(
            key: const ValueKey('cal.new_meeting'),
            label: t('اجتماع جديد', 'New meeting'),
            icon: Icons.add_rounded,
            expand: true,
            onPressed: () => _add(),
          ),
          if (!_dept) ...[
            const SizedBox(height: AppSpace.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: QuickMeetingButton(orgId: widget.orgId, api: widget.api, onDone: _refresh),
            ),
          ],
          const SizedBox(height: AppSpace.lg - 6),
          CalMonthPicker(
            month: _pickerMonth,
            selected: list ? calDay(_nowWall) : _anchor,
            today: calDay(_nowWall),
            rangeStart: view == CalView.week ? days.first : null,
            rangeEnd: view == CalView.week ? days.last : null,
            dotsOf: (d) => _dotsOf(shown, d),
            pausedOf: (d) => _pauses.any((p) => p.covers(d)),
            onPick: (d) => _go(list || view == CalView.month ? CalView.day : view, d),
            onMonth: (dir) => setState(() => _pickerMonth = DateTime(_pickerMonth.year, _pickerMonth.month + dir)),
          ),
          const SizedBox(height: AppSpace.lg - 6),
          if (next.isNotEmpty) ...[
            CalUpNextCard(event: next.first, nowUtc: now, live: calIsLive(next.first, now, liveKeys: keys), onTap: () => _tap(next.first)),
            const SizedBox(height: AppSpace.md - 2),
          ],
          if (invites.isNotEmpty) ...[
            CalInvitesCard(invites: invites, actions: _actions),
            const SizedBox(height: AppSpace.md - 2),
          ],
          if (!_dept)
            CalFilterPanel(
              counts: _countsOf(view, all),
              filters: _filters,
              onCat: (k) => _setFilters(_filters.toggleCat(k)),
              orgs: calOrgsOf(all),
              onOrg: (id) => _setFilters(_filters.toggleOrg(id)),
            ),
        ]),
      ),
    );
  }

  /// The filters' counts: what the list shows on the Scheduled meetings tab, the visible range on the Calendar tab.
  Map<CalCat, int> _countsOf(CalView view, List<CalEvent> all) {
    if (view != CalView.agenda) return calCountsByCat(calSlice(all, _range.$1.toUtc(), _range.$2.toUtc()));
    final now = _nowUtc, keys = _liveKeys;
    return calCountsByCat(all.where((e) => calIsOver(e, now, liveKeys: keys) == _showPast));
  }

  Widget _tabs(BuildContext context, CalView view, {required bool wide, bool expand = false}) => CalPageTabs(
        index: view == CalView.agenda ? 0 : 1,
        invites: _chunk?.pending ?? 0,
        expand: expand,
        onChanged: (i) => _setTab(i, wide: wide),
      );

  // ── header (phone / tablet) ──────────────────────────────────────────────
  Widget _header(BuildContext context, CalView view) {
    final c = context.colors;
    final canPop = !widget.asTab && Navigator.of(context).canPop();
    final monthTitle = calTitleFor(view == CalView.day || view == CalView.week ? CalView.month : view, _anchor, weekFrom: _weekFrom);
    final grid = view != CalView.agenda;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(canPop ? AppSpace.xxs : AppSpace.md + AppSpace.xxs / 2, AppSpace.xs, AppSpace.xs, AppSpace.xxs),
      child: Row(children: [
        if (canPop) const AppBackButton(),
        Expanded(
          // the list's hero carries the date; on the grid the month is the title, and opens the mini month
          child: !grid
              ? Semantics(header: true, child: Text(_pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)))
              : Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Semantics(
                    button: true,
                    label: t('اختر يوماً', 'Pick a day'),
                    child: InkWell(
                      key: const ValueKey('cal.month_toggle'),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      onTap: () => setState(() {
                        _pickerOpen = !_pickerOpen;
                        _pickerMonth = DateTime(_anchor.year, _anchor.month);
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                            child: Text(monthTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
                          ),
                          AnimatedRotation(
                            turns: _pickerOpen ? 0.5 : 0,
                            duration: AppMotion.of(context).base,
                            child: Icon(Icons.expand_more_rounded, size: AppIconSize.lg - 2, color: appInk(context, c.primary)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
        ),
        if (!_dept) QuickMeetingButton(icon: true, orgId: widget.orgId, api: widget.api, onDone: _refresh),
        const HelpInfoButton(pageId: 'calendar'),
        if (grid) _TodayButton(onTap: _today, isToday: _atToday),
        _MoreMenu(onRefresh: _refresh, onExport: _export),
      ]),
    );
  }

  Widget _toolbar(BuildContext context, CalView view, {required bool wide}) {
    final c = context.colors;
    final title = calTitleFor(view, _anchor, weekFrom: _weekFrom);
    final canPop = !widget.asTab && Navigator.of(context).canPop();
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.sm, AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.divider))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (canPop && !wide) ...[
            const AppBackButton(),
            const SizedBox(width: AppSpace.xxs),
          ],
          // the track hugs its two tabs instead of stretching across the toolbar
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: _tabs(context, view, wide: wide, expand: true)),
            ),
          ),
          if (_loading && _chunk != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm - 2),
              child: SizedBox(width: AppSpace.xxxl - 4, child: LinearProgressIndicator(minHeight: AppSpace.xxs - 1, borderRadius: BorderRadius.circular(AppRadius.pill), color: c.primary, backgroundColor: c.inputBg)),
            ),
          const MeetingLinksIcon(),
          _MoreMenu(onRefresh: _refresh, onExport: _export),
        ]),
        if (view != CalView.agenda) ...[
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            _TodayButton(onTap: _today, isToday: _atToday, outlined: true),
            const SizedBox(width: AppSpace.xs - 2),
            IconButton(tooltip: t('السابق', 'Previous'), onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
            IconButton(tooltip: t('التالي', 'Next'), onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
            const SizedBox(width: AppSpace.xs - 2),
            Expanded(
              child: Semantics(header: true, child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context))),
            ),
            CalViewSwitch(view: view, views: calGridViews, onView: (v) => _go(v, _anchor)),
          ]),
        ],
      ]),
    );
  }

  // ── main column ──────────────────────────────────────────────────────────
  Widget _main(BuildContext context, CalView view, List<CalEvent> all, List<CalEvent> shown, {required bool wide, required double width}) {
    final c = context.colors;
    final tablet = !wide && width >= 700;
    final pending = _chunk?.pending ?? 0;
    final firstPending = all.where((e) => e.isMeeting && e.myStatus == 'pending' && !calIsOver(e, _nowUtc)).firstOrNull;
    final grid = view != CalView.agenda;
    final children = <Widget>[
      if (wide || tablet) _toolbar(context, view, wide: wide) else ...[
        _header(context, view),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
          child: _tabs(context, view, wide: false, expand: true),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_pickerOpen || !grid
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xxs, AppSpace.sm, AppSpace.xs),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(AppSpace.xs - 2, AppSpace.xxs, AppSpace.xs - 2, AppSpace.xs),
                    decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider, width: AppBorder.hairline)),
                    child: CalMonthPicker(
                      month: _pickerMonth,
                      selected: _anchor,
                      today: calDay(_nowWall),
                      dotsOf: (d) => _dotsOf(shown, d),
                      pausedOf: (d) => _pauses.any((p) => p.covers(d)),
                      onPick: (d) {
                        _pickerOpen = false;
                        _go(view, d);
                      },
                      onMonth: (dir) => setState(() => _pickerMonth = DateTime(_pickerMonth.year, _pickerMonth.month + dir)),
                    ),
                  ),
                ),
        ),
        if (grid)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xxs),
            child: CalViewSwitch(view: view, views: calGridViews, onView: (v) => _go(v, _anchor), expand: true),
          ),
      ],
      // on the list the chips ride with the rows ([_agenda]), so the first event stays high on a phone
      if (!wide && !_dept && grid)
        Padding(
          padding: EdgeInsets.only(top: tablet ? AppSpace.xs : AppSpace.xxs / 2, bottom: AppSpace.xxs),
          child: CalFilterChips(
            counts: _countsOf(view, all),
            filters: _filters,
            onCat: (k) => _setFilters(_filters.toggleCat(k)),
            orgs: calOrgsOf(all),
            onOrg: (id) => _setFilters(_filters.toggleOrg(id)),
          ),
        ),
      if (!wide && _loading && _chunk != null)
        LinearProgressIndicator(minHeight: AppSpace.xxs / 2, color: c.primary, backgroundColor: c.background)
      else if (!wide)
        const SizedBox(height: AppSpace.xxs / 2),
      if (_error != null && _chunk != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs - 2, AppSpace.md, AppSpace.xs - 2),
          child: AppBanner(
            icon: Icons.cloud_off_rounded,
            text: _error!,
            color: c.danger,
            action: IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
          ),
        ),
      if (pending > 0 && !wide && firstPending != null && view != CalView.agenda)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs - 2, AppSpace.md, AppSpace.xs - 2),
          child: AppBanner(
            icon: Icons.mark_email_unread_rounded,
            color: c.primary,
            text: t('لديك $pending ${pending == 1 ? 'دعوة' : 'دعوات'} بانتظار ردك', 'You have $pending invitation${pending == 1 ? '' : 's'} awaiting your answer'),
            action: IconButton(tooltip: t('عرض', 'Open'), onPressed: () => _openMeeting(firstPending.meetingId!), icon: const Icon(Icons.open_in_new_rounded)),
          ),
        ),
      Expanded(child: _content(context, view, all, shown, wide: wide)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _content(BuildContext context, CalView view, List<CalEvent> all, List<CalEvent> shown, {required bool wide}) {
    if (_chunk == null) {
      if (_error != null) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: AppEmpty(
              icon: Icons.cloud_off_rounded,
              title: t('تعذر تحميل جدولك', 'Could not load your schedule'),
              message: _error,
              actionLabel: t('أعد المحاولة', 'Try again'),
              onAction: _refresh,
            ),
          ),
        );
      }
      return CalScheduleSkeleton(view: view);
    }
    final child = switch (view) {
      CalView.agenda => _agenda(context, all, shown, wide: wide),
      CalView.day => _day(context, shown, wide: wide),
      CalView.week => _week(context, shown, wide: wide),
      CalView.month => _month(context, shown, wide: wide),
    };
    final keyed = KeyedSubtree(key: ValueKey(view == CalView.agenda ? 'list|$_showPast' : '${view.name}|$_anchor'), child: child);
    final animated = AnimatedSwitcher(
      duration: AppMotion.of(context).base,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      transitionBuilder: (w, anim) {
        final dx = _slide == 0 ? 0.0 : 0.06 * _slide;
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: Tween(begin: Offset(dx, _slide == 0 ? 0.015 : 0), end: Offset.zero).animate(anim), child: w),
        );
      },
      layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?cur]),
      child: keyed,
    );
    if (wide || view == CalView.agenda) return animated;
    // phones: a horizontal swipe moves the range (the grids scroll vertically, the swipe stays free)
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 300) return;
        final forward = rtl ? v > 0 : v < 0;
        _shift(forward ? 1 : -1);
      },
      child: animated,
    );
  }

  /// The Scheduled meetings tab: what is coming, or (the toggle) what has finished.
  Widget _agenda(BuildContext context, List<CalEvent> all, List<CalEvent> shown, {required bool wide}) {
    final now = _nowUtc, wall = _nowWall, keys = _liveKeys;
    final today = calDay(wall);
    final showOrg = calOrgsOf(shown).where((o) => o.id != 0).length > 1;
    final coming = calComing(shown, now, liveKeys: keys)..sort((a, b) => a.start.compareTo(b.start));
    final live = [for (final e in coming) if (calIsLive(e, now, liveKeys: keys)) e];
    final ahead = [for (final e in coming) if (!live.contains(e)) e];
    final past = calPast(shown, nowUtc: now, nowWall: wall, liveKeys: keys);
    final chips = wide || _dept
        ? null
        : CalBleed(
            gutter: AppSpace.md,
            child: CalFilterChips(
              counts: _countsOf(CalView.agenda, all),
              filters: _filters,
              onCat: (k) => _setFilters(_filters.toggleCat(k)),
              orgs: calOrgsOf(all),
              onOrg: (id) => _setFilters(_filters.toggleOrg(id)),
            ),
          );
    Widget more(String key, IconData icon, String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Center(
            child: TextButton.icon(key: ValueKey(key), onPressed: onTap, icon: Icon(icon), label: Text(label)),
          ),
        );

    final Widget list;
    if (_showPast) {
      list = CalAgendaList(
        days: past,
        nowUtc: now,
        liveKeys: keys,
        actions: _actions,
        showOrg: showOrg,
        history: true,
        padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, wide ? AppSpace.xl : _fabRoomOf(context)),
        header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ?chips,
          CalListBar(
            title: t('السابقة والمنتهية', 'Past and ended'),
            actionKey: 'cal.past.toggle',
            actionIcon: Icons.upcoming_rounded,
            actionLabel: t('القادمة', 'Coming up'),
            onAction: _togglePast,
          ),
        ]),
        emptyRange: _loading ? const CalScheduleSkeleton(view: CalView.agenda, bare: true) : _NothingAhead(past: true, filtered: _filters.any, onClear: () => _setFilters(const CalFilters())),
        footer: _pastDays < calPastMax
            ? more('cal.past.more', Icons.history_rounded, t('عرض أسبوعين سابقين', 'Show two earlier weeks'), () {
                setState(() => _pastDays += calPastStep);
                _load();
              })
            : null,
      );
    } else {
      final nothing = coming.isEmpty;
      final todayLeft = coming.where((e) => calDay(e.wallStart) == today && !e.cancelled).length;
      final todayAll = calEventsOnDay(shown, today).where((e) => !e.cancelled).length;
      final inWeek = wall.add(const Duration(days: 7));
      final next = ahead.where((e) => !e.cancelled && !e.declined).firstOrNull;
      list = CalAgendaList(
        days: nothing ? const [] : calAgenda(ahead, from: today, days: _agendaDays, nowWall: wall, pauses: _pauses),
        nowUtc: now,
        liveKeys: keys,
        actions: _actions,
        showOrg: showOrg,
        todayDone: todayLeft == 0 && todayAll > 0,
        padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, wide ? AppSpace.xl : _fabRoomOf(context)),
        header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppReveal(index: 0, group: 'cal.agenda', rise: 8, child: CalTodayHero(
            nowUtc: now,
            left: todayLeft,
            week: ahead.where((e) => !e.cancelled && e.wallStart.isBefore(inWeek)).length + live.length,
            invites: _chunk?.pending ?? 0,
            next: next,
            nextJoinable: next != null && calJoinable(next, now, liveKeys: keys),
            onTapNext: next == null ? null : () => _tap(next),
            onJoinNext: next == null ? null : () => _join(next),
          )),
          const SizedBox(height: AppSpace.md),
          ?chips,
          CalListBar(
            title: t('القادمة', 'Coming up'),
            actionKey: 'cal.past.toggle',
            actionIcon: Icons.history_rounded,
            actionLabel: t('السابقة والمنتهية', 'Past and ended'),
            onAction: _togglePast,
          ),
          for (final e in live) ...[
            CalLiveNowCard(event: e, nowUtc: now, onTap: () => _tap(e), onJoin: () => _join(e)),
            const SizedBox(height: AppSpace.sm),
          ],
        ]),
        emptyRange: live.isNotEmpty ? null : _NothingAhead(filtered: _filters.any, onClear: () => _setFilters(const CalFilters()), onNew: _dept ? null : () => _add()),
        footer: _agendaDays < 56
            ? more('cal.agenda.more', Icons.expand_more_rounded, t('عرض أسبوعين آخرين', 'Show the next two weeks'), () {
                setState(() => _agendaDays += calAgendaDays);
                _load();
              })
            : null,
      );
    }
    final body = AppRefresh(onRefresh: _refresh, child: list);
    if (!wide) return body;
    return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: AppWidth.reading.max), child: body));
  }

  Widget _day(BuildContext context, List<CalEvent> shown, {required bool wide}) {
    final keys = _liveKeys;
    final grid = CalTimeGrid(
      key: ValueKey('day-$_anchor'),
      days: [_anchor],
      events: shown,
      pauses: _pauses,
      showHeader: wide,
      bottomPadding: wide || _dept ? 0 : _fabRoomOf(context),
      now: widget.now == null ? null : _nowWall,
      isLive: (e) => calIsLive(e, _nowUtc, liveKeys: keys),
      onTapEvent: _tap,
      onTapSlot: _add,
      onMove: _move,
    );
    if (wide) return grid;
    final week = _daysOf(CalView.week);
    return Column(children: [
      CalWeekStrip(
        days: week,
        selected: _anchor,
        today: calDay(_nowWall),
        dotsOf: (d) => _dotsOf(shown, d),
        onPick: (d) => _go(CalView.day, d, dir: d.isAfter(_anchor) ? 1 : -1),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md + AppSpace.xxs / 2, AppSpace.xxs / 2, AppSpace.md + AppSpace.xxs / 2, AppSpace.xs - 2),
        child: Row(children: [
          Expanded(
            child: Text(
              '${_dayTitleOf(_anchor)} · ${AppTime.date(AppTime.fromZone(DateTime(_anchor.year, _anchor.month, _anchor.day, 12)), pattern: 'd MMMM')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.section(context),
            ),
          ),
          Text(
            () {
              final n = calEventsOnDay(shown, _anchor).where((e) => !e.cancelled).length;
              return n == 0 ? t('يوم فارغ', 'Free day') : t('$n ${n == 1 ? 'موعد' : 'مواعيد'}', '$n ${n == 1 ? 'event' : 'events'}');
            }(),
            style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textLight),
          ),
        ]),
      ),
      Expanded(child: grid),
    ]);
  }

  String _dayTitleOf(DateTime d) {
    final diff = calDay(d).difference(calDay(_nowWall)).inDays;
    if (diff == 0) return t('اليوم', 'Today');
    if (diff == 1) return t('غداً', 'Tomorrow');
    return AppTime.date(AppTime.fromZone(DateTime(d.year, d.month, d.day, 12)), pattern: 'EEEE');
  }

  Widget _week(BuildContext context, List<CalEvent> shown, {required bool wide}) {
    final keys = _liveKeys;
    final days = _daysOf(CalView.week);
    return CalTimeGrid(
      key: ValueKey('week-${days.first}'),
      days: days,
      events: shown,
      pauses: _pauses,
      bottomPadding: wide || _dept ? 0 : _fabRoomOf(context),
      now: widget.now == null ? null : _nowWall,
      isLive: (e) => calIsLive(e, _nowUtc, liveKeys: keys),
      onTapEvent: _tap,
      onTapSlot: _add,
      onMove: _move,
      onOpenDay: (d) => _go(CalView.day, d),
    );
  }

  Widget _month(BuildContext context, List<CalEvent> shown, {required bool wide}) {
    if (wide) {
      return CalMonthGrid(
        month: _anchor,
        days: calVisibleDays(CalView.month, _anchor),
        events: shown,
        pauses: _pauses,
        now: widget.now == null ? null : _nowWall,
        onTapDay: (d) => _go(CalView.day, d),
        onTapEvent: _tap,
        onMove: _move,
      );
    }
    // phone: the month as dots on top, the picked day's list below (Apple Calendar)
    final sel = _anchor;
    final day = calAgenda(shown, from: sel, days: 1, nowWall: _nowWall, pauses: _pauses).firstOrNull ??
        CalAgendaDay(day: sel, events: const [], today: sel == calDay(_nowWall));
    return AppRefresh(
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xxs, AppSpace.sm, _fabRoomOf(context)),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
            decoration: BoxDecoration(color: context.colors.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: context.colors.divider, width: AppBorder.hairline)),
            child: CalMonthPicker(
              month: DateTime(sel.year, sel.month),
              selected: sel,
              today: calDay(_nowWall),
              roomy: true,
              showHeader: false,
              dotsOf: (d) => _dotsOf(shown, d),
              pausedOf: (d) => _pauses.any((p) => p.covers(d)),
              onPick: (d) {
                if (d.month != sel.month) {
                  _go(CalView.month, d, dir: d.isAfter(sel) ? 1 : -1);
                } else {
                  setState(() => _anchor = d);
                }
              },
              onMonth: (dir) => _shift(dir),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
            child: CalAgendaDayCard(
              day: CalAgendaDay(day: day.day, events: day.events, today: day.today, nowAt: day.nowAt, pauses: [for (final p in _pauses) if (p.covers(sel)) p]),
              nowUtc: _nowUtc,
              liveKeys: _liveKeys,
              actions: _actions,
              showOrg: calOrgsOf(shown).where((o) => o.id != 0).length > 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayButton extends StatelessWidget {
  const _TodayButton({required this.onTap, required this.isToday, this.outlined = false});
  final VoidCallback onTap;
  final bool isToday, outlined;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
      child: InkWell(
        key: const ValueKey('cal.today'),
        borderRadius: AppRadius.controlAll,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs, minWidth: AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md - 2, vertical: AppSpace.xs),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: outlined || isToday ? c.cardBg : calTint(c, c.primary, 0.10),
            borderRadius: AppRadius.controlAll,
            border: Border.all(color: outlined ? Color.lerp(c.divider, c.textDark, 0.2)! : (isToday ? c.divider : c.primary.withValues(alpha: 0.3)), width: AppBorder.hairline),
          ),
          // already on today: the button goes quiet (it would change nothing)
          child: Text(t('اليوم', 'Today'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: isToday ? c.textMedium : (outlined ? c.textDark : appInk(context, c.primary)))),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.onRefresh, required this.onExport});
  final Future<void> Function() onRefresh;
  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<String>(
      key: const ValueKey('cal.more'),
      tooltip: t('المزيد', 'More'),
      icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      onSelected: (v) {
        if (v == 'refresh') onRefresh();
        if (v == 'ics') onExport();
        if (v == 'links') openMeetingLinks(context);
      },
      itemBuilder: (_) => [
        if (!AppConfig.disableList.contains(kMeetingLinksFeatureKey))
          PopupMenuItem(
            key: const ValueKey('cal.more.links'),
            value: 'links',
            child: Row(children: [
              const Icon(Icons.link_rounded, size: 20),
              const SizedBox(width: 10),
              Flexible(child: Text(t('روابط الاجتماعات', 'Meeting links'))),
            ]),
          ),
        PopupMenuItem(
          value: 'refresh',
          child: Row(children: [const Icon(Icons.refresh_rounded, size: 20), const SizedBox(width: 10), Text(t('تحديث', 'Refresh'))]),
        ),
        PopupMenuItem(
          value: 'ics',
          child: Row(children: [
            const Icon(Icons.ios_share_rounded, size: 20),
            const SizedBox(width: 10),
            Flexible(child: Text(t('تصدير إلى التقويم (.ics)', 'Export to calendar (.ics)'))),
          ]),
        ),
      ],
    );
  }
}

class _NothingAhead extends StatelessWidget {
  const _NothingAhead({required this.filtered, required this.onClear, this.past = false, this.onNew});
  final bool filtered, past;
  final VoidCallback onClear;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
      child: Column(children: [
        Container(
          width: AppSpace.xxxl + AppSpace.lg,
          height: AppSpace.xxxl + AppSpace.lg,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.blockSky),
          child: Icon(past ? Icons.history_rounded : Icons.event_available_rounded, size: AppIconSize.hero, color: c.blockAccentInk(c.accent3, c.blockSky)),
        ),
        const SizedBox(height: AppSpace.md),
        Text(past ? t('لا شيء هنا بعد', 'Nothing here yet') : t('لا شيء قادم', 'Nothing coming up'), textAlign: TextAlign.center, style: AppType.section(context)),
        const SizedBox(height: AppSpace.xxs),
        Text(
          filtered
              ? t('بعض الأنواع مخفية بالمرشّحات', 'Some kinds are hidden by the filters')
              : past
                  ? t('ستجد هنا مواعيدك المنتهية والاجتماعات المغلقة', 'What has finished and meetings that were closed show up here')
                  : t('ستظهر هنا محاضراتك وامتحاناتك واجتماعاتك', 'Your classes, exams and meetings show up here'),
          textAlign: TextAlign.center,
          style: AppType.body(context),
        ),
        if (filtered) ...[
          const SizedBox(height: AppSpace.xs),
          TextButton(onPressed: onClear, child: Text(t('إظهار الكل', 'Show everything'))),
        ] else if (onNew != null) ...[
          const SizedBox(height: AppSpace.md),
          AppButton.primary(label: t('اجتماع جديد', 'New meeting'), icon: Icons.add_rounded, onPressed: onNew),
        ],
      ]),
    );
  }
}
