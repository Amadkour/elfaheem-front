/// ─────────────────────────────────────────────────────────────────────────────
/// progress_provider.dart
/// POST /api/v1/views                              — save last watched position
/// POST /api/v1/views/{session_id}/complete        — mark session as completed
/// ─────────────────────────────────────────────────────────────────────────────

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class ViewProgress {
  final int  sessionId;
  final int  lastPosition; // seconds watched
  final bool isCompleted;

  const ViewProgress({
    required this.sessionId,
    required this.lastPosition,
    required this.isCompleted,
  });

  factory ViewProgress.fromJson(Map<String, dynamic> j) => ViewProgress(
        sessionId:    j['session_id']    as int,
        lastPosition: j['last_position'] as int? ?? 0,
        isCompleted:  j['is_completed']  as bool? ?? false,
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

class ProgressProvider extends BaseProvider {
  final ApiClient _api;

  ProgressProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── State ─────────────────────────────────────────────────────────────────────
  /// Local cache: sessionId → progress info
  final Map<int, ViewProgress> _progressMap = {};

  Map<int, ViewProgress> get progressMap => Map.unmodifiable(_progressMap);

  ViewProgress? progressFor(int sessionId) => _progressMap[sessionId];

  bool isCompleted(int sessionId) =>
      _progressMap[sessionId]?.isCompleted ?? false;

  // ── Track View ────────────────────────────────────────────────────────────────

  /// Call periodically (e.g. every 10 s) to save the student's position.
  /// [lastPosition] is the current playback position in seconds.
  Future<void> trackView({
    required int sessionId,
    int lastPosition = 0,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/views',
          body: {
            'session_id':    sessionId,
            'last_position': lastPosition,
          },
        ));

    if (result is Map<String, dynamic>) {
      _progressMap[sessionId] = ViewProgress.fromJson(result);
      notifyListeners();
    }
    // Update local cache optimistically even if response is bare
    _progressMap[sessionId] = ViewProgress(
      sessionId:    sessionId,
      lastPosition: lastPosition,
      isCompleted:  _progressMap[sessionId]?.isCompleted ?? false,
    );
    notifyListeners();
  }

  // ── Mark Completed ────────────────────────────────────────────────────────────

  Future<bool> markCompleted(int sessionId) async {
    final result = await run(
      () => _api.post('/api/v1/views/$sessionId/complete'),
    );

    if (result != null) {
      _progressMap[sessionId] = ViewProgress(
        sessionId:    sessionId,
        lastPosition: _progressMap[sessionId]?.lastPosition ?? 0,
        isCompleted:  true,
      );
      notifyListeners();
      return true;
    }
    return false;
  }
}
