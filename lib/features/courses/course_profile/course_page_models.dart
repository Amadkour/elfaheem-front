// lib/features/courses/course_profile/course_page_models.dart
//
// The `page` block of GET /api/v1/course-profile/{id} (D-1090, back FLUTTER_API_CHANGES.md 2026-11-16): everything the
// course page's Overview draws in ONE call — counts, my next session, setup steps (staff), the weekly slots, exams,
// the course rules, section groups, the team, attendance and, for a course outside any organization, rating / path /
// earnings. Plus the shapes of GET …/sections and GET …/rules. Pure Dart (no Flutter, no ApiClient); every field is
// read leniently so an older server (no `page`) leaves [CoursePage.of] null and the page keeps its old cards.
library;

import 'package:flutter_education_app/features/org/org_v3.dart' show orgParseUtc;

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
int _i(dynamic v) => v is num ? v.toInt() : 0;
int? _io(dynamic v) => v is num ? v.toInt() : null;
double? _d(dynamic v) => v is num ? v.toDouble() : null;
String? _s(dynamic v) => v?.toString();

/// The weekdays the server sends, in the order a week is drawn (Saturday first, as the platform's week starts).
const kCourseWeekDays = ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday'];

/// A person the page names (instructor, a section's TA).
class CoursePerson {
  const CoursePerson({required this.id, required this.name, this.imageUrl});

  factory CoursePerson.fromJson(Map<String, dynamic> j) =>
      CoursePerson(id: _i(j['id']), name: (j['name'] ?? '').toString(), imageUrl: _s(j['image_url']));

  static CoursePerson? maybe(dynamic v) => v is Map ? CoursePerson.fromJson(_m(v)) : null;

  final int id;
  final String name;
  final String? imageUrl;
}

class CoursePageCounts {
  const CoursePageCounts({
    this.students = 0,
    this.sessionsTotal = 0,
    this.sessionsDone = 0,
    this.lectures = 0,
    this.sections = 0,
    this.minutes = 0,
    this.hours = 0,
    this.priceAmount = 0,
    this.currency,
    this.free = true,
  });

  factory CoursePageCounts.fromJson(Map<String, dynamic> j) {
    final p = _m(j['price']);
    return CoursePageCounts(
      students: _i(j['students']),
      sessionsTotal: _i(j['sessions_total']),
      sessionsDone: _i(j['sessions_done']),
      lectures: _i(j['lectures']),
      sections: _i(j['sections']),
      minutes: _i(j['minutes']),
      hours: _d(j['hours']) ?? 0,
      priceAmount: _d(p['amount']) ?? 0,
      currency: _s(p['currency']),
      free: p['free'] != false,
    );
  }

  final int students, sessionsTotal, sessionsDone, lectures, sections, minutes;
  final double hours, priceAmount;
  final String? currency;
  final bool free;
}

/// The next session for the caller (a student: a lecture or their own section).
class CoursePageNext {
  const CoursePageNext({
    required this.id,
    required this.name,
    this.track = 'lecture',
    this.groupNo,
    this.at,
    this.minutes,
    this.liveNow = false,
    this.attendanceEnabled = true,
  });

  factory CoursePageNext.fromJson(Map<String, dynamic> j) => CoursePageNext(
    id: _i(j['id']),
    name: (j['name'] ?? '').toString(),
    track: (j['track'] ?? 'lecture').toString(),
    groupNo: _io(j['group_no']),
    at: orgParseUtc(j['scheduled_at']),
    minutes: _io(j['duration_minutes']),
    liveNow: j['live_now'] == true,
    attendanceEnabled: j['attendance_enabled'] != false,
  );

  final int id;
  final String name, track;
  final int? groupNo, minutes;
  final DateTime? at;
  final bool liveNow;

  /// D-1110: this session takes attendance (off = no Start attendance).
  final bool attendanceEnabled;
  bool get isSection => track == 'section';
}

