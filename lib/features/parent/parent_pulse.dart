// lib/features/parent/parent_pulse.dart — "How is my child doing?" (D-305), the `pulse` block of each child row of
// GET /api/v1/parent/overview (services/parent_pulse_service.py on the server):
//
//   status            on_track · watch · needs_you · quiet
//   week              the last 7 days: scheduled / attended / missed sessions, homework missing / due soon, active days
//   attendanceTrend   6 rolling weeks (0–100 | null), oldest first
//   grades            the last 28 days vs the 28 before, the class average (aggregates of exams with >= 5 results)
//   subjects          per course: average · class average · missed · weak answers · tone (strength / focus / steady)
//   upcoming          the next 7 days (calendar rows)            roadmap   the child's learning path
//   insights          <= 4 plain-language findings, each with an optional action (message the teacher, report, alerts)
//   teachers          who the parent may message (POST /parent/children/{id}/message-teacher, [ParentPulseApi])
//
// Pure parsing (test/org/parent_pulse_test.dart). An older server (no `pulse`) or the kill switch `parent.insights`
// (`pulse: null`) → [ParentChildOverview.pulse] is null and the home keeps the per-child cards.
library;

import '../../config/app_config.dart';
import '../../core/api_client.dart';
import 'parent_overview.dart' show ParentEventRow, parentUtc;

