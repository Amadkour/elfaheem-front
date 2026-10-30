/// courses/details/course_detail_provider.dart
library;


import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../../../../core/live/event_wait.dart';
import '../../../../utils/helpers.dart';
import '../../../../utils/live_events.dart';
import '../../../shared/course/course_space/course_sessions.dart' show courseStudentSessionDone;
import '../../../shared/guest/guest_state.dart';
import '../../models.dart';
import 'components/issued_certificate.dart';
import 'session_exam_gate.dart';
export 'session_exam_gate.dart';

class CourseDetailProvider extends BaseProvider {
  final ApiClient _api;

  CourseDetailProvider({ApiClient? api}) : _api = api ?? ApiClient();

  late CourseModel course;
  CourseDetailTab _activeTab = CourseDetailTab.lessons;

  // ── Progress ───────────────────────────────────────────────────────────────
  double progressPercentage = 0.0;

  /// Set of materialIds the student has already completed.
  /// Used by the UI to show a ✓ badge on each material tile.
  final Set<int> completedMaterialIds = {};

  /// Set of sessionIds the student has already completed.
  final Set<int> completedSessionIds = {};

  /// Certificates the teacher issued to THIS student for THIS course
  /// (shown in the "About" tab → "My certificates").
  List<IssuedCertificate> myCertificates = [];

  /// sessionId → the exam(s) attached to that session. Only sessions that have
  /// a published exam are present. A student must PASS these exams before the
  /// sessions after them unlock (see [isSessionUnlocked]).
  final Map<int, SessionExamGate> examGates = {};

  /// Optional intro video (عرض أولي) — shown in the hero INSTEAD of the
  /// course image when the teacher added one. Read straight from the
  /// `reel_url` key of GET /courses/{id}.
  String? reelUrl;

  CourseDetailTab get activeTab => _activeTab;

  // ── Device-blocked signal ─────────────────────────────────────────────────
  // The provider only REPORTS that the device is blocked; the screen listens
  // and shows the dialog (the provider must not hold a BuildContext).
  bool _deviceBlocked = false;

