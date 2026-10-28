// lib/core/home/me_home.dart — ONE call for the signed-in home: GET /api/v1/me/home (Track B.4, D-062).
//
//   MeHome                  the payload, typed: today[] / upcoming[] as CalEvent (the calendar feed's rows),
//                           attention (= GET /me/attention), inbox_preview[] (raw inbox rows, ≤ 5) + inbox_counts,
//                           notifications_unread, org_overview (= GET /org/public/me/overview, null without a
//                           membership), students / members: courses_progress[], teachers: the teacher block
//                           (teaching_today[], pending{…}, teaching_courses, earnings{…}) passed through as
//                           [MeHomeTeacher] — so the teacher home can read the same object.
//     home.nextUp()         today's next (or running) session / exam — the hero
//     home.attentionCount(AttentionTabs.home)            the "To do" count, drawn once
//     home.orgEntry(orgId) · home.todayOf(orgId) · home.inboxPreviewOf(orgId)   the Organization-mode slices
//   MeHomeService.instance  the loader: GET /me/home once per open, cached in memory (instant redraw), refreshed
//                           on resume · pull (refresh()) · the live events `attention_changed` / `*_updated`
//                           (LiveEvents) · back online after a failure. Listen with ListenableBuilder; the live
//                           wiring runs only while something listens.
//     ensure()              load when nothing is cached (or the cache is stale) — the screen's initState
//     refresh()             reload now (pull-to-refresh); in-flight calls are shared
//   Older server (bare 404 / 405 on /me/home) → [MeHomeOutcome.legacy]: the same MeHome is composed from today's
//   separate calls (GET /me/calendar for today + 7 days, /me/attention, /me/inbox), each best-effort, so the
//   screens have ONE code path. Parents get 403 `role_not_supported` → [MeHomeOutcome.unsupported] (no home).
//
// Pure (unit-tested, test/org/me_home_test.dart): MeHome.fromJson, nextUp, orgEntry / todayOf / inboxPreviewOf,
// meHomeOutcomeOf, MeHomeService with an injected fetch (legacy composition).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../features/shared/calendar/calendar_models.dart' show CalEvent;
import '../../utils/live_events.dart';
import '../api_client.dart';
import '../app_time.dart';
import '../offline/app_connectivity.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Small parsers (null-safe, never throw)
// ─────────────────────────────────────────────────────────────────────────────

int meHomeInt(dynamic v, [int fallback = 0]) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fallback);

