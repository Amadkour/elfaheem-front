// ─────────────────────────────────────────────────────────────────────────────
// teacher_home_provider.dart
//
// Owns ONLY the teacher home / dashboard state: stats, the small course
// preview shown on the home grid, the upcoming schedule, the pending counters
// and — Track B.5 — the teacher block of GET /me/home ([extra]: earnings,
// inbox preview, unread notifications).
//
// PROVIDER SPLIT
// ─────────────────────────────────────────────────────────────────────────
// Full course management (list, filter, CRUD) lives in
// `teacher_courses_provider.dart`'s `TeacherCoursesProvider`. Both are
// registered as separate, independent providers at the app root (see
// core/providers.dart), so either screen can read the one it needs without a
// hard dependency on the other.
//
// LOADING
// ─────────────────────────────────────────────────────────────────────────
// `init()` awaits GET /teacher/dashboard (the main aggregate, through run())
// and GET /me/home together, so the home paints ONE skeleton and then the
// whole body. /me/home never fails the home: a bare 404 (older server) marks
// it missing for the session and the tiles it feeds stay hidden; any other
// failure keeps the last good block. `ensureLoaded(userId)` is what the home
// screen calls on mount — it loads once per signed-in user (the screen is
// kept alive; a different account after /login reloads, the same one does
// not). `refreshSilently()` is the same fetch without the loading state, for
// background refreshes (the per-second schedule ticker in
// queue_work_items.dart, a course saved on another tab).
//
// LIVE NOW
// ─────────────────────────────────────────────────────────────────────────
// `liveNow` (the meetings I'm invited to that are live) follows `meeting_live` / `session_live` (LiveEvents): an
// end drops the room at once, then ONLY GET /me/home is asked again (at most once per 2 s); an older server without
// `live_now` shows the rooms the events announced. Wired once the home loaded; no timer.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:async';

import '../../../core/api_client.dart';
import '../../../core/app_mode.dart';
import '../../../core/base_provider.dart';
import '../../../core/home/me_home.dart' show MeHomeService, MeLiveRoom, liveRoomsAfterEvent;
import '../../../utils/live_events.dart';
import '../courses/component/teacher_stats.dart';
import 'teacher_home_extra.dart';
import 'teacher_models.dart';

class TeacherHomeProvider extends BaseProvider {
  final ApiClient _api;

  TeacherHomeProvider({ApiClient? api}) : _api = api ?? ApiClient() {
    _side = _sideKey;
    AppModeController.instance.addListener(_onMode);
  }

  // ── Side (personal account ↔ organization) ───────────────────────────────
  // GET /teacher/dashboard and GET /me/home carry the mode's `scope` / `org_id` (MeHomeService.scopeQuery): the
  // course preview, stats and Go live list are that side's. A switch drops the other side's preview at once and
  // reloads; an answer that arrives after a switch is dropped.

  late String _side;

  static String get _sideKey {
    final q = MeHomeService.scopeQuery();
    return '${q['scope']}:${q['org_id'] ?? ''}';
  }

  void _onMode() {
    final now = _sideKey;
    if (now == _side) return;
    _side = now;
    if (!_loaded) return; // the home never loaded: nothing to reload
    _homeCourses = [];
    _stats = const TeacherStats();
    _schedule = [];
    _pending = const {};
    notifyListeners();
    _fetchDashboard();
  }

  // ── Dashboard state ──────────────────────────────────────────────────────

  TeacherStats _stats = const TeacherStats();
  List<TeacherCourse> _homeCourses = [];
  List<ScheduleSession> _schedule = [];
  Map<String, int> _pending = const {};
  TeacherHomeExtra? _extra;
  bool _extraMissing = false;
  bool _loaded = false;
  int? _loadedFor;

  TeacherStats get stats => _stats;

  /// Course preview for the home grid only — the full, filterable course
  /// list lives in [TeacherCoursesProvider]. The screen additionally clamps
  /// this to 8 items.
  List<TeacherCourse> get homeCourses => List.unmodifiable(_homeCourses);

  List<ScheduleSession> get schedule => List.unmodifiable(_schedule);

  /// attendance_missing · materials_missing · grading · enrollment_requests (GET /teacher/dashboard `pending`,
  /// else the same block of GET /me/home).
  Map<String, int> get pending => _pending.isNotEmpty ? _pending : (_extra?.pending ?? const {});

