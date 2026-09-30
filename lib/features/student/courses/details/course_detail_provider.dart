/// courses/details/course_detail_provider.dart
library;

import 'package:flutter/cupertino.dart';

import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../../../../utils/helpers.dart';
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

  Future<void> fetchFull(String courseId) async {
    final r = await run(
          () => _api.get('/api/v1/courses/$courseId', auth: true),
    );
    if (r is Map<String, dynamic>) {
      course = CourseModel.fromJson(r);
      final reel = (r['reel_url'] as String?)?.trim();
      reelUrl = (reel == null || reel.isEmpty) ? null : reel;
    }
    await Future.wait([
      fetchSessions(courseId),
      if (course.isEnrolled) fetchMyCertificates(courseId),
    ]);
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

  // ── Pagination ────────────────────────────────────────────────────────────
  int _sessionsSkip = 0;
  bool _hasMoreSessions = true;
  static const _sessionsPageSize = 20;

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
  Future<void> fetchSessions(String courseId, {bool reset = true}) async {
    if (reset) {
      _sessionsSkip = 0;
      _hasMoreSessions = true;
      sessions = [];
      examGates.clear();
    }
    try {
      final result = await run(
            () => _api.get(
          '/api/v1/courses/$courseId/sessions',
          queryParams: {'skip': _sessionsSkip, 'limit': _sessionsPageSize},
        ),
      );
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
        _hasMoreSessions = page.length == _sessionsPageSize;
      }
      completedSessionIds.clear();
      completedSessionIds.addAll(
        sessions.where((e) => e.isCompleted).map((e) => e.id),
      );
    } on ApiException catch (e) {
      if (e.isDeviceBlocked) {
        // Screen listens to this and shows the device-blocked dialog.
        _deviceBlocked = true;
        notifyListeners();
        return;
      }
      Helpers.showMessage(e.message);
    } catch (e) {
      Helpers.showMessage(e.toString());
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
        '/api/v1/courses/${course.id}/sessions',
        queryParams: {'skip': 0, 'limit': limit},
      );
      if (result is Map && result['items'] is List) {
        final items = result['items'] as List;
        final fresh =
        items
            .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        examGates.clear();
        _storeGates(items);
        sessions = fresh;
        _sessionsSkip = fresh.length;
        _hasMoreSessions = fresh.length == limit;
        completedSessionIds
          ..clear()
          ..addAll(fresh.where((e) => e.isCompleted).map((e) => e.id));
        notifyListeners();
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

  // ── Premium / sequential unlock logic ────────────────────────────────────

  /// Whether the session at [index] (position within the sorted [sessions]
  /// list) is open for the current student.
  ///
  /// Rules:
  /// • Session 1 (index 0) is always open — it's the free preview.
  /// • Unenrolled students never get past session 1.
  /// • Enrolled students can open any later session UNLESS an exam attached
  ///   to an earlier session is still not passed (see [blockingExamFor]).
  ///   Sessions without an exam never block the next one.
  bool isSessionUnlocked(int index) {
    if (index < 0 || index >= sessions.length) return false;
    if (index == 0) return true;
    if (!course.isEnrolled) return false;
    return blockingExamFor(index) == null;
  }

  /// The first not-yet-passed exam attached to a session BEFORE [index]
  /// (null → no exam is blocking this session). Also drives the UI message.
  SessionExamInfo? blockingExamFor(int index) {
    for (var j = 0; j < index && j < sessions.length; j++) {
      final pending = examGates[sessions[j].id]?.firstPending;
      if (pending != null) return pending;
    }
    return null;
  }

  /// Same rule as [isSessionUnlocked] but looked up by session id — useful
  /// for widgets (e.g. the "live" tab) that only render a filtered subset
  /// of [sessions] and can't rely on their position in that subset.
  bool isSessionUnlockedById(int sessionId) {
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    return isSessionUnlocked(idx);
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
    if (c.isEnrolled) return;
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
    if (completedSessionIds.contains(sessionId)) return;
    completedSessionIds.add(sessionId);
    notifyListeners();

    final r = await run(
          () => _api.post('/api/v1/sessions/$sessionId/complete', auth: true),
    );

    if (r == null && hasError) {
      completedSessionIds.remove(sessionId);
      notifyListeners();
    } else {
      await _syncProgressFromServer();
    }
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
        course.progress = ((cr['progress'] as num?)?.toDouble() ?? 0.0).toInt();
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