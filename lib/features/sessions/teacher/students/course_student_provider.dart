import 'dart:async';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/design/app_username.dart' show usernameFrom;
import 'package:flutter_education_app/features/sessions/teacher/students/course_students_logic.dart';

export 'package:flutter_education_app/features/sessions/teacher/students/course_students_logic.dart';

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

  // ── D-870 – D-873 (null / 0 from an older server) ─────────────────────────
  final int lessonsDone;
  final int lessonsTotal;

  /// The last course activity (a finished lesson, an exam, any activity), UTC; null = never.
  final DateTime? lastActiveAt;

  /// The best percentage of each exam the student sat, averaged; null = no exam.
  final double? examAvg;

  /// completed | inactive | low | active | new (the server's rule, services/course_students_service.py).
  final String state;
  final bool atRisk;

  /// Why the student is at risk: never_started | no_activity | behind_pace | slow_start.
  final StudentRisk? risk;

  /// How many active linked parents (a count only, D-873).
  final int parentCount;
  final DateTime? lastNudgedAt;
  final bool canNudge;

  const EnrolledStudent({
    required this.id,
    required this.name,
    required this.gmail,
    this.imageUrl,
    required this.enrolledAt,
    required this.status,
    required this.progressPercentage,
    this.username,
    this.lessonsDone = 0,
    this.lessonsTotal = 0,
    this.lastActiveAt,
    this.examAvg,
    this.state = 'active',
    this.atRisk = false,
    this.risk,
    this.parentCount = 0,
    this.lastNudgedAt,
    this.canNudge = true,
  });

  factory EnrolledStudent.fromJson(Map<String, dynamic> j) => EnrolledStudent(
    id: (j['id'] as num).toInt(),
    name: '${j['name'] ?? ''}',
    gmail: '${j['gmail'] ?? ''}',
    imageUrl: j['image_url'] as String?,
    enrolledAt: '${j['enrolled_at'] ?? ''}',
    status: '${j['status'] ?? ''}',
    progressPercentage:
    (j['progress_percentage'] as num?)?.toDouble() ?? 0.0,
    username: usernameFrom(j),
    lessonsDone: (j['lessons_done'] as num?)?.toInt() ?? 0,
    lessonsTotal: (j['lessons_total'] as num?)?.toInt() ?? 0,
    lastActiveAt: parseServerUtc(j['last_active_at']),
    examAvg: (j['exam_avg'] as num?)?.toDouble(),
    state: '${j['state'] ?? ((j['progress_percentage'] as num? ?? 0) >= 100 ? 'completed' : 'active')}',
    atRisk: j['at_risk'] == true,
    risk: j['risk'] is Map ? StudentRisk.fromJson(Map<String, dynamic>.from(j['risk'] as Map)) : null,
    parentCount: (j['parent_count'] as num?)?.toInt() ?? 0,
    lastNudgedAt: parseServerUtc(j['last_nudged_at']),
    canNudge: j['can_nudge'] != false,
  );

  String get initials {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts.isNotEmpty ? parts[0][0].toUpperCase() : '?';
  }

  EnrolledStudent nudged(DateTime at) => EnrolledStudent(
    id: id, name: name, gmail: gmail, imageUrl: imageUrl, enrolledAt: enrolledAt, status: status,
    progressPercentage: progressPercentage, username: username, lessonsDone: lessonsDone, lessonsTotal: lessonsTotal,
    lastActiveAt: lastActiveAt, examAvg: examAvg, state: state, atRisk: atRisk, risk: risk, parentCount: parentCount,
    lastNudgedAt: at, canNudge: false,
  );
}

/// One page of `GET /courses/{id}/students` (D-870): the students, the counts per filter, the course-wide summary.
class CourseStudentsPage {
  const CourseStudentsPage({
    required this.items,
    required this.total,
    this.avgProgress = 0,
    this.completedCount = 0,
    this.summary,
    this.counts = const {},
    this.nudgeEnabled = false,
    this.cooldownHours = 24,
  });