  /// The teacher block of GET /me/home; null while it has not arrived or on an older server.
  TeacherHomeExtra? get extra => _extra;

  /// Older server (no `live_now`): the rooms the live events announced.
  List<MeLiveRoom> _eventRooms = const [];

  /// The "Live now" banner's rooms (see LIVE NOW above).
  List<MeLiveRoom> get liveNow {
    final x = _extra;
    return x == null || !x.liveNowKnown ? _eventRooms : x.liveNow;
  }

  StreamSubscription<LiveEvent>? _liveSub;
  DateTime? _lastLive;

  void _wireLive() {
    _liveSub ??= LiveEvents.instance.listen({LiveEvents.meetingLive, LiveEvents.sessionLive}, onLiveRoomEvent);
  }

  /// A room went live / ended (public for tests).
  void onLiveRoomEvent(LiveEvent e) {
    final x = _extra;
    if (x != null && x.liveNowKnown && '${e.data['live']}' == 'false') {
      // drop it at once (the reload confirms)
      final meeting = e.type == LiveEvents.meetingLive;
      final key = '${meeting ? 'meeting' : 'session'}:${e.data[meeting ? 'meeting_id' : 'session_id']}';
      _extra = x.withLiveNow([for (final r in x.liveNow) if (r.key != key) r]);
    }
    _eventRooms = liveRoomsAfterEvent(_eventRooms, e);
    notifyListeners();
    final now = DateTime.now();
    if (_lastLive != null && now.difference(_lastLive!) < const Duration(seconds: 2)) return;
    _lastLive = now;
    _fetchExtra().then((extra) {
      if (extra == null) return;
      _extra = extra;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    AppModeController.instance.removeListener(_onMode);
    super.dispose();
  }

  /// True once GET /teacher/dashboard answered at least once (a later failure keeps the data on screen).
  bool get loaded => _loaded;

  // ─────────────────────────────────────────────────────────────────────────
  // Bootstrap
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> init() => _fetchDashboard();

  /// Loads once per signed-in user: the home screen is kept alive across tab switches, and after a /login as the
  /// SAME account nothing is fetched again; a different account (or the first mount) loads.
  Future<void> ensureLoaded(int? userId) {
    if (_loaded && _loadedFor == userId) return Future.value();
    _loadedFor = userId;
    return _fetchDashboard();
  }

  /// Same fetch as [init], but never puts the provider into
  /// [ProviderState.loading]. Use this for background/automatic refreshes
  /// where flashing a full-screen loading state would be jarring and isn't
  /// tied to any user action.
  Future<void> refreshSilently() => _fetchDashboard(silent: true);

  Future<void> _fetchDashboard({bool silent = false}) async {
    final side = _side;
    final extraFuture = _fetchExtra();
    final result = await run(
      () => _api.get('/api/v1/teacher/dashboard', queryParams: MeHomeService.scopeQuery()),
      makLoading: !silent,
    );
    final extra = await extraFuture;
    if (side != _side) return; // the mode changed meanwhile: the reload it started answers for the new side
    if (result is Map<String, dynamic>) {
      final data = TeacherDashboardData.fromJson(result);
      _stats = data.stats;
      _homeCourses = data.courses;
      _schedule = data.schedule;
      _pending = data.pending;
      _loaded = true;
    }
    if (extra != null) _extra = extra;
    _wireLive();
    notifyListeners();
  }

  /// GET /me/home — the teacher block. Never throws: a bare 404 / 405 marks the route missing for the session
  /// (older server), any other failure returns null and the last good block stays.
  Future<TeacherHomeExtra?> _fetchExtra() async {
    if (_extraMissing) return null;
    try {
      final query = MeHomeService.scopeQuery(); // the mode's side, as the course lists — captured before the GET
      final r = await _api.get('/api/v1/me/home', queryParams: query);
      if (r is Map<String, dynamic>) {
        // the same payload feeds the shared home cache: Organization mode (OrgMemberHome) reads it from there —
        // only while the side it was asked for is still the current one (a switch meanwhile = the other side's home)
        MeHomeService.instance.adopt(r, query: query);
        return TeacherHomeExtra.fromJson(r);
      }
    } on ApiException catch (e) {
      if (teacherHomeExtraMissing(e)) _extraMissing = true;
    } catch (_) {
      // transient: keep what we had
    }
    return null;
  }
}
