/// ─────────────────────────────────────────────────────────────────────────────
/// ratings_provider.dart
/// POST /api/v1/rates                                — create rating (1-5)
/// GET  /api/v1/courses/{course_id}/ratings          — course ratings list
/// GET  /api/v1/sessions/{session_id}/ratings        — session ratings list
/// ─────────────────────────────────────────────────────────────────────────────
library;

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class RatingModel {
  final int     id;
  final int     sourceId;   // course_id or session_id
  final String  type;       // 'course' | 'session'
  final int     value;      // 1–5
  final String? review;
  final int?    studentId;
  final String? studentName;
  final String? createdAt;

  const RatingModel({
    required this.id,
    required this.sourceId,
    required this.type,
    required this.value,
    this.review,
    this.studentId,
    this.studentName,
    this.createdAt,
  });

  factory RatingModel.fromJson(Map<String, dynamic> j) => RatingModel(
        id:          j['id']           as int,
        sourceId:    j['source_id']    as int,
        type:        j['type']         as String,
        value:       j['value']        as int,
        review:      j['review']       as String?,
        studentId:   j['student_id']   as int?,
        studentName: j['student']?['name'] as String?,
        createdAt:   j['created_at']   as String?,
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

class RatingsProvider extends BaseProvider {
  final ApiClient _api;

  RatingsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── State ────────────────────────────────────────────────────────────────────
  List<RatingModel> _courseRatings  = [];
  List<RatingModel> _sessionRatings = [];

  List<RatingModel> get courseRatings  => List.unmodifiable(_courseRatings);
  List<RatingModel> get sessionRatings => List.unmodifiable(_sessionRatings);

  /// Average of [courseRatings], or 0 if empty.
  double get courseAverage => _courseRatings.isEmpty
      ? 0
      : _courseRatings.map((r) => r.value).reduce((a, b) => a + b) /
            _courseRatings.length;

  /// Average of [sessionRatings], or 0 if empty.
  double get sessionAverage => _sessionRatings.isEmpty
      ? 0
      : _sessionRatings.map((r) => r.value).reduce((a, b) => a + b) /
            _sessionRatings.length;

  // ── Rate ──────────────────────────────────────────────────────────────────────

  /// [type] = 'course' | 'session'
  /// [value] must be 1–5.
  Future<bool> rate({
    required int    sourceId,
    required String type,
    required int    value,
    String? review,
  }) async {
    assert(value >= 1 && value <= 5, 'Rating value must be between 1 and 5');
    final result = await run(() => _api.post(
          '/api/v1/rates',
          body: {
            'source_id': sourceId,
            'type':      type,
            'value':     value,
            if (review != null) 'review': review,
          },
        ));

    if (result != null) {
      // Optimistically reload the relevant ratings list
      if (type == 'course') {
        await fetchCourseRatings(sourceId);
      } else {
        await fetchSessionRatings(sourceId);
      }
      return true;
    }
    return false;
  }

  // ── Course Ratings ────────────────────────────────────────────────────────────

  Future<void> fetchCourseRatings(
    int courseId, {
    int skip  = 0,
    int limit = 20,
  }) async {
    final result = await run(() => _api.get(
          '/api/v1/courses/$courseId/ratings',
          queryParams: {'skip': skip, 'limit': limit},
          auth: false,
        ));

    if (result is List) {
      _courseRatings = result
          .map((e) => RatingModel.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    }
  }

  // ── Session Ratings ───────────────────────────────────────────────────────────

  Future<void> fetchSessionRatings(
    int sessionId, {
    int skip  = 0,
    int limit = 20,
  }) async {
    final result = await run(() => _api.get(
          '/api/v1/sessions/$sessionId/ratings',
          queryParams: {'skip': skip, 'limit': limit},
          auth: false,
        ));

    if (result is List) {
      _sessionRatings = result
          .map((e) => RatingModel.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    }
  }
}