double meHomeDouble(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? fallback;

Map<String, dynamic> meHomeMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> meHomeMapList(dynamic v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

/// The server's naive-UTC (or zoned) instant as a UTC DateTime, null when absent / unreadable.
DateTime? meHomeUtc(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc();
}

List<CalEvent> meHomeEvents(dynamic v) =>
    [for (final m in meHomeMapList(v)) CalEvent.fromJson(m)].whereType<CalEvent>().toList();

// ─────────────────────────────────────────────────────────────────────────────
//  Model
// ─────────────────────────────────────────────────────────────────────────────

class MeNextLecture {
  const MeNextLecture({required this.id, required this.name, this.scheduledAt, this.durationMinutes = 0, this.track = 'lecture'});

  final int id;
  final String name;
  final DateTime? scheduledAt; // UTC
  final int durationMinutes;
  final String track;

  static MeNextLecture? fromJson(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    return MeNextLecture(
      id: meHomeInt(m['id']),
      name: '${m['name'] ?? ''}',
      scheduledAt: meHomeUtc(m['scheduled_at']),
      durationMinutes: meHomeInt(m['duration_minutes']),
      track: '${m['track'] ?? 'lecture'}',
    );
  }
}

class MeCourseProgress {
  const MeCourseProgress({
    required this.courseId,
    required this.nameAr,
    required this.nameEn,
    this.imageUrl,
    this.progress = 0,
    this.plan,
    this.expiresAt,
    this.nextLecture,
  });

  final int courseId;
  final String nameAr, nameEn;
  final String? imageUrl, plan;

  /// 0–100.
  final double progress;
  final DateTime? expiresAt;
  final MeNextLecture? nextLecture;

  factory MeCourseProgress.fromJson(Map<String, dynamic> m) => MeCourseProgress(
        courseId: meHomeInt(m['course_id']),
        nameAr: '${m['name_ar'] ?? m['name_en'] ?? ''}',
        nameEn: '${m['name_en'] ?? m['name_ar'] ?? ''}',
        imageUrl: m['image_url']?.toString(),
        progress: meHomeDouble(m['progress']).clamp(0, 100).toDouble(),
        plan: m['plan']?.toString(),
        expiresAt: meHomeUtc(m['expires_at']),
        nextLecture: MeNextLecture.fromJson(m['next_lecture']),
      );

  String name(String lang) => lang == 'ar' ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn);
}

/// The teacher block of the payload (teachers only) — passed through for the teacher home.
class MeHomeTeacher {
  const MeHomeTeacher({
    required this.teachingToday,
    required this.pending,
    required this.teachingCourses,
    required this.earningsMonth,
    required this.pendingPayout,
  });

  final List<CalEvent> teachingToday;

  /// attendance_missing · materials_missing · grading · enrollment_requests
  final Map<String, int> pending;
  final int teachingCourses;
  final double earningsMonth, pendingPayout;

  static MeHomeTeacher? fromJson(Map<String, dynamic> m) {
    if (m['teaching_today'] == null && m['pending'] == null && m['earnings'] == null) return null;
    final earnings = meHomeMap(m['earnings']);
    return MeHomeTeacher(
      teachingToday: meHomeEvents(m['teaching_today']),
      pending: {for (final e in meHomeMap(m['pending']).entries) e.key: meHomeInt(e.value)},
      teachingCourses: meHomeInt(m['teaching_courses']),
      earningsMonth: meHomeDouble(earnings['month']),
      pendingPayout: meHomeDouble(earnings['pending_payout']),
    );
  }
}

/// Today's next thing: running now ([live]) or the next one to start.
class MeNextUp {
  const MeNextUp(this.event, {required this.live});
  final CalEvent event;
  final bool live;
}

class MeHome {
  const MeHome({
    required this.now,
    required this.todayDate,
    required this.timezone,
    required this.role,
    required this.orgsEnabled,
    required this.today,
    required this.upcoming,
    required this.attention,
    required this.inboxPreview,
    required this.inboxCounts,
    required this.notificationsUnread,
    required this.orgOverview,
    required this.coursesProgress,
    required this.teacher,
    this.legacy = false,
    this.raw = const {},
  });

  /// The server's clock when it answered (UTC); null on a legacy composition.
  final DateTime? now;

  /// `YYYY-MM-DD` of the platform's today.
  final String todayDate;
  final String timezone, role;
  final bool orgsEnabled;

  /// The platform's today (exam pauses and dated changes applied) and the next 7 days (≤ 10), both by start.
  final List<CalEvent> today, upcoming;

  /// The attention snapshot (`counts`, `total`, `by_org`, `items`, `tabs`).
  final Map<String, dynamic> attention;

  /// The inbox's 5 most urgent rows (to-dos first), raw — wrap with `InboxItem(row)` to draw them.
  final List<Map<String, dynamic>> inboxPreview;

  /// todo · news · offers · done · overdue · due_soon · mandatory
  final Map<String, int> inboxCounts;
  final int notificationsUnread;

  /// `GET /org/public/me/overview` (`items`, `default_org_id`, `pending_total`, `suggested_mode`) or null.
  final Map<String, dynamic>? orgOverview;
  final List<MeCourseProgress> coursesProgress;
  final MeHomeTeacher? teacher;

  /// Composed from today's separate calls (older server).
  final bool legacy;
  final Map<String, dynamic> raw;

  factory MeHome.fromJson(Map<String, dynamic> m, {bool legacy = false}) {
    final today = meHomeEvents(m['today'])..sort((a, b) => a.start.compareTo(b.start));
    final upcoming = meHomeEvents(m['upcoming'])..sort((a, b) => a.start.compareTo(b.start));
    return MeHome(
      now: meHomeUtc(m['now']),
      todayDate: '${m['today_date'] ?? ''}',
      timezone: '${m['timezone'] ?? ''}',
      role: '${m['role'] ?? ''}',
      orgsEnabled: m['orgs_enabled'] != false,
      today: today,
      upcoming: upcoming,
      attention: meHomeMap(m['attention']),
      inboxPreview: meHomeMapList(m['inbox_preview']),
      inboxCounts: {for (final e in meHomeMap(m['inbox_counts']).entries) e.key: meHomeInt(e.value)},
      notificationsUnread: meHomeInt(m['notifications_unread']),
      orgOverview: m['org_overview'] is Map ? meHomeMap(m['org_overview']) : null,
      coursesProgress: meHomeMapList(m['courses_progress']).map(MeCourseProgress.fromJson).toList(),
      teacher: MeHomeTeacher.fromJson(m),
      legacy: legacy,
      raw: m,
    );
  }

  static const MeHome empty = MeHome(
    now: null, todayDate: '', timezone: '', role: '', orgsEnabled: true, today: [], upcoming: [], attention: {},
    inboxPreview: [], inboxCounts: {}, notificationsUnread: 0, orgOverview: null, coursesProgress: const [],
    teacher: null, legacy: true,
  );

  // ── attention ──────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get attentionItems => meHomeMapList(attention['items']);

  /// The badge number of a tab (`AttentionTabs.x`); with [orgId] only that organization's items.
  int attentionCount(String tab, {int? orgId}) {
    var n = 0;
    for (final x in attentionItems) {
      if ('${x['tab']}' != tab) continue;
      if (orgId != null && meHomeInt(x['org_id'], -1) != orgId) continue;
      n += meHomeInt(x['count'], 1);
    }
    return n;
  }

  int get attentionTotal => meHomeInt(attention['total']);

  // ── inbox ──────────────────────────────────────────────────────────────────

  int get inboxTodo => inboxCounts['todo'] ?? 0;
  int get inboxOverdue => inboxCounts['overdue'] ?? 0;
  int get inboxDueSoon => inboxCounts['due_soon'] ?? 0;

  /// The preview rows of one organization (`org_id`).
  List<Map<String, dynamic>> inboxPreviewOf(int orgId) =>
      [for (final x in inboxPreview) if (meHomeInt(x['org_id'], -1) == orgId) x];

  // ── organization ───────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get orgEntries => meHomeMapList(orgOverview?['items']);

  /// The overview entry of one organization (`{organization, roles, manage, todo, approvals, news}`), or null.
  Map<String, dynamic>? orgEntry(int orgId) {
    for (final e in orgEntries) {
      if (meHomeInt(meHomeMap(e['organization'])['id'], -1) == orgId) return e;
    }
    return null;
  }

  /// Today's events of one organization (timetable slots, extras, exams, its meetings).
  List<CalEvent> todayOf(int orgId) => [for (final e in today) if (e.orgId == orgId) e];

  List<CalEvent> upcomingOf(int orgId) => [for (final e in upcoming) if (e.orgId == orgId) e];

  // ── the hero ───────────────────────────────────────────────────────────────

  /// Today's next thing at [nowUtc] (default: the device clock): the event running now, else the first one still
  /// to start; declined meetings are skipped. Null once the day is over (or free).
  MeNextUp? nextUp([DateTime? nowUtc, Iterable<CalEvent>? events]) {
    final now = nowUtc ?? DateTime.now().toUtc();
    for (final e in events ?? today) {
      if (e.declined || !e.end.isAfter(now)) continue;
      return MeNextUp(e, live: !e.start.isAfter(now));
    }
    return null;
  }

  /// The first event of the coming days (the "free today" hero's hint).
  CalEvent? get firstUpcoming => upcoming.firstOrNull;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Outcome of the call
// ─────────────────────────────────────────────────────────────────────────────

enum MeHomeOutcome {
  ok,

  /// The server has no `/me/home` yet (bare 404 "Not Found" / 405): compose it from the separate calls.
  legacy,

  /// 403 `role_not_supported` (parents): this role has no home payload.
  unsupported,
  failed,
}

MeHomeOutcome meHomeOutcomeOf(ApiException e) {
  if (e.statusCode == 405) return MeHomeOutcome.legacy;
  if (e.statusCode == 404 && ApiException.asMap(e.body)?['detail'] == 'Not Found') return MeHomeOutcome.legacy;
  if (e.statusCode == 403 && e.code == 'role_not_supported') return MeHomeOutcome.unsupported;
  return MeHomeOutcome.failed;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Service
// ─────────────────────────────────────────────────────────────────────────────

typedef MeHomeFetch = Future<dynamic> Function(String path, {Map<String, dynamic>? query});

class MeHomeService extends ChangeNotifier with WidgetsBindingObserver {
  MeHomeService({MeHomeFetch? fetch, Future<String?> Function()? token, DateTime Function()? clock})
      : _fetch = fetch ?? _apiFetch,
        _token = token ?? _apiToken,
        _clock = clock ?? (() => DateTime.now().toUtc());

  static final MeHomeService instance = MeHomeService();

  static const path = '/api/v1/me/home';
  static const calendarPath = '/api/v1/me/calendar';
  static const attentionPath = '/api/v1/me/attention';
  static const inboxPath = '/api/v1/me/inbox';

  /// A cached home older than this is reloaded by [ensure] (a tab re-opened after a while).
  static const staleAfter = Duration(seconds: 45);
  static const upcomingDays = 7;
  static const upcomingMax = 10;

  static Future<dynamic> _apiFetch(String p, {Map<String, dynamic>? query}) => ApiClient().get(p, queryParams: query);
  static Future<String?> _apiToken() => ApiClient().accessToken;

  final MeHomeFetch _fetch;
  final Future<String?> Function() _token;
  final DateTime Function() _clock;

  MeHome? home;
  bool loading = false;
  ApiException? error;
  MeHomeOutcome outcome = MeHomeOutcome.ok;
  DateTime? loadedAt;
  Future<void>? _running;
  StreamSubscription<LiveEvent>? _live;
  bool _wired = false;

  bool get legacy => outcome == MeHomeOutcome.legacy;
  bool get unsupported => outcome == MeHomeOutcome.unsupported;

  /// Nothing to show and the last load failed → the screen shows ErrorRetry.
  bool get failed => home == null && error != null;

  bool get _stale => loadedAt == null || _clock().difference(loadedAt!) > staleAfter;

  /// Once per open: load when nothing is cached or the cache is stale; a cached home paints at once.
  Future<void> ensure() => home == null || _stale ? refresh() : Future.value();

  /// Reload now; a call already in flight is shared.
  Future<void> refresh() => _running ??= _load().whenComplete(() => _running = null);

  Future<void> _load() async {
    String? token;
    try {
      token = await _token();
    } catch (_) {}
    if (token == null || token.isEmpty) return; // guest / signed out: no call, no 401 redirect
    loading = true;
    notifyListeners();
    try {
      final r = await _fetch(path);
      if (r is Map) {
        home = MeHome.fromJson(Map<String, dynamic>.from(r));
        outcome = MeHomeOutcome.ok;
        error = null;
        loadedAt = _clock();
      }
    } catch (e) {
      final err = ApiException.from(e);
      final o = meHomeOutcomeOf(err);
      if (o == MeHomeOutcome.legacy) {
        outcome = o;
        home = await _legacyLoad();
        error = null;
        loadedAt = _clock();
      } else if (o == MeHomeOutcome.unsupported) {
        outcome = o;
        home = null;
        error = null;
      } else {
        error = err; // keep the last home: a failed refresh never blanks the screen
      }
    }
    loading = false;
    notifyListeners();
  }

  /// Older server: today + 7 days from the calendar, the attention snapshot and the inbox, each best-effort.
  Future<MeHome> _legacyLoad() async {
    final now = _clock();
    final wall = AppTime.toZone(now);
    final dayStart = AppTime.fromZone(DateTime(wall.year, wall.month, wall.day));
    final dayEnd = dayStart.add(const Duration(days: 1));
    final results = await Future.wait<dynamic>([
      _quiet(() => _fetch(calendarPath, query: {
            'start': dayStart.toIso8601String(),
            'end': dayEnd.add(const Duration(days: upcomingDays)).toIso8601String(),
          })),
      _quiet(() => _fetch(attentionPath)),
      _quiet(() => _fetch(inboxPath)),
    ]);
    final events = CalEvent.listFrom(results[0])..sort((a, b) => a.start.compareTo(b.start));
    final inbox = meHomeMap(results[2]);
    final items = meHomeMapList(inbox['items']);
    final preview = [
      ...items.where((x) => '${x['segment'] ?? 'todo'}' == 'todo'),
      ...items.where((x) => '${x['segment'] ?? 'todo'}' != 'todo'),
    ].take(5).toList();
    return MeHome(
      now: now,
      todayDate: '${wall.year.toString().padLeft(4, '0')}-${wall.month.toString().padLeft(2, '0')}-${wall.day.toString().padLeft(2, '0')}',
      timezone: '',
      role: '',
      orgsEnabled: true,
      today: [for (final e in events) if (e.start.isBefore(dayEnd)) e],
      upcoming: [for (final e in events) if (!e.start.isBefore(dayEnd)) e].take(upcomingMax).toList(),
      attention: meHomeMap(results[1]),
      inboxPreview: preview,
      inboxCounts: {for (final e in meHomeMap(inbox['counts']).entries) e.key: meHomeInt(e.value)},
      notificationsUnread: 0,
      orgOverview: null, // AppModeController keeps the overview on an older server
      coursesProgress: const [],
      teacher: null,
      legacy: true,
    );
  }

  static Future<dynamic> _quiet(Future<dynamic> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }

  /// Logout.
  void clear() {
    home = null;
    error = null;
    loadedAt = null;
    outcome = MeHomeOutcome.ok;
    notifyListeners();
  }

  // ── live wiring (only while something listens) ─────────────────────────────

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_wired) return;
    _wired = true;
    WidgetsBinding.instance.addObserver(this);
    _live = LiveEvents.instance.listen({...LiveEvents.silentTypes, LiveEvents.attentionChanged}, (_) => _quietRefresh());
    AppConnectivity.instance.online.addListener(_onConnectivity);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (hasListeners || !_wired) return;
    _wired = false;
    _live?.cancel();
    _live = null;
    AppConnectivity.instance.online.removeListener(_onConnectivity);
    WidgetsBinding.instance.removeObserver(this);
  }

  DateTime? _lastQuiet;

  /// Events can burst (several `*_updated` in a row): at most one reload per 5 s.
  void _quietRefresh() {
    final now = _clock();
    if (_lastQuiet != null && now.difference(_lastQuiet!) < const Duration(seconds: 5)) return;
    _lastQuiet = now;
    refresh();
  }

  /// Back online (AppConnectivity says so only after the server answered) → retry a failed load.
  void _onConnectivity() {
    if (!AppConnectivity.instance.isOnline || loading) return;
    if (error != null || home == null) refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ensure();
  }
}