  /// One-shot: returns true once after a fetch hit a device-blocked error.
  bool consumeDeviceBlocked() {
    final v = _deviceBlocked;
    _deviceBlocked = false;
    return v;
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init(CourseModel c) async {
    course = c;
    makeLoading();
    // Run sessions + optional progress fetch in parallel for speed
    await Future.wait([
      fetchFull(c.id),
      // fetchProgress(c.id),
    ]);
    stopLoading();
  }

  // ── Course data ───────────────────────────────────────────────────────────

  /// Why the course cannot be shown: the server answers 404 for a draft / unknown course (to non-staff) and
  /// 403 `course_locked` for a private course without access (both on the course and on its session list).
  /// Null while the course is reachable.
  CourseBlock? block;

  /// Remembers a 404 / 403 course_locked on the way through [run] (which turns every ApiException into null).
  Future<dynamic> _guarded(Future<dynamic> Function() call) async {
    try {
      return await call();
    } on ApiException catch (e) {
      final b = courseBlockOf(e);
      if (b != null) block = b;
      rethrow;
    }
  }

  Future<void> fetchFull(String courseId) async {
    block = null;
    final r = await run(
          () => _guarded(() => _api.get('/api/v1/courses/$courseId', auth: true)),
    );
    if (r is Map<String, dynamic>) {
      course = CourseModel.fromJson(r);
      final reel = (r['reel_url'] as String?)?.trim();
      reelUrl = (reel == null || reel.isEmpty) ? null : reel;
    }
    if (block == CourseBlock.unavailable) {
      sessions = [];
      notifyListeners();
      return;
    }
    await Future.wait([
      fetchSessions(courseId),
      if (course.isEnrolled) fetchMyCertificates(courseId),
    ]);
    _watchLive(courseId);
  }

  // The live card follows the teacher: the server sends `session_live` to the enrolled students when a session of
  // this course starts (and ends); a slow poll covers a closed stream. Guests have no stream (no account).
  EventOrPoll? _liveWatch;
  String? _liveWatchCourse;
  bool _disposed = false;

  void _watchLive(String courseId) {
    if (GuestState.active || _liveWatchCourse == courseId) return;
    _liveWatch?.dispose();
    _liveWatchCourse = courseId;
    _liveWatch = EventOrPoll(
      names: const {LiveEvents.sessionLive},
      match: (e) => '${e.data['course_id']}' == courseId,
      every: const Duration(seconds: 30),
      fallbackEvery: const Duration(minutes: 2),
      poll: refreshSessionsSilently,
    )..start();
  }

  @override
  void dispose() {
    _disposed = true;
    _liveWatch?.dispose();
    super.dispose();
  }

  // ── My certificates ───────────────────────────────────────────────────────

  /// GET /api/v1/courses/{id}/my-certificates — silent on failure: the
  /// section simply doesn't show, it must never break the course screen.
  Future<void> fetchMyCertificates(String courseId) async {
    try {
      final r = await _api.get(
        '/api/v1/courses/$courseId/my-certificates',
        auth: true,
      );
      if (r is List) {
        myCertificates = r
            .whereType<Map<String, dynamic>>()
            .map(IssuedCertificate.fromJson)
            .toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  List<SessionModel> sessions = [];

  /// all · lecture · section (sections are taught by the assistant)
  String trackFilter = 'all';
  void setTrackFilter(String v) {
    trackFilter = v;
    notifyListeners();
  }

  // ── Pagination ────────────────────────────────────────────────────────────
  int _sessionsSkip = 0;
  bool _hasMoreSessions = true;
  static const _sessionsPageSize = 20;

  /// The server clamps a page to 1..500 (`SESSIONS_PAGE_MAX`); the teacher's studio loads the course in one such page.
  static const _sessionsRestLimit = 500;

  bool get hasMoreSessions => _hasMoreSessions;

  /// True only while fetching another page onto an already-populated list —
  /// distinct from the initial-load spinner, so the UI can show a small
  /// footer loader instead of blanking the whole list.
  bool get isLoadingMoreSessions => isLoading && sessions.isNotEmpty;

  List<SessionModel> get liveSessions =>
      sessions.where((e) => e.isLiveActive).toList();

  /// Fetches page 1 fresh (used on pull-to-refresh / first open).
  /// Pass [reset]=false to append the next page instead (see
  /// [loadMoreSessions]).
  ///
  /// A course with sections loads the rest of its sessions right after the first page (N3): the Lectures / Sections
  /// tabs count and filter the loaded list, and a page of 20 read "Lectures 10 · Sections 10" for a 32-session course.
  Future<void> fetchSessions(String courseId, {bool reset = true, bool rest = false}) async {
    if (reset) {
      _sessionsSkip = 0;
      _hasMoreSessions = true;
      sessions = [];
      examGates.clear();
    }
    try {
      final result = await run(
            () => _guarded(() => _api.get(
          // Guest: the public outline (titles / order only, never any media URL).
          GuestState.active
              ? '/api/v1/courses/$courseId/sessions/public'
              : '/api/v1/courses/$courseId/sessions',
          queryParams: {'skip': _sessionsSkip, 'limit': rest ? _sessionsRestLimit : _sessionsPageSize},
        )),
      );
      var loadRest = false;
      if (result is Map && result['items'] is List) {
        final items = result['items'] as List;
        final page =
        items
            .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) {
            int compareOrder = a.order.compareTo(b.order);
            if (compareOrder == 0) {
              return a.createdAt.compareTo(b.createdAt);
            }
            return compareOrder;
          });

        _storeGates(items);
        sessions = [...sessions, ...page];
        _sessionsSkip += page.length;
        _hasMoreSessions = page.length == (rest ? _sessionsRestLimit : _sessionsPageSize);
        loadRest = !rest && _hasMoreSessions && sessions.any((s) => s.track == 'section');
      }
      completedSessionIds.clear();
      completedSessionIds.addAll(
        sessions.where((e) => e.isCompleted).map((e) => e.id),
      );
      if (loadRest) {
        notifyListeners();
        return await fetchSessions(courseId, reset: false, rest: true);
      }
    } on ApiException catch (e) {
      if (e.isDeviceBlocked) {
        // Screen listens to this and shows the device-blocked dialog.
        _deviceBlocked = true;
        notifyListeners();
        return;
      }
      Helpers.showMessage(e.message);
    } catch (e) {
      Helpers.showMessage(apiErrorText(ApiException.from(e)));
      return;
    }
    notifyListeners();
  }

  /// Fetches the next page and appends it. No-ops while a fetch is already
  /// in flight or once the server has told us there's nothing more.
  Future<void> loadMoreSessions() async {
    if (!_hasMoreSessions || isLoading) return;
    await fetchSessions(course.id, reset: false);
  }

  Future<void> refresh() => fetchFull(course.id);

  /// Re-reads the sessions already on screen WITHOUT a loading flash or
  /// losing the loaded pages. Used after the student comes back from the exam
  /// tab, so a freshly passed exam unlocks the next sessions immediately.
  Future<void> refreshSessionsSilently() async {
    try {
      final limit = sessions.length > _sessionsPageSize
          ? sessions.length
          : _sessionsPageSize;
      final result = await _api.get(
        GuestState.active
            ? '/api/v1/courses/${course.id}/sessions/public'
            : '/api/v1/courses/${course.id}/sessions',
        queryParams: {'skip': 0, 'limit': limit},
      );
      if (result is Map && result['items'] is List) {
        final items = result['items'] as List;
        final fresh =
        items
            .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) {
            final c = a.order.compareTo(b.order);
            return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
          });
        examGates.clear();
        _storeGates(items);
        sessions = fresh;
        _sessionsSkip = fresh.length;
        _hasMoreSessions = fresh.length == limit;
        completedSessionIds
          ..clear()
          ..addAll(fresh.where((e) => e.isCompleted).map((e) => e.id));
        if (!_disposed) notifyListeners(); // a live-watch poll may land after the page closed
      }
    } catch (_) {}
  }

