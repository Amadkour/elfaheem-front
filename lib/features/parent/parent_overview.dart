// lib/features/parent/parent_overview.dart — the parent's "Today" tab data (Track B.5, D-062).
//
// ONE call, GET /api/v1/parent/overview, instead of config → requests → children → one profile per child on the
// first paint:
//   children[]   per linked child: the /parent/children row, today's dated events (calendar rows), attendance of
//                the last 30 days (0–100 | null), the 3 newest marks, the unread alerts, the nearest exam, the
//                number of active courses
//   alerts_total the unread alerts over every child · requests / link_config (= the Link tab's two calls)
// [ParentOverviewData.fromJson] is pure (test/org/parent_overview_test.dart); [ParentOverviewProvider] loads it.
// An older server answers a bare 404: [parentOverviewUnsupported] → `unsupported`, the dashboard hides the tab.
library;

import '../../config/app_config.dart';
import '../../core/api_client.dart';
import '../../core/base_provider.dart';

/// ISO string → UTC instant. A naive timestamp (no zone) is the server's UTC.
DateTime? parentUtc(dynamic v) {
  if (v == null) return null;
  final d = DateTime.tryParse('$v');
  if (d == null) return null;
  return d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond);
}

int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _double(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
String _str(dynamic v) => (v ?? '').toString();
List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

/// One dated event of a child's day (a row of GET /me/calendar: course session · timetable slot · exam · meeting).
class ParentEventRow {
  const ParentEventRow({
    this.id,
    this.source = '',
    required this.title,
    this.subtitle = '',
    this.startsAt,
    this.endsAt,
    this.courseId,
    this.kind = '',
    this.mode = '',
    this.location = '',
  });

  final int? id;
  final String source, title, subtitle, kind, mode, location;
  final DateTime? startsAt, endsAt;
  final int? courseId;

  factory ParentEventRow.fromJson(Map<String, dynamic> j) => ParentEventRow(
        id: _int(j['id']),
        source: _str(j['source']),
        title: _str(j['title']),
        subtitle: _str(j['subtitle']),
        startsAt: parentUtc(j['starts_at']),
        endsAt: parentUtc(j['ends_at']),
        courseId: _int(j['course_id']),
        kind: _str(j['kind']),
        mode: _str(j['mode']),
        location: _str(j['location']),
      );

  /// Minutes after midnight in the effective timezone (the agenda's "now" marker), or null.
  int? wallMinutes(DateTime Function(DateTime utc) toZone) {
    final s = startsAt;
    if (s == null) return null;
    final w = toZone(s);
    return w.hour * 60 + w.minute;
  }
}

/// One of the child's newest exam marks.
class ParentMark {
  const ParentMark({
    this.examId,
    required this.exam,
    this.courseId,
    this.courseAr = '',
    this.courseEn = '',
    this.percentage,
    this.passed,
    this.submittedAt,
  });

  final int? examId, courseId;
  final String exam, courseAr, courseEn;
  final double? percentage;
  final bool? passed;
  final DateTime? submittedAt;

  factory ParentMark.fromJson(Map<String, dynamic> j) => ParentMark(
        examId: _int(j['exam_id']),
        exam: _str(j['exam']),
        courseId: _int(j['course_id']),
        courseAr: _str(j['course_ar']),
        courseEn: _str(j['course_en']),
        percentage: _double(j['percentage']),
        passed: j['passed'] is bool ? j['passed'] as bool : null,
        submittedAt: parentUtc(j['submitted_at']),
      );

  /// The course name in the current language (falls back to the other one).
  String get course {
    final ar = AppConfig.lang.toString().toLowerCase().startsWith('ar');
    final first = ar ? courseAr : courseEn, second = ar ? courseEn : courseAr;
    return first.isNotEmpty ? first : second;
  }
}

/// The nearest upcoming exam: a published course exam or one of an organization's exam timetable.
class ParentNextExam {
  const ParentNextExam({this.id, required this.name, this.courseId, this.startsAt, this.endsAt, this.source = ''});

  final int? id, courseId;
  final String name, source;
  final DateTime? startsAt, endsAt;

  factory ParentNextExam.fromJson(Map<String, dynamic> j) => ParentNextExam(
        id: _int(j['id']),
        name: _str(j['name']),
        courseId: _int(j['course_id']),
        startsAt: parentUtc(j['starts_at']),
        endsAt: parentUtc(j['ends_at']),
        source: _str(j['source']),
      );
}

class ParentChildOverview {
  const ParentChildOverview({
    required this.id,
    required this.name,
    this.imageUrl = '',
    this.isActive = true,
    this.linkedAt,
    this.child = const {},
    this.todaySessions = const [],
    this.attendancePct30d,
    this.latestMarks = const [],
    this.openAlerts = 0,
    this.nextExam,
    this.courses = 0,
  });

  final int id;
  final String name, imageUrl;
  final bool isActive;
  final DateTime? linkedAt;

  /// The /parent/children row as sent — what the Children / Link tabs are seeded with.
  final Map<String, dynamic> child;
  final List<ParentEventRow> todaySessions;

  /// 0–100, null without a scheduled session in the window.
  final int? attendancePct30d;
  final List<ParentMark> latestMarks;
  final int openAlerts;
  final ParentNextExam? nextExam;
  final int courses;

  factory ParentChildOverview.fromJson(Map<String, dynamic> j) {
    final child = j['child'] is Map ? Map<String, dynamic>.from(j['child'] as Map) : <String, dynamic>{};
    return ParentChildOverview(
      id: _int(child['id']) ?? _int(j['id']) ?? 0,
      name: _str(child['name']),
      imageUrl: _str(child['image_url']),
      isActive: child['is_active'] != false,
      linkedAt: parentUtc(child['linked_at']),
      child: child,
      todaySessions: [for (final e in _maps(j['today_sessions'])) ParentEventRow.fromJson(e)]
        ..sort((a, b) => (a.startsAt ?? DateTime.utc(2100)).compareTo(b.startsAt ?? DateTime.utc(2100))),
      attendancePct30d: _int(j['attendance_pct_30d'])?.clamp(0, 100),
      latestMarks: [for (final m in _maps(j['latest_marks'])) ParentMark.fromJson(m)],
      openAlerts: _int(j['open_alerts']) ?? 0,
      nextExam: j['next_exam'] is Map ? ParentNextExam.fromJson(Map<String, dynamic>.from(j['next_exam'] as Map)) : null,
      courses: _int(j['courses']) ?? 0,
    );
  }
}

class ParentOverviewData {
  const ParentOverviewData({
    this.now,
    this.todayDate = '',
    this.timezone = '',
    this.children = const [],
    this.alertsTotal = 0,
    this.requests = const [],
    this.linkConfig = const {},
  });

  final DateTime? now;
  final String todayDate, timezone;
  final List<ParentChildOverview> children;
  final int alertsTotal;

  /// The parent's link requests (= GET /parent/link/requests) and the link config (= GET /parent/link/config).
  final List<Map<String, dynamic>> requests;
  final Map<String, dynamic> linkConfig;

  bool get hasChildren => children.isNotEmpty;
  int get pendingRequests => requests.where((r) => r['status'] == 'pending').length;
  int get sessionsToday => children.fold(0, (n, c) => n + c.todaySessions.length);

  factory ParentOverviewData.fromJson(Map<String, dynamic> j) => ParentOverviewData(
        now: parentUtc(j['now']),
        todayDate: _str(j['today_date']),
        timezone: _str(j['timezone']),
        children: [for (final c in _maps(j['children'])) ParentChildOverview.fromJson(c)],
        alertsTotal: _int(j['alerts_total']) ?? 0,
        requests: _maps(j['requests']),
        linkConfig: j['link_config'] is Map ? Map<String, dynamic>.from(j['link_config'] as Map) : const {},
      );
}

/// FastAPI's bare "Not Found" (or a 405): the route is not on this server → the Today tab is hidden.
bool parentOverviewUnsupported(ApiException e) =>
    e.statusCode == 405 || (e.statusCode == 404 && ApiException.asMap(e.body)?['detail'] == 'Not Found');

class ParentOverviewProvider extends BaseProvider {
  ParentOverviewProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  ParentOverviewData? data;

  /// The server has no /parent/overview (older server): nothing to show, the tab is hidden.
  bool unsupported = false;

  bool get loaded => data != null;

  /// Loads the overview; [silent] keeps the data on screen (no loading state) while it refreshes.
  Future<void> load({bool silent = false}) async {
    if (unsupported) return;
    final r = await run(
      () async {
        try {
          return await _api.get('/api/v1/parent/overview');
        } on ApiException catch (e) {
          if (parentOverviewUnsupported(e)) {
            unsupported = true;
            return null;
          }
          rethrow;
        }
      },
      makLoading: !silent || !loaded,
    );
    if (r is Map) {
      data = ParentOverviewData.fromJson(Map<String, dynamic>.from(r));
    }
    notifyListeners();
  }

  @override
  void reset() {
    data = null;
    super.reset();
  }
}
