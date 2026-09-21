// lib/features/student/sessions/sessions_provider.dart
// ─────────────────────────────────────────────────────
// Student sessions provider — now includes material fetching and
// server-side pagination of the course's session list.


import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../teacher/sessions/model/live_response_model.dart';
import '../../shared/session/material/session_material_model.dart';
import '../models.dart';

class StudentSessionsProvider extends BaseProvider {
  final ApiClient _api;

  StudentSessionsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<SessionModel> _sessions = [];
  final Map<int, bool> _checkedIn = {};
  // materials per session (loaded on expand / detail open)
  final Map<int, List<SessionMaterialModel>> _materials = {};

  // ── Pagination ────────────────────────────────────────────────────────────
  int? _courseId;
  int _skip = 0;
  bool _hasMore = true;
  static const _pageSize = 20;

  bool get hasMore => _hasMore;

  /// True only while fetching another page onto an already-populated list —
  /// distinct from the initial-load spinner, so the UI can show a small
  /// footer loader instead of blanking the whole list.
  bool get isLoadingMore => isLoading && _sessions.isNotEmpty;

  List<SessionModel> get sessions => List.unmodifiable(_sessions);
  List<SessionModel> get liveSessions     => _sessions.where((s) => s.isLive).toList();
  List<SessionModel> get recordedSessions => _sessions.where((s) => !s.isLive).toList();

  bool isCheckedIn(int sessionId) => _checkedIn[sessionId] ?? false;
  List<SessionMaterialModel> materialsFor(int sessionId) =>
      List.unmodifiable(_materials[sessionId] ?? []);

  // ── Fetch sessions ────────────────────────────────────────────────────────

  /// Fetches page 1 fresh (used on pull-to-refresh / first open).
  /// Pass [reset]=false to append the next page instead (see [loadMoreSessions]).
  Future<void> fetchSessions(int courseId, {bool reset = true}) async {
    _courseId = courseId;
    if (reset) {
      _skip = 0;
      _hasMore = true;
      _sessions = [];
    }
    final r = await run(() => _api.get('/api/v1/courses/$courseId/sessions',
        auth: true, queryParams: {'skip': _skip, 'limit': _pageSize}));
    if (r is Map && r['items'] is List) {
      final page = (r['items'] as List)
          .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      _sessions = [..._sessions, ...page];
      _skip += page.length;
      _hasMore = page.length == _pageSize;
      notifyListeners();
    }
  }

  /// Fetches the next page and appends it. No-ops while a fetch is already
  /// in flight, once the server has told us there's nothing more, or before
  /// the first [fetchSessions] call has set a course.
  Future<void> loadMoreSessions() async {
    final courseId = _courseId;
    if (!_hasMore || isLoading || courseId == null) return;
    await fetchSessions(courseId, reset: false);
  }

  // ── Materials ─────────────────────────────────────────────────────────────

  Future<void> fetchMaterials(int sessionId) async {
    final r = await run(() => _api.get('/api/v1/sessions/$sessionId/materials', auth: true));
    if (r is List) {
      _materials[sessionId] = r
          .map((e) => SessionMaterialModel.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    }
  }

  // ── Join live ─────────────────────────────────────────────────────────────

  Future<LiveResponseModel?> joinLive(int sessionId) async {
    final r = await run(() => _api.get('/api/v1/live-sessions/$sessionId/join'));
    if (r is Map<String, dynamic>) {
      return LiveResponseModel(
        sessionId: sessionId,
        url:   r['ws_url']  as String? ?? '',
        token: r['token']   as String? ?? '',
      );
    }
    return null;
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<String?> fetchRecordingUrl(int sessionId) async {
    final r = await run(() => _api.get('/api/v1/live-sessions/$sessionId/recording'));
    if (r is Map<String, dynamic>) {
      final url = r['recording_url'] as String?;
      if (url != null) {
        _sessions = _sessions
            .map((s) => s.id == sessionId ? (s..recordingUrl = url) : s)
            .toList();
        notifyListeners();
      }
      return url;
    }
    return null;
  }

  // ── Progress ──────────────────────────────────────────────────────────────

  Future<void> trackView(int sessionId, {int lastPosition = 0}) async {
    await run(() => _api.post('/api/v1/views',
        body: {'session_id': sessionId, 'last_position': lastPosition}));
  }

  Future<bool> markComplete(int sessionId) async {
    final r = await run(() => _api.post('/api/v1/views/$sessionId/complete'));
    if (r != null) {
      _sessions = _sessions
          .map((s) => s.id == sessionId ? s.copyWith(isCompleted: true) : s)
          .toList();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Attendance ────────────────────────────────────────────────────────────

  Future<bool> checkIn(int sessionId) async {
    final r = await run(() =>
        _api.post('/api/v1/attendance/check-in', queryParams: {'session_id': sessionId}));
    if (r != null) { _checkedIn[sessionId] = true; notifyListeners(); return true; }
    return false;
  }

  Future<bool> checkOut(int sessionId) async {
    final r = await run(() =>
        _api.post('/api/v1/attendance/check-out', queryParams: {'session_id': sessionId}));
    if (r != null) { _checkedIn[sessionId] = false; notifyListeners(); return true; }
    return false;
  }

  // ── Rating ────────────────────────────────────────────────────────────────

  Future<bool> rateSession(int sessionId, int value, {String? review}) async {
    final r = await run(() => _api.post('/api/v1/rates', body: {
    'source_id': sessionId,
    'type': 'session',
    'value': value,
    'review': ?review,
    }));
    return r != null;
  }
}