  void _storeGates(List items) {
    for (final raw in items.whereType<Map<String, dynamic>>()) {
      final id = raw['id'] as int;
      final gate = SessionExamGate.fromJson(raw['exams']);
      if (gate.isEmpty) {
        examGates.remove(id);
      } else {
        examGates[id] = gate;
      }
    }
  }

  // ── Sequential unlock logic ──────────────────────────────────────────────

  /// Whether the session at [index] (position within the sorted [sessions]
  /// list) is open for the current student.
  ///
  /// Rules:
  /// • Session 1 (index 0) is always open — it's the free preview.
  /// • Any later session is open only if the student is ENROLLED and the
  ///   PREVIOUS session is complete (server-computed `completeness`: every
  ///   material completed AND the session's exam passed, when it has one).
  bool isSessionUnlocked(int index) {
    if (index < 0 || index >= sessions.length) return false;
    if (index == 0) return true;
    if (!course.isEnrolled) return false;
    return sessions[index - 1].isCompleted;
  }

  /// The session right before [index], or null for the first one.
  /// Lets the UI say "finish «X» first" on a locked session.
  SessionModel? previousSessionOf(int index) =>
      (index > 0 && index <= sessions.length) ? sessions[index - 1] : null;

  /// The not-yet-passed exam of the previous session (null → the lock, if any,
  /// is caused by unfinished materials rather than an exam). Drives the UI message.
  SessionExamInfo? blockingExamFor(int index) {
    final prev = previousSessionOf(index);
    return prev == null ? null : examGates[prev.id]?.firstPending;
  }

  // ── Exam passed → complete session + open next ───────────────────────────

  /// Call this right after the student passes an exam attached to [sessionId].
  ///
  /// 1. Re-reads sessions + exam gates + `completeness` from the server.
  ///    Passing the exam does NOT complete the materials — the session only
  ///    becomes complete when its materials are done too (server decides).
  /// 2. Returns the next session if it is now unlocked, otherwise null
  ///    (materials unfinished, other exams pending, last session, not enrolled).
  Future<SessionModel?> onSessionExamPassed(int sessionId) async {
    await _syncProgressFromServer(); // progress numbers + refreshSessionsSilently
    final stillPending = examGates[sessionId]?.firstPending != null;

    var idx = sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return null;

    // Next session may be on a page that hasn't been loaded yet.
    if (idx + 1 >= sessions.length && _hasMoreSessions) {
      await loadMoreSessions();
      idx = sessions.indexWhere((s) => s.id == sessionId);
    }

    final nextIdx = idx + 1;
    if (nextIdx >= sessions.length) return null;
    final next = isSessionUnlocked(nextIdx) ? sessions[nextIdx] : null;

    // Signal for the UI: "open this session now" (see consumeSessionToOpen).
    // Only when this call actually just finished the session's exam gate.
    if (next != null && !stillPending) {
      _sessionToOpenId = next.id;
      notifyListeners();
    }
    return next;
  }

