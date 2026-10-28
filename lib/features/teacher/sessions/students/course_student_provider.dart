import 'dart:async';

import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../../../../design/app_username.dart' show usernameFrom;

class EnrolledStudent {
  final int id;
  final String name;
  final String gmail;
  final String? imageUrl;
  final String enrolledAt;
  final String status;
  final double progressPercentage;

  /// The student's @username (without "@"); null when none or an older server (D-071 v2).
  final String? username;

  const EnrolledStudent({
    required this.id,
    required this.name,
    required this.gmail,
    this.imageUrl,
    required this.enrolledAt,
    required this.status,
    required this.progressPercentage,
    this.username,
  });

  factory EnrolledStudent.fromJson(Map<String, dynamic> j) => EnrolledStudent(
    id: j['id'] as int,
    name: j['name'] as String,
    gmail: j['gmail'] as String,
    imageUrl: j['image_url'] as String?,
    enrolledAt: j['enrolled_at'] as String,
    status: j['status'] as String,
    progressPercentage:
    (j['progress_percentage'] as num?)?.toDouble() ?? 0.0,
    username: usernameFrom(j),
  );

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class EnrolledStudentsProvider extends BaseProvider {
  final ApiClient _api;

  EnrolledStudentsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<EnrolledStudent> _all = [];
  String _query = '';
  int? _courseId;

  // ── Pagination (search runs server-side, so the loaded page(s) ARE the
  // current result set — no client-side filtering needed) ────────────────
  int _skip = 0;
  bool _hasMore = true;
  int _totalCount = 0;
  double _avgProgress = 0;
  int _completedCount = 0;
  static const _pageSize = 20;
  Timer? _searchDebounce;

  bool get hasMore => _hasMore;

  /// True only while fetching another page onto an already-populated list —
  /// distinct from the initial-load spinner, so the UI can show a small
  /// footer loader instead of blanking the whole list.
  bool get isLoadingMore => isLoading && _all.isNotEmpty;

  // ── Certificate issuance state ──────────────────────────────────────────
  // Keyed by "certificateId:studentId" so a course with multiple
  // certificates tracks each student's status per-certificate.
  // The value is how many times it has been sent, so the UI can show
  // "sent 2×" and still allow re-sending.
  final Map<String, int> _issuedCounts = {};
  String? _sendingKey;
  int? _bulkCertificateId;

  String _key(int certificateId, int studentId) => '$certificateId:$studentId';

  bool isCertificateIssued(int certificateId, int studentId) =>
      issuedCount(certificateId, studentId) > 0;

  /// How many times this certificate has been sent to this student.
  int issuedCount(int certificateId, int studentId) =>
      _issuedCounts[_key(certificateId, studentId)] ?? 0;

  /// True while a "send to all" request is running for this certificate.
  bool isSendingToAll(int certificateId) => _bulkCertificateId == certificateId;

  /// True while ANY bulk send is running (used to disable other buttons).
  bool get isBulkSending => _bulkCertificateId != null;

  bool isSendingCertificate(int certificateId, int studentId) =>
      _sendingKey == _key(certificateId, studentId);

  /// Call once with the course's certificate ids (e.g. from
  /// `course.certificates.map((c) => c.id)`) to pre-mark students who
  /// already received one, so the button shows "sent" instead of "send".
  Future<void> loadIssuedForCertificates(List<int> certificateIds) async {
    _issuedCounts.clear(); // rebuilt from the server, so refresh doesn't double count
    for (final certId in certificateIds) {
      final result = await run(() => _api.get('/api/v1/certificates/$certId/issuances'));
      if (result is List) {
        for (final row in result.whereType<Map<String, dynamic>>()) {
          final studentId = row['student_id'] as int?;
          if (studentId != null) _bump(certId, studentId);
        }
      }
    }
    notifyListeners();
  }

  /// Generates + emails the certificate to this student.
  /// Returns true on success (and marks the student as "sent").
  Future<bool> sendCertificate(int certificateId, int studentId) async {
    _sendingKey = _key(certificateId, studentId);
    notifyListeners();

    final result = await run(
          () => _api.post('/api/v1/certificates/$certificateId/issue', body: {'student_id': studentId}),
    );

    _sendingKey = null;
    final success = result is Map<String, dynamic>;
    if (success) _bump(certificateId, studentId);
    notifyListeners();
    return success;
  }

  void _bump(int certificateId, int studentId) {
    final k = _key(certificateId, studentId);
    _issuedCounts[k] = (_issuedCounts[k] ?? 0) + 1;
  }

  /// Generates + emails the certificate to EVERY enrolled student in one
  /// request (server: POST /certificates/{id}/issue-all).
  /// Returns how many students it was sent to, or -1 on failure.
  Future<int> sendCertificateToAll(int certificateId) async {
    _bulkCertificateId = certificateId;
    notifyListeners();

    final result = await run(
          () => _api.post('/api/v1/certificates/$certificateId/issue-all', body: const {}),
    );

    _bulkCertificateId = null;
    var sent = -1;
    if (result is List) {
      sent = 0;
      for (final row in result.whereType<Map<String, dynamic>>()) {
        final studentId = row['student_id'] as int?;
        if (studentId != null) {
          _bump(certificateId, studentId);
          sent++;
        }
      }
    }
    notifyListeners();
    return sent;
  }

  List<EnrolledStudent> get students => List.unmodifiable(_all);

  /// Total enrolled students matching the current search, as reported by
  /// the server — not just how many pages we've loaded so far.
  int get totalCount => _totalCount;

  /// Average progress across the *entire* matching set (not just the
  /// page(s) loaded so far) — reported by the server alongside each page.
  double get avgProgress => _avgProgress;

  /// Completed-count across the entire matching set, same reasoning as
  /// [avgProgress].
  int get completedCount => _completedCount;

  /// Debounced server-side search — re-fetches page 1 with the new query
  /// shortly after the user stops typing, rather than filtering the
  /// (partial) loaded list on the client.
  void setQuery(String q) {
    _query = q;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final courseId = _courseId;
      if (courseId != null) fetch(courseId, reset: true);
    });
  }

  /// Fetches page 1 fresh (used on pull-to-refresh / first open / search).
  /// Pass [reset]=false to append the next page instead (see [loadMore]).
  Future<void> fetch(int courseId, {bool reset = true}) async {
    _courseId = courseId;
    if (reset) {
      _skip = 0;
      _hasMore = true;
      _all = [];
    }
    final result = await run(() => _api.get(
      '/api/v1/courses/$courseId/students',
      queryParams: {
        'skip': _skip,
        'limit': _pageSize,
        if (_query.isNotEmpty) 'search': _query,
      },
    ));
    if (result is Map && result['items'] is List) {
      final page = (result['items'] as List)
          .map((e) => EnrolledStudent.fromJson(e as Map<String, dynamic>))
          .toList();
      _all = [..._all, ...page];
      _skip += page.length;
      _totalCount = (result['total'] as num?)?.toInt() ?? _all.length;
      _avgProgress = (result['avg_progress'] as num?)?.toDouble() ?? 0;
      _completedCount = (result['completed_count'] as num?)?.toInt() ?? 0;
      _hasMore = page.length == _pageSize;
      notifyListeners();
    }
  }

  /// Fetches the next page and appends it. No-ops while a fetch is already
  /// in flight, once the server has told us there's nothing more, or before
  /// the first [fetch] call has set a course.
  Future<void> loadMore() async {
    final courseId = _courseId;
    if (!_hasMore || isLoading || courseId == null) return;
    await fetch(courseId, reset: false);
  }
}