/// courses/details/course_detail_provider.dart
library;

import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../../models.dart';

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

  CourseDetailTab get activeTab => _activeTab;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init(CourseModel c) async {
    course = c;
    makeLoading();
    // Run sessions + optional progress fetch in parallel for speed
    await Future.wait([
      fetchSessions(c.id),
     // fetchProgress(c.id),
    ]);
    stopLoading();
  }

  // ── Course data ───────────────────────────────────────────────────────────

  Future<void> fetchFull(String courseId) async {
    final r =
    await run(() => _api.get('/api/v1/courses/$courseId', auth: true));
    if (r is Map<String, dynamic>) {
      course = CourseModel.fromJson(r);
      notifyListeners();
    }
  }

  Future<void> fetchSessions(String courseId) async {
    final result =
    await run(() => _api.get('/api/v1/courses/$courseId/sessions'));
    if (result is List) {
      course.sessions = result
          .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
    }
  }

  Future<void> refresh() => fetchFull(course.id);

  void setTab(CourseDetailTab tab) {
    if (_activeTab == tab) return;
    _activeTab = tab;
    notifyListeners();
  }

  Future<void> toggleFavorite() async {
    final was = course.isFavorite;
    course = course.copyWith(isFavorite: !was);
    notifyListeners();
    final r = was
        ? await run(() => _api.delete('/api/v1/courses/${course.id}/favorite'))
        : await run(() => _api.post('/api/v1/courses/${course.id}/favorite'));
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

  // ── Student progress ──────────────────────────────────────────────────────

  /// Fetches the full per-session / per-material breakdown from the backend
  /// and updates [progressPercentage], [completedMaterialIds],
  /// [completedSessionIds] in one shot.
  ///
  /// Endpoint: GET /api/v1/courses/{courseId}/my-progress
  // Future<void> fetchProgress(String courseId) async {
  //   final r = await run(
  //           () => _api.get('/api/v1/courses/$courseId/my-progress', auth: true));
  //   if (r is Map<String, dynamic>) {
  //     progressPercentage =
  //         (r['overall_percentage'] as num?)?.toDouble() ?? 0.0;
  //
  //     completedMaterialIds.clear();
  //     completedSessionIds.clear();
  //
  //     final sessions = r['sessions'] as List? ?? [];
  //     for (final s in sessions) {
  //       final sMap = s as Map<String, dynamic>;
  //       if (sMap['is_session_complete'] == true) {
  //         completedSessionIds.add(sMap['session_id'] as int);
  //       }
  //       final materials = sMap['materials'] as List? ?? [];
  //       for (final m in materials) {
  //         final mMap = m as Map<String, dynamic>;
  //         if (mMap['is_completed'] == true) {
  //           completedMaterialIds.add(mMap['material_id'] as int);
  //         }
  //       }
  //     }
  //     notifyListeners();
  //   }
  // }

  // ── Student material completion ───────────────────────────────────────────

  /// Called when a student finishes a material (video end / image dismiss /
  /// PDF-link open). Updates local state immediately for instant UI feedback,
  /// then persists to the backend.
  ///
  /// Endpoint: POST /api/v1/sessions/{sessionId}/materials/{materialId}/complete
  Future<void> markMaterialComplete(int sessionId, int materialId) async {
    // Optimistic local update so the ✓ badge appears instantly
    if (completedMaterialIds.contains(materialId)) return; // already done
    completedMaterialIds.add(materialId);
    notifyListeners();

    final r = await run(() => _api.post(
      '/api/v1/sessions/$sessionId/materials/$materialId/complete',
      auth: true,
    ));

    // If the server rejected it, roll back the optimistic update
    if (r == null && hasError) {
      completedMaterialIds.remove(materialId);
      course.materialsCompleted+=1;
      course.progress+=(course.materialsCompleted)/course.materialsTotal;
      notifyListeners();
    }
  }

  // ── Student session (live) completion ─────────────────────────────────────

  /// Called automatically when a student leaves the LiveKit room.
  /// Endpoint: POST /api/v1/sessions/{sessionId}/complete
  Future<void> markSessionComplete(int sessionId) async {
    if (completedSessionIds.contains(sessionId)) return;
    completedSessionIds.add(sessionId);
    notifyListeners();

    final r = await run(() => _api.post(
      '/api/v1/sessions/$sessionId/complete',
      auth: true,
    ));

    if (r == null && hasError) {
      completedSessionIds.remove(sessionId);

      course.materialsCompleted+=1;
      course.progress+=(course.materialsCompleted)/course.materialsTotal;
      notifyListeners();
    }
  }

  // ── Student live-session join ─────────────────────────────────────────────

  /// Fetches the student's personal join token for an already-active
  /// live session.
  /// Endpoint: GET /api/v1/live-sessions/{sessionId}/join
  /// Returns a [LiveJoinResponse] (url + token) or null on error.
  Future<Map<String, dynamic>?> fetchStudentJoinToken(int sessionId) async {
    final r = await run(
            () => _api.get('/api/v1/live-sessions/$sessionId/join', auth: true));
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