class CourseSetupStep {
  const CourseSetupStep(this.key, this.done);

  /// cover · description · schedule · rules · first_exam
  final String key;
  final bool done;
}

class CourseWeekSlot {
  const CourseWeekSlot({required this.day, required this.start, required this.end, this.track = 'lecture', this.groupNo});

  factory CourseWeekSlot.fromJson(Map<String, dynamic> j) => CourseWeekSlot(
    day: (j['day'] ?? '').toString().toLowerCase(),
    start: (j['start'] ?? '').toString(),
    end: (j['end'] ?? '').toString(),
    track: (j['track'] ?? 'lecture').toString(),
    groupNo: _io(j['group_no']),
  );

  /// saturday … friday; [start] / [end] are wall times "HH:MM".
  final String day, start, end, track;
  final int? groupNo;
  bool get isSection => track == 'section';
}

class CourseExamRow {
  const CourseExamRow({required this.id, required this.name, this.start, this.end, this.duration});

  factory CourseExamRow.fromJson(Map<String, dynamic> j) => CourseExamRow(
    id: _i(j['id']),
    name: (j['name'] ?? '').toString(),
    start: orgParseUtc(j['start_date']),
    end: orgParseUtc(j['end_date']),
    duration: _io(j['duration']),
  );

  final int id;
  final String name;
  final DateTime? start, end;
  final int? duration;
}

class CourseExamResult {
  const CourseExamResult({required this.name, this.marks, this.total, this.percentage, this.passed});

  factory CourseExamResult.fromJson(Map<String, dynamic> j) => CourseExamResult(
    name: (j['name'] ?? '').toString(),
    marks: _d(j['marks']),
    total: _d(j['total']),
    percentage: _d(j['percentage']),
    passed: j['passed'] as bool?,
  );

  final String name;
  final double? marks, total, percentage;
  final bool? passed;
}

class CoursePageExams {
  const CoursePageExams({this.total = 0, this.upcoming = const [], this.upcomingCount = 0, this.toGrade, this.lastResult});

  factory CoursePageExams.fromJson(Map<String, dynamic> j) => CoursePageExams(
    total: _i(j['total']),
    upcoming: _l(j['upcoming']).map(CourseExamRow.fromJson).toList(),
    upcomingCount: _i(j['upcoming_count']),
    toGrade: _io(j['to_grade']),
    lastResult: j['last_result'] is Map ? CourseExamResult.fromJson(_m(j['last_result'])) : null,
  );

  final int total, upcomingCount;
  final List<CourseExamRow> upcoming;

  /// Staff: submissions waiting for a grade.
  final int? toGrade;

  /// A student: the last graded exam.
  final CourseExamResult? lastResult;
}

class CourseGradePart {
  const CourseGradePart(this.label, this.weight);

  final String label;
  final int weight;
}

class CourseRuleItem {
  const CourseRuleItem({required this.id, required this.text, this.order = 0});

  final int id;
  final String text;
  final int order;
}

/// GET …/rules (and `page.rules`): the teacher's rules for this course only.
class CourseRules {
  const CourseRules({
    this.absenceLimit,
    this.grades = const [],
    this.latePolicy,
    this.items = const [],
    this.canEdit = false,
    this.myAbsences,
    this.myLeft,
    this.over = false,
  });

  factory CourseRules.fromJson(Map<String, dynamic> j) {
    final me = j['me'] is Map ? _m(j['me']) : null;
    return CourseRules(
      absenceLimit: _io(j['absence_limit']),
      grades: [
        for (final g in _l(j['grade_breakdown'])) CourseGradePart((g['label'] ?? '').toString(), _i(g['weight'])),
      ],
      latePolicy: (_s(j['late_policy']) ?? '').trim().isEmpty ? null : _s(j['late_policy']),
      items: [
        for (final it in _l(j['items'])) CourseRuleItem(id: _i(it['id']), text: (it['text'] ?? '').toString(), order: _i(it['order'])),
      ]..sort((a, b) => a.order.compareTo(b.order)),
      canEdit: j['can_edit'] == true,
      myAbsences: me == null ? null : _io(me['absences']),
      myLeft: me == null ? null : _io(me['left']),
      over: me?['over'] == true,
    );
  }

  final int? absenceLimit;
  final List<CourseGradePart> grades;
  final String? latePolicy;
  final List<CourseRuleItem> items;
  final bool canEdit;

  /// A student's own absences against [absenceLimit] (null for staff).
  final int? myAbsences, myLeft;
  final bool over;

  bool get isEmpty => absenceLimit == null && grades.isEmpty && latePolicy == null && items.isEmpty;
  int get count => items.length + (absenceLimit != null ? 1 : 0) + (grades.isNotEmpty ? 1 : 0) + (latePolicy != null ? 1 : 0);

  CourseRules copyWith({bool? canEdit}) => CourseRules(
    absenceLimit: absenceLimit,
    grades: grades,
    latePolicy: latePolicy,
    items: items,
    canEdit: canEdit ?? this.canEdit,
    myAbsences: myAbsences,
    myLeft: myLeft,
    over: over,
  );
}

/// One section group of the course.
class CourseSectionGroup {
  const CourseSectionGroup({required this.groupNo, required this.label, this.labelEn, this.ta, this.students});

  factory CourseSectionGroup.fromJson(Map<String, dynamic> j) => CourseSectionGroup(
    groupNo: _i(j['group_no']),
    label: (j['label'] ?? '').toString(),
    labelEn: _s(j['label_en']),
    ta: CoursePerson.maybe(j['ta']),
    students: _io(j['students']),
  );

  final int groupNo;
  final String label;
  final String? labelEn;
  final CoursePerson? ta;

  /// Staff only: how many students are in the group.
  final int? students;

  /// The group's name in the reader's language: the teacher's own label wins over the generated English one.
  String labelFor(bool ar) {
    final generated = RegExp(r'^سكشن \d+$').hasMatch(label);
    if (ar || !generated) return label;
    return labelEn ?? label;
  }
}

/// `page.sections` and GET …/sections.
class CourseSections {
  const CourseSections({
    this.mode = 'teacher_assigns',
    this.modeSource = 'course',
    this.source = 'course',
    this.myGroup,
    this.canPick = false,
    this.groups = const [],
    this.unassigned,
    this.students = const [],
    this.canEdit = false,
  });

  factory CourseSections.fromJson(Map<String, dynamic> j) => CourseSections(
    mode: (j['mode'] ?? 'teacher_assigns').toString(),
    modeSource: (j['mode_source'] ?? 'course').toString(),
    source: (j['source'] ?? 'course').toString(),
    myGroup: _io(j['my_group']),
    canPick: j['can_pick'] == true,
    groups: _l(j['groups']).map(CourseSectionGroup.fromJson).toList(),
    unassigned: _io(j['unassigned']),
    students: [
      for (final s in _l(j['students']))
        CourseSectionStudent(person: CoursePerson.fromJson(_m(s['user'])), groupNo: _io(s['group_no']), setBy: _s(s['set_by'])),
    ],
    canEdit: j['can_edit'] == true,
  );

  /// teacher_assigns · student_picks_once
  final String mode;

  /// org (the organization's setup decides) · course (the teacher's own setting)
  final String modeSource;

  /// registrar (groups from the organization's registration, read-only) · course (the course's own groups)
  final String source;
  final int? myGroup;
  final bool canPick;
  final List<CourseSectionGroup> groups;
  final int? unassigned;
  final List<CourseSectionStudent> students;
  final bool canEdit;

  bool get studentPicks => mode == 'student_picks_once';
  bool get fromRegistrar => source == 'registrar';
  CourseSectionGroup? group(int? no) => no == null ? null : groups.where((g) => g.groupNo == no).firstOrNull;
}

class CourseSectionStudent {
  const CourseSectionStudent({required this.person, this.groupNo, this.setBy});

  final CoursePerson person;
  final int? groupNo;
  final String? setBy;
}

class CoursePageTeam {
  const CoursePageTeam({this.instructor, this.assistants = const [], this.myTa});

  factory CoursePageTeam.fromJson(Map<String, dynamic> j) => CoursePageTeam(
    instructor: CoursePerson.maybe(j['instructor']),
    assistants: [for (final a in _l(j['assistants'])) CoursePerson.fromJson(a)],
    myTa: CoursePerson.maybe(j['my_ta']),
  );

  final CoursePerson? instructor;
  final List<CoursePerson> assistants;
  final CoursePerson? myTa;
}

/// A student: attended / expected / absences (+ the limit); staff: the course's rate and how many are at risk.
class CoursePageAttendance {
  const CoursePageAttendance({this.attended, this.expected, this.absences, this.limit, this.rate, this.atRisk});

  factory CoursePageAttendance.fromJson(Map<String, dynamic> j) => CoursePageAttendance(
    attended: _io(j['attended']),
    expected: _io(j['expected']),
    absences: _io(j['absences']),
    limit: _io(j['limit']),
    rate: _d(j['rate']),
    atRisk: _io(j['at_risk']),
  );

  final int? attended, expected, absences, limit, atRisk;

  /// Staff: 0…100.
  final double? rate;

  /// A student's own rate 0…100 (null before the first counted session).
  double? get myRate => (expected ?? 0) > 0 ? (attended ?? 0) * 100 / expected! : null;
}

class CoursePathStep {
  const CoursePathStep({required this.id, required this.nameAr, required this.nameEn, this.imageUrl});

  final int id;
  final String nameAr, nameEn;
  final String? imageUrl;
  String name(bool ar) => (ar ? nameAr : nameEn).isNotEmpty ? (ar ? nameAr : nameEn) : (ar ? nameEn : nameAr);
}

/// A course outside any organization: rating, the star breakdown (5★ first), the path and — for its owner — the
/// earnings of the last 8 weeks.
class CoursePagePersonal {
  const CoursePagePersonal({this.rating, this.reviews = 0, this.distribution = const [], this.path = const [], this.earningsWeeks, this.earningsTotal, this.earningsCurrency});

  factory CoursePagePersonal.fromJson(Map<String, dynamic> j) {
    final e = j['earnings'] is Map ? _m(j['earnings']) : null;
    return CoursePagePersonal(
      rating: _d(j['rating']),
      reviews: _i(j['reviews']),
      distribution: [for (final v in (j['distribution'] is List ? j['distribution'] as List : const [])) _i(v)],
      path: [
        for (final p in _l(j['path']))
          CoursePathStep(id: _i(p['id']), nameAr: (p['name_ar'] ?? '').toString(), nameEn: (p['name_en'] ?? '').toString(), imageUrl: _s(p['image_url'])),
      ],
      earningsWeeks: e == null ? null : [for (final v in (e['weeks'] is List ? e['weeks'] as List : const [])) (v is num ? v.toDouble() : 0.0)],
      earningsTotal: e == null ? null : _d(e['total']),
      earningsCurrency: e == null ? null : _s(e['currency']),
    );
  }

  final double? rating;
  final int reviews;
  final List<int> distribution;
  final List<CoursePathStep> path;
  final List<double>? earningsWeeks;
  final double? earningsTotal;
  final String? earningsCurrency;
}

/// The whole `page` block.
class CoursePage {
  const CoursePage({
    this.counts = const CoursePageCounts(),
    this.next,
    this.setup,
    this.weekSource = 'course',
    this.week = const [],
    this.exams,
    this.rules = const CourseRules(),
    this.sections = const CourseSections(),
    this.team = const CoursePageTeam(),
    this.attendance,
    this.personal,
    this.attendanceEnabled = true,
  });

  factory CoursePage.fromJson(Map<String, dynamic> j) {
    final setup = j['setup'] is Map ? _m(j['setup']) : null;
    final week = _m(j['week']);
    return CoursePage(
      counts: CoursePageCounts.fromJson(_m(j['counts'])),
      next: j['next'] is Map ? CoursePageNext.fromJson(_m(j['next'])) : null,
      setup: setup == null ? null : [for (final s in _l(setup['steps'])) CourseSetupStep((s['key'] ?? '').toString(), s['done'] == true)],
      weekSource: (week['source'] ?? 'course').toString(),
      week: _l(week['slots']).map(CourseWeekSlot.fromJson).toList(),
      exams: j['exams'] is Map ? CoursePageExams.fromJson(_m(j['exams'])) : null,
      rules: CourseRules.fromJson(_m(j['rules'])),
      sections: CourseSections.fromJson(_m(j['sections'])),
      team: CoursePageTeam.fromJson(_m(j['team'])),
      attendance: j['attendance'] is Map ? CoursePageAttendance.fromJson(_m(j['attendance'])) : null,
      personal: j['personal'] is Map ? CoursePagePersonal.fromJson(_m(j['personal'])) : null,
      attendanceEnabled: j['attendance_enabled'] != false,
    );
  }

  /// The block of a whole profile payload; null when the server sent none (an older server).
  static CoursePage? of(Map<String, dynamic> profile) =>
      profile['page'] is Map ? CoursePage.fromJson(_m(profile['page'])) : null;

  final CoursePageCounts counts;
  final CoursePageNext? next;

  /// Staff only (null for a student or a read-only course).
  final List<CourseSetupStep>? setup;
  final String weekSource;
  final List<CourseWeekSlot> week;
  final CoursePageExams? exams;
  final CourseRules rules;
  final CourseSections sections;
  final CoursePageTeam team;
  final CoursePageAttendance? attendance;
  final CoursePagePersonal? personal;

  /// D-1110: the course's attendance switch (an older server: on).
  final bool attendanceEnabled;

  int get setupDone => setup?.where((s) => s.done).length ?? 0;
  bool get setupComplete => setup == null || setup!.every((s) => s.done);
  bool get isPersonal => personal != null;
}

/// D-1110: the course's attendance switch and what changing it would do (`GET …/attendance-flag`).
class CourseAttendanceFlag {
  const CourseAttendanceFlag({
    this.enabled = true,
    this.sessions = 0,
    this.on = 0,
    this.off = 0,
    this.taken = 0,
    this.wouldTurnOff = 0,
    this.wouldKeepTaken = 0,
    this.wouldTurnOn = 0,
  });

  factory CourseAttendanceFlag.fromJson(Map<String, dynamic> j) => CourseAttendanceFlag(
    enabled: j['enabled'] != false,
    sessions: _i(j['sessions']),
    on: _i(j['on']),
    off: _i(j['off']),
    taken: _i(j['taken']),
    wouldTurnOff: _i(j['would_turn_off']),
    wouldKeepTaken: _i(j['would_keep_taken']),
    wouldTurnOn: _i(j['would_turn_on']),
  );

  final bool enabled;
  final int sessions, on, off, taken, wouldTurnOff, wouldKeepTaken, wouldTurnOn;
}

/// D-1110: what `PUT …/attendance-flag` did.
class CourseAttendanceFlagResult {
  const CourseAttendanceFlagResult({this.enabled = true, this.turnedOn = 0, this.turnedOff = 0, this.keptTaken = 0});

  factory CourseAttendanceFlagResult.fromJson(Map<String, dynamic> j) => CourseAttendanceFlagResult(
    enabled: j['enabled'] != false,
    turnedOn: _i(j['turned_on']),
    turnedOff: _i(j['turned_off']),
    keptTaken: _i(j['kept_taken']),
  );

  final bool enabled;
  final int turnedOn, turnedOff, keptTaken;
}