  final List<EnrolledStudent> items;
  final int total;
  final double avgProgress;
  final int completedCount;

  /// Null from an older server (the page then builds one from [total] / [avgProgress] / [completedCount]).
  final CourseStudentsSummary? summary;
  final Map<StudentFilter, int> counts;

  /// False from an older server (no nudge there) or with the kill switch `course_students.nudge` off.
  final bool nudgeEnabled;
  final int cooldownHours;

  factory CourseStudentsPage.fromJson(Map<String, dynamic> j) {
    final items = [
      for (final e in (j['items'] as List? ?? const []).whereType<Map>()) EnrolledStudent.fromJson(Map<String, dynamic>.from(e)),
    ];
    final counts = j['counts'] is Map ? Map<String, dynamic>.from(j['counts'] as Map) : const <String, dynamic>{};
    return CourseStudentsPage(
      items: items,
      total: (j['total'] as num?)?.toInt() ?? items.length,
      avgProgress: (j['avg_progress'] as num?)?.toDouble() ?? 0,
      completedCount: (j['completed_count'] as num?)?.toInt() ?? 0,
      summary: j['summary'] is Map ? CourseStudentsSummary.fromJson(Map<String, dynamic>.from(j['summary'] as Map)) : null,
      counts: {
        for (final f in StudentFilter.values)
          if (counts[f.wire] is num) f: (counts[f.wire] as num).toInt(),
      },
      nudgeEnabled: j['nudge_enabled'] == true,
      cooldownHours: ((j['rule'] as Map?)?['nudge_cooldown_hours'] as num?)?.toInt() ?? 24,
    );
  }
}

/// The summary an older server's page allows: enrolled, average and completed only.
extension CourseStudentsSummaryFallback on CourseStudentsSummary {
  static CourseStudentsSummary of(CourseStudentsPage p) =>
      CourseStudentsSummary(enrolled: p.total, avgProgress: p.avgProgress, completed: p.completedCount);
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

  /// Total enrolled students matching the current search AND filter, as reported by the server — not just how many
  /// pages we've loaded so far.
  int get totalCount => _totalCount;

  /// Average progress across the *entire* search set (not just the page(s) loaded so far).
  double get avgProgress => _avgProgress;

  /// Completed-count across the entire search set, same reasoning as [avgProgress].
  int get completedCount => _completedCount;

  // ── D-870 – D-873: the course-wide summary, one filter, one sort, the selection, the nudge ──────────────────────
  CourseStudentsSummary _summary = const CourseStudentsSummary();
  Map<StudentFilter, int> _counts = const {};
  StudentFilter _filter = StudentFilter.all;
  StudentSort _sort = StudentSort.name;
  bool _nudgeEnabled = true;
  int _cooldownHours = 24;
  bool _loadedOnce = false;
  final Set<int> _selected = {};
  bool _nudging = false;
  int _seq = 0;

  CourseStudentsSummary get summary => _summary;
  int countOf(StudentFilter f) => _counts[f] ?? (f == StudentFilter.all ? _totalCount : 0);
  StudentFilter get filter => _filter;
  StudentSort get sort => _sort;
  String get query => _query;

  /// The server answered the nudge as available (the kill switch `course_students.nudge`); the UI hides it otherwise.
  bool get nudgeEnabled => _nudgeEnabled;
  int get cooldownHours => _cooldownHours;

  /// True once a page has arrived (the summary is real, not zeros).
  bool get loadedOnce => _loadedOnce;
  Set<int> get selected => Set.unmodifiable(_selected);
  bool get selecting => _selected.isNotEmpty;
  bool get isNudging => _nudging;

  /// The loaded students of the selection (a selection only holds loaded rows).
  List<EnrolledStudent> get selectedStudents => [for (final s in _all) if (_selected.contains(s.id)) s];