  int? _sessionToOpenId;

  /// One-shot: the id of the session that should be opened now (the one that
  /// just unlocked after passing the previous session's exam), or null.
  int? consumeSessionToOpen() {
    final v = _sessionToOpenId;
    _sessionToOpenId = null;
    return v;
  }

  /// Same rule as [isSessionUnlocked] but looked up by session id — useful
  /// for widgets (e.g. the "live" tab) that only render a filtered subset
  /// of [sessions] and can't rely on their position in that subset.
  bool isSessionUnlockedById(int sessionId) {
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    return isSessionUnlocked(idx);
  }

  /// "Continue learning": the session whose row should open and scroll into view (+ a counter, so a second tap
  /// on the same session opens it again). The row clears nothing — it compares [focusTick] with the last it saw.
  int? focusSessionId;
  int focusTick = 0;

  /// The next thing the student can actually take: the first unlocked, unfinished session that has something to
  /// play — not a live session whose time is over with nothing recorded in it (that row has nothing to open).
  SessionModel? get nextPlayable {
    final now = DateTime.now().toUtc();
    for (final s in sessions) {
      if (!isSessionUnlockedById(s.id)) continue;
      if (s.isLiveActive) return s;
      // the timeline's own "done" (N1): an empty session the server calls complete is not skipped while ahead
      final done = courseStudentSessionDone(
        serverDone: s.isCompleted,
        materials: s.totalMaterial,
        materialsDone: s.completeMaterial,
        when: s.scheduledAt?.toUtc(),
        minutes: s.durationMinutes,
        now: now,
      );
      if (done) continue;
      final hasContent = s.totalMaterial > 0 || s.hasRecording;
      if (s.isLive && !hasContent) {
        final at = s.scheduledAt;
        final over = at == null || at.add(Duration(minutes: s.durationMinutes > 0 ? s.durationMinutes : 60)).isBefore(now);
        if (over) continue;
      }
      if (!s.isLive && !hasContent) continue;
      return s;
    }
    return null;
  }

  /// Opens the Lessons tab on [sessionId]'s row (expanded, scrolled into view).
  void focusSession(int sessionId) {
    focusSessionId = sessionId;
    focusTick++;
    _activeTab = CourseDetailTab.lessons;
    notifyListeners();
  }

  void setTab(CourseDetailTab tab) {
    if (_activeTab == tab) return;
    final leavingExams =
        _activeTab == CourseDetailTab.exam && tab != CourseDetailTab.exam;
    _activeTab = tab;
    notifyListeners();
    // The student may just have passed a session exam → refresh the gates.
    if (leavingExams && course.isEnrolled && examGates.isNotEmpty) {
      refreshSessionsSilently();
    }
  }

  Future<void> toggleFavorite() async {
    if (GuestState.active) return; // the UI already showed the login sheet
    if (ViewAsState.active) return; // read-only: the server would refuse it and the heart would flicker back
    final was = course.isFavorite;
    course = course.copyWith(isFavorite: !was);
    notifyListeners();
    final r = was
        ? await _api.delete('/api/v1/courses/${course.id}/favorite')
        : await _api.post('/api/v1/courses/${course.id}/favorite');
    if (r == null && hasError) {
      course = course.copyWith(isFavorite: was);
      notifyListeners();
    }
  }

  Future<void> enroll(CourseModel c) async {
    if (GuestState.active) return;
    if (ViewAsState.active || c.isEnrolled) return; // an admin viewing a student must never enrol them
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/courses/${course.id}/enroll'));
    c.isEnrolled = false;
    if (r != null) c.isEnrolled = true;
    notifyListeners();
  }

  // ── Student material completion ───────────────────────────────────────────

  /// Called when a student finishes a material (video end / image dismiss /
  /// PDF-link open). Updates local state immediately for instant UI feedback,
  /// then persists to the backend.
  ///
  /// Endpoint: POST /api/v1/sessions/{sessionId}/materials/{materialId}/complete
  Future<void> markMaterialComplete(int sessionId, int materialId) async {
    if (ViewAsState.active) return; // view-as is read-only: no progress is recorded (and no optimistic tick)
    if (sessionId <= 0 || materialId <= 0) return; // placeholder material
    // Optimistic local update so the ✓ badge appears instantly
    if (completedMaterialIds.contains(materialId)) return; // already done
    completedMaterialIds.add(materialId);
    notifyListeners();

    final r = await run(
          () => _api.post(
        '/api/v1/sessions/$sessionId/materials/$materialId/complete',
        auth: true,
      ),
    );

    // If the server rejected it, roll back the optimistic update
    if (r == null && hasError) {
      completedMaterialIds.remove(materialId);
      notifyListeners();
    } else {
      await _syncProgressFromServer();
    }
  }

  // ── Student session (live) completion ─────────────────────────────────────

  /// Called automatically when a student leaves the LiveKit room.
  /// Endpoint: POST /api/v1/sessions/{sessionId}/complete
  Future<void> markSessionComplete(int sessionId) async {
    if (ViewAsState.active) return;
    if (completedSessionIds.contains(sessionId)) return;
    // No optimistic add: completeness is computed by the server (materials +
    // exam), and an optimistic flag would unlock the next session too early.
    await run(
          () => _api.post('/api/v1/sessions/$sessionId/complete', auth: true),
    );
    await _syncProgressFromServer();
  }

  /// Pulls the authoritative numbers after a completion was saved: the
  /// course's overall progress / material counters, and every session's
  /// completeMaterial / progress / completeness (which drives which session
  /// unlocks next). Counting locally would double-count a material the
  /// student had already completed in an earlier run, because the backend
  /// endpoint is idempotent and doesn't say whether the row was new.
  /// Silent on failure — the optimistic tick stays.
  Future<void> _syncProgressFromServer() async {
    try {
      final cr = await _api.get('/api/v1/courses/${course.id}', auth: true);
      if (cr is Map<String, dynamic>) {
        course.progress = ((cr['progress'] as num?)?.toDouble() ?? 0.0).round();
        course.materialsTotal =
            cr['materials_total'] as int? ?? course.materialsTotal;
        course.materialsCompleted =
            cr['materials_completed'] as int? ?? course.materialsCompleted;
        notifyListeners();
      }
    } catch (_) {}
    await refreshSessionsSilently();
  }

  // ── Student live-session join ─────────────────────────────────────────────

  /// Fetches the student's personal join token for an already-active
  /// live session.
  /// Endpoint: GET /api/v1/live-sessions/{sessionId}/join
  /// Returns a [LiveJoinResponse] (url + token) or null on error.
  Future<Map<String, dynamic>?> fetchStudentJoinToken(int sessionId) async {
    final r = await run(
          () => _api.get('/api/v1/live-sessions/$sessionId/join', auth: true),
    );
    if (r is Map<String, dynamic>) return r;
    return null;
  }

// ── Private helpers ───────────────────────────────────────────────────────

/// Recomputes a local estimate of overall progress without waiting for
/// a full server round-trip (used for optimistic updates).
// void _recalcProgress() {
//   int sessionsTotal = course.sessions.length ?? 0;
//   int materialsTotal = course.sessions
//       .fold<int>(0, (sum, s) => sum + (s.materials?.length ?? 0)) ??
//       0;
//   int total = sessionsTotal + materialsTotal;
//   if (total == 0) {
//     progressPercentage = 0.0;
//     return;
//   }
//   int done = completedSessionIds.length + completedMaterialIds.length;
//   progressPercentage = double.parse(
//       ((done / total) * 100).toStringAsFixed(1));
// }
}
/// Why a course page cannot show the course.
enum CourseBlock {
  /// 403 `course_locked`: a private course; the access code opens it.
  locked,

  /// 404: a draft or an unknown course (the server hides drafts from non-staff).
  unavailable,
}

/// The [CourseBlock] an API error means, or null for any other failure.
CourseBlock? courseBlockOf(ApiException e) {
  if (e.code == 'course_locked') return CourseBlock.locked;
  if (e.statusCode == 404) return CourseBlock.unavailable;
  return null;
}
