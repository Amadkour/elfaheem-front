import 'package:flutter_education_app/features/teacher/home/teacher_provider.dart';

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../models.dart';

class StudentSessionsProvider extends BaseProvider {
  final ApiClient _api;

  StudentSessionsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<SessionModel> _sessions = [];
  final Map<int, bool> _checkedIn = {}; // sessionId → isCheckedIn

  List<SessionModel> get sessions => List.unmodifiable(_sessions);

  List<SessionModel> get liveSessions =>
      _sessions.where((s) => s.isLive).toList();

  List<SessionModel> get recordedSessions =>
      _sessions.where((s) => !s.isLive).toList();

  bool isCheckedIn(int sessionId) => _checkedIn[sessionId] ?? false;

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> fetchSessions(int courseId) async {
    final r = await run(
        () => _api.get('/api/v1/courses/$courseId/sessions', auth: true));
    if (r is List) {
      _sessions = r
          .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
    }
  }

  // ── Join live ─────────────────────────────────────────────────────────────

  /// Returns the personalised Daily.co meeting URL.
  Future<LiveResponseModel?> joinLive(int sessionId) async {
    final r =
        await run(() => _api.get('/api/v1/live-sessions/$sessionId/join'));
    if (r is Map<String, dynamic>) {
      final LiveResponseModel url = LiveResponseModel(
          sessionId: sessionId,
          url: r['ws_url'] as String? ?? '',
          token: r['token'] as String? ?? '');
      print("--------------------------------------------------------");
      print(url.toJson);
      print("--------------------------------------------------------");

      return url ;
    }
    return null;
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<String?> fetchRecordingUrl(int sessionId) async {
    final r =
        await run(() => _api.get('/api/v1/live-sessions/$sessionId/recording'));
    if (r is Map<String, dynamic>) {
      final url = r['recording_url'] as String?;
      if (url != null) {
        _sessions = _sessions
            .map((s) => s.id == sessionId
                ? (s..recordingUrl = url) // update local
                : s)
            .toList();
        notifyListeners();
      }
      return url;
    }
    return null;
  }

  // ── Progress tracking ─────────────────────────────────────────────────────

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
    final r = await run(() => _api.post('/api/v1/attendance/check-in',
        queryParams: {'session_id': sessionId}));
    if (r != null) {
      _checkedIn[sessionId] = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> checkOut(int sessionId) async {
    final r = await run(() => _api.post('/api/v1/attendance/check-out',
        queryParams: {'session_id': sessionId}));
    if (r != null) {
      _checkedIn[sessionId] = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Rating ────────────────────────────────────────────────────────────────

  Future<bool> rateSession(int sessionId, int value, {String? review}) async {
    final r = await run(() => _api.post('/api/v1/rates', body: {
          'source_id': sessionId,
          'type': 'session',
          'value': value,
          if (review != null) 'review': review
        }));
    return r != null;
  }
}