  void toggleSelected(int id) {
    if (!_selected.remove(id)) _selected.add(id);
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  void setFilter(StudentFilter f) {
    if (f == _filter) return;
    _filter = f;
    notifyListeners();
    final courseId = _courseId;
    if (courseId != null) fetch(courseId, reset: true);
  }

  void setSort(StudentSort s) {
    if (s == _sort) return;
    _sort = s;
    notifyListeners();
    final courseId = _courseId;
    if (courseId != null) fetch(courseId, reset: true);
  }

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

  Map<String, dynamic> _params(int skip, int limit) => {
        'skip': skip,
        'limit': limit,
        if (_query.isNotEmpty) 'search': _query,
        if (_filter != StudentFilter.all) 'filter': _filter.wire,
        if (_sort != StudentSort.name) 'sort': _sort.wire,
      };

  /// Fetches page 1 fresh (used on pull-to-refresh / first open / search).
  /// Pass [reset]=false to append the next page instead (see [loadMore]).
  Future<void> fetch(int courseId, {bool reset = true}) async {
    _courseId = courseId;
    // a reset keeps the cards on screen until the new page arrives (no skeleton flash on a filter / sort / search)
    if (reset) {
      _skip = 0;
      _hasMore = true;
      _selected.clear();
    }
    final seq = ++_seq;
    final result = await run(() => _api.get('/api/v1/courses/$courseId/students', queryParams: _params(_skip, _pageSize)));
    if (seq != _seq) return; // a newer search / filter answered (or will answer) instead
    if (result is Map && result['items'] is List) {
      final page = CourseStudentsPage.fromJson(Map<String, dynamic>.from(result));
      _all = reset ? page.items : [..._all, ...page.items];
      _skip += page.items.length;
      _totalCount = page.total;
      _avgProgress = page.avgProgress;
      _completedCount = page.completedCount;
      _summary = page.summary ?? CourseStudentsSummaryFallback.of(page);
      _counts = page.counts;
      _nudgeEnabled = page.nudgeEnabled;
      _cooldownHours = page.cooldownHours;
      _hasMore = page.items.length == _pageSize;
      _loadedOnce = true;
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

  /// Every student of the current search / filter / sort in one call (the export), or null when it failed.
  Future<List<EnrolledStudent>?> fetchAll() async {
    final courseId = _courseId;
    if (courseId == null) return null;
    try {
      final r = await _api.get('/api/v1/courses/$courseId/students', queryParams: _params(0, 2000));
      if (r is Map && r['items'] is List) return CourseStudentsPage.fromJson(Map<String, dynamic>.from(r)).items;
    } catch (_) {/* the caller says it failed */}
    return null;
  }

  /// Sends the nudge (D-873): [ids] or every low-progress student ([allLow]); the cards that went out show
  /// "Nudged just now" at once and the page reloads for the server's figures. Throws [ApiException] (429
  /// `nudged_recently`, 403 …) for the caller's notice.
  Future<NudgeResult> nudge({List<int> ids = const [], bool allLow = false, required String message, required bool parents}) async {
    final courseId = _courseId;
    if (courseId == null) return const NudgeResult();
    _nudging = true;
    notifyListeners();
    try {
      final r = await _api.post('/api/v1/courses/$courseId/students/nudge', body: {
        if (allLow) 'all_low': true else 'student_ids': ids,
        'message': message,
        'notify_parents': parents,
        'lang': AppConfig.lang,
      });
      final res = NudgeResult.fromJson(r is Map ? Map<String, dynamic>.from(r) : const {});
      final skipped = {for (final s in res.skipped) s.studentId};
      final at = res.nudgedAt ?? DateTime.now().toUtc();
      _all = [
        for (final s in _all)
          (allLow ? s.atRisk && s.canNudge : ids.contains(s.id)) && !skipped.contains(s.id) ? s.nudged(at) : s,
      ];
      _selected.clear();
      return res;
    } finally {
      _nudging = false;
      notifyListeners();
      unawaited(fetch(courseId, reset: true));
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