int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _double(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
String _str(dynamic v) => (v ?? '').toString();
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

bool get _ar => AppConfig.lang.toString().toLowerCase().startsWith('ar');

/// [ar] / [en] in the current language, falling back to the other one.
String pulseName(String ar, String en) {
  final first = _ar ? ar : en, second = _ar ? en : ar;
  return first.isNotEmpty ? first : second;
}

enum PulseStatus {
  onTrack('on_track'),
  watch('watch'),
  needsYou('needs_you'),
  quiet('quiet');

  const PulseStatus(this.wire);
  final String wire;

  static PulseStatus parse(dynamic v) => PulseStatus.values.firstWhere((s) => s.wire == '$v', orElse: () => quiet);
}

class PulseWeek {
  const PulseWeek({
    this.scheduled = 0,
    this.attended = 0,
    this.missed = 0,
    this.rate,
    this.homeworkDue = 0,
    this.homeworkMissing = 0,
    this.homeworkDueSoon = 0,
    this.activeDays = 0,
    this.lastActiveDays,
  });

  final int scheduled, attended, missed, homeworkDue, homeworkMissing, homeworkDueSoon, activeDays;
  final int? rate, lastActiveDays;

  factory PulseWeek.fromJson(Map<String, dynamic> j) => PulseWeek(
        scheduled: _int(j['scheduled']) ?? 0,
        attended: _int(j['attended']) ?? 0,
        missed: _int(j['missed']) ?? 0,
        rate: _int(j['rate'])?.clamp(0, 100),
        homeworkDue: _int(j['homework_due']) ?? 0,
        homeworkMissing: _int(j['homework_missing']) ?? 0,
        homeworkDueSoon: _int(j['homework_due_soon']) ?? 0,
        activeDays: _int(j['active_days']) ?? 0,
        lastActiveDays: _int(j['last_active_days']),
      );
}

class PulseMissed {
  const PulseMissed({required this.session, this.courseId, this.courseAr = '', this.courseEn = '', this.at});
  final String session, courseAr, courseEn;
  final int? courseId;
  final DateTime? at;

  String get course => pulseName(courseAr, courseEn);

  factory PulseMissed.fromJson(Map<String, dynamic> j) => PulseMissed(
        session: _str(j['session']),
        courseId: _int(j['course_id']),
        courseAr: _str(j['course_ar']),
        courseEn: _str(j['course_en']),
        at: parentUtc(j['at']),
      );
}

class PulseGrades {
  const PulseGrades({this.avg, this.prevAvg, this.classAvg, this.mineVsClass, this.count = 0, this.failed = 0, this.trend = const []});

  /// The child's average of the last 28 days, of the 28 before, and the class average over the exams that have one
  /// ([mineVsClass] = the child's average over those same exams, the fair comparison).
  final double? avg, prevAvg, classAvg, mineVsClass;
  final int count, failed;

  /// 6 weekly averages, oldest first (null = no mark that week).
  final List<double?> trend;

  /// avg − the 28 days before, or null.
  double? get delta => avg == null || prevAvg == null ? null : avg! - prevAvg!;

  factory PulseGrades.fromJson(Map<String, dynamic> j) => PulseGrades(
        avg: _double(j['avg']),
        prevAvg: _double(j['prev_avg']),
        classAvg: _double(j['class_avg']),
        mineVsClass: _double(j['mine_vs_class']),
        count: _int(j['count']) ?? 0,
        failed: _int(j['failed']) ?? 0,
        trend: [for (final p in _maps(j['trend'])) _double(p['avg'])],
      );
}

class PulsePerson {
  const PulsePerson({required this.id, required this.name, this.imageUrl = ''});
  final int id;
  final String name, imageUrl;

  static PulsePerson? tryParse(dynamic v) {
    final j = _map(v);
    final id = _int(j['id']);
    return id == null ? null : PulsePerson(id: id, name: _str(j['name']), imageUrl: _str(j['image_url']));
  }
}

class PulseSubject {
  const PulseSubject({
    required this.courseId,
    this.nameAr = '',
    this.nameEn = '',
    this.progress = 0,
    this.avg,
    this.classAvg,
    this.missed = 0,
    this.weakOpen = 0,
    this.tone = 'steady',
    this.teacher,
  });

  final int courseId;
  final String nameAr, nameEn, tone;
  final double progress;
  final double? avg, classAvg;
  final int missed, weakOpen;
  final PulsePerson? teacher;

  String get name => pulseName(nameAr, nameEn);
  bool get isStrength => tone == 'strength';
  bool get isFocus => tone == 'focus';

  factory PulseSubject.fromJson(Map<String, dynamic> j) => PulseSubject(
        courseId: _int(j['course_id']) ?? 0,
        nameAr: _str(j['name_ar']),
        nameEn: _str(j['name_en']),
        progress: (_double(j['progress']) ?? 0).clamp(0, 100).toDouble(),
        avg: _double(j['avg']),
        classAvg: _double(j['class_avg']),
        missed: _int(j['missed']) ?? 0,
        weakOpen: _int(j['weak_open']) ?? 0,
        tone: _str(j['tone']).isEmpty ? 'steady' : _str(j['tone']),
        teacher: PulsePerson.tryParse(j['teacher']),
      );
}

class PulseRoadmap {
  const PulseRoadmap({this.fieldAr = '', this.fieldEn = '', this.done = 0, this.total = 0, this.nextAr = '', this.nextEn = '', this.nextProgress, this.nextKind = ''});
  final String fieldAr, fieldEn, nextAr, nextEn, nextKind;
  final int done, total;
  final double? nextProgress;

  String get field => pulseName(fieldAr, fieldEn);
  String get next => pulseName(nextAr, nextEn);
  double get ratio => total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  static PulseRoadmap? tryParse(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final f = _map(j['field']), n = _map(j['next']);
    return PulseRoadmap(
      fieldAr: _str(f['name_ar']),
      fieldEn: _str(f['name_en']),
      done: _int(j['done']) ?? 0,
      total: _int(j['total']) ?? 0,
      nextAr: _str(n['name_ar']),
      nextEn: _str(n['name_en']),
      nextProgress: _double(n['progress']),
      nextKind: _str(n['kind']),
    );
  }
}

/// What a finding offers to do about it.
enum PulseActionKind { messageTeacher, openReport, openAlerts }

class PulseAction {
  const PulseAction(this.kind, {this.courseId, this.teacherId});
  final PulseActionKind kind;
  final int? courseId, teacherId;

  static PulseAction? tryParse(dynamic v) {
    final j = _map(v);
    final kind = switch (j['kind']) {
      'message_teacher' => PulseActionKind.messageTeacher,
      'open_report' => PulseActionKind.openReport,
      'open_alerts' => PulseActionKind.openAlerts,
      _ => null,
    };
    return kind == null ? null : PulseAction(kind, courseId: _int(j['course_id']), teacherId: _int(j['teacher_id']));
  }
}

class PulseInsight {
  const PulseInsight({required this.code, this.level = 'info', this.params = const {}, this.action});
  final String code, level;
  final Map<String, dynamic> params;
  final PulseAction? action;

  factory PulseInsight.fromJson(Map<String, dynamic> j) => PulseInsight(
        code: _str(j['code']),
        level: _str(j['level']).isEmpty ? 'info' : _str(j['level']),
        params: _map(j['params']),
        action: PulseAction.tryParse(j['action']),
      );
}

class PulseTeacher {
  const PulseTeacher({required this.id, required this.name, this.imageUrl = '', required this.courseId, this.courseAr = '', this.courseEn = ''});
  final int id, courseId;
  final String name, imageUrl, courseAr, courseEn;

  String get course => pulseName(courseAr, courseEn);

  factory PulseTeacher.fromJson(Map<String, dynamic> j) => PulseTeacher(
        id: _int(j['id']) ?? 0,
        name: _str(j['name']),
        imageUrl: _str(j['image_url']),
        courseId: _int(j['course_id']) ?? 0,
        courseAr: _str(j['course_ar']),
        courseEn: _str(j['course_en']),
      );
}

class ParentPulse {
  const ParentPulse({
    this.status = PulseStatus.quiet,
    this.week = const PulseWeek(),
    this.missedSessions = const [],
    this.attendanceTrend = const [],
    this.grades,
    this.subjects = const [],
    this.upcoming = const [],
    this.roadmap,
    this.insights = const [],
    this.teachers = const [],
  });

  final PulseStatus status;
  final PulseWeek week;
  final List<PulseMissed> missedSessions;

  /// 6 rolling weeks, oldest first (null = nothing scheduled that week).
  final List<int?> attendanceTrend;
  final PulseGrades? grades;
  final List<PulseSubject> subjects;
  final List<ParentEventRow> upcoming;
  final PulseRoadmap? roadmap;
  final List<PulseInsight> insights;
  final List<PulseTeacher> teachers;

  List<PulseSubject> get strengths => [for (final s in subjects) if (s.isStrength) s];
  List<PulseSubject> get focus => [for (final s in subjects) if (s.isFocus) s];

  /// The teacher of [courseId] (the message sheet's preselection), or null.
  PulseTeacher? teacherOf(int? courseId) {
    for (final t in teachers) {
      if (t.courseId == courseId) return t;
    }
    return null;
  }

  static ParentPulse? tryParse(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return ParentPulse(
      status: PulseStatus.parse(j['status']),
      week: PulseWeek.fromJson(_map(j['week'])),
      missedSessions: [for (final m in _maps(j['missed_sessions'])) PulseMissed.fromJson(m)],
      attendanceTrend: [for (final p in _maps(j['attendance_trend'])) _int(p['rate'])?.clamp(0, 100)],
      grades: j['grades'] is Map ? PulseGrades.fromJson(_map(j['grades'])) : null,
      subjects: [for (final s in _maps(j['subjects'])) PulseSubject.fromJson(s)],
      upcoming: [for (final e in _maps(j['upcoming'])) ParentEventRow.fromJson(e)]
        ..sort((a, b) => (a.startsAt ?? DateTime.utc(2100)).compareTo(b.startsAt ?? DateTime.utc(2100))),
      roadmap: PulseRoadmap.tryParse(j['roadmap']),
      insights: [for (final i in _maps(j['insights'])) PulseInsight.fromJson(i)],
      teachers: [for (final t in _maps(j['teachers'])) PulseTeacher.fromJson(t)],
    );
  }
}

/// POST /api/v1/parent/children/{id}/message-teacher (kill switch `parent.message_teacher`).
class ParentPulseApi {
  ParentPulseApi({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  /// The number of messages left today for that teacher; throws [ApiException] (429 `parent_message_limit`, …).
  Future<int?> messageTeacher(int childId, {required int courseId, required String message, bool sharePhone = false}) async {
    final r = await _api.post('/api/v1/parent/children/$childId/message-teacher',
        body: {'course_id': courseId, 'message': message, 'share_phone': sharePhone});
    return r is Map ? _int(r['remaining_today']) : null;
  }
}
