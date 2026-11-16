// lib/features/courses/course_profile/course_profile_models.dart
//
// Pure models + helpers of the course profile (GET /api/v1/course-profile/{id}). No Flutter, no ApiClient:
// everything here is unit-tested (test/ui/course_profile_test.dart).
library;

import 'package:flutter_education_app/features/courses/course_profile/course_page_models.dart';
import 'package:flutter_education_app/features/org/org_v3.dart' show orgParseUtc;

export 'package:flutter_education_app/features/courses/course_profile/course_page_models.dart';

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) => v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
double? _d(dynamic v) => v is num ? v.toDouble() : null;
int _i(dynamic v) => v is num ? v.toInt() : 0;

/// What GET /api/v1/courses/{id} says about the course page for the signed-in caller (D-111): [closed] (the
/// organization archived the course's last run) and [unread] (course announcements newer than what this person last
/// saw, counted by the server). Each is null when the server did not send it (an older server; [unread] also for a
/// guest).
class CoursePageState {
  const CoursePageState({this.closed, this.unread});

  factory CoursePageState.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const CoursePageState();
    final c = j['closed'], u = j['announcements_unread'];
    return CoursePageState(closed: c is bool ? c : null, unread: u is num ? u.toInt().clamp(0, 1 << 30) : null);
  }

  final bool? closed;
  final int? unread;

  /// The server sent at least one of the two fields.
  bool get known => closed != null || unread != null;
}

/// What the signed-in user may do on this course (decided by the server).
class CpCaps {
  const CpCaps(this.raw);
  final Map<String, dynamic> raw;
  bool _b(String k) => raw[k] == true;
  bool get viewMaterial => _b('view_material');
  bool get manageLecture => _b('manage_lecture');
  bool get manageSection => _b('manage_section');
  bool get attendLecture => _b('attend_lecture');
  bool get attendSection => _b('attend_section');
  bool get viewAttendance => _b('view_attendance');
  bool get viewAllAttendance => _b('view_all_attendance');
  bool get manageStaff => _b('manage_staff');
  bool get manageCertificates => _b('manage_certificates');
  bool get manageArchive => _b('manage_archive');
  bool get approveArchive => _b('approve_archive');
  bool get live => _b('live');
  bool get announce => _b('announce');
  bool get viewVersions => _b('view_versions');
  bool get archiveCourse => _b('archive_course');
  bool get courseSettings => _b('course_settings');
  bool manage(String track) => track == 'lecture' ? manageLecture : manageSection;
  bool attend(String track) => track == 'lecture' ? attendLecture : attendSection;
  bool get anyManage => manageLecture || manageSection;
  bool get anyAttend => attendLecture || attendSection;
}

/// One run (term) of an organization course — the course's "versions".
class CpVersion {
  CpVersion(this.raw)
      : id = _i(raw['id']),
        status = (raw['status'] ?? 'open').toString(),
        current = raw['current'] == true,
        term = _m(raw['term']);
  final Map<String, dynamic> raw, term;
  final int id;
  final String status;
  final bool current;
  bool get archived => status == 'archived';
  int get students => _i(raw['students']);
  int get passed => _i(raw['passed']);
}

class CpSession {
  CpSession(this.raw)
      : id = _i(raw['id']),
        name = (raw['name'] ?? '').toString(),
        track = (raw['track'] ?? 'lecture').toString(),
        scheduledAt = orgParseUtc(raw['scheduled_at']),
        materials = _l(raw['materials']);
  final Map<String, dynamic> raw;
  final int id;
  final String name, track;
  final DateTime? scheduledAt;
  final List<Map<String, dynamic>> materials;
  int get materialsCount => _i(raw['materials_count']);
  int? get groupNo => raw['group_no'] is num ? _i(raw['group_no']) : null;
  int? get durationMinutes => raw['duration_minutes'] is num ? _i(raw['duration_minutes']) : null;
  bool get liveNow => raw['live_now'] == true;
  bool get upcoming => raw['upcoming'] == true;
  bool get fromTimetable => raw['from_timetable'] == true;
  bool? get done => raw['done'] as bool?;
  bool? get attended => raw['attended'] as bool?;
  bool? get watched => raw['watched'] as bool?;
  String? get description => raw['description']?.toString();
}

class CourseProfile {
  CourseProfile(this.raw)
      : course = _m(raw['course']),
        role = (raw['role'] ?? 'visitor').toString(),
        caps = CpCaps(_m(raw['caps'])),
        lectures = _l(_m(raw['tracks'])['lecture']).map(CpSession.new).toList(),
        sections = _l(_m(raw['tracks'])['section']).map(CpSession.new).toList(),
        certificates = _l(raw['certificates']),
        announcements = _l(raw['announcements']),
        analytics = _m(raw['analytics']),
        archive = raw['archive'] is Map ? _m(raw['archive']) : null,
        archivePolicy = raw['archive_policy'] is Map ? _m(raw['archive_policy']) : null,
        staff = _m(raw['staff']),
        versions = _l(raw['versions']).map(CpVersion.new).toList(),
        attendanceTarget = raw['attendance_target'] is Map ? CpSession(_m(raw['attendance_target'])) : null;
  final Map<String, dynamic> raw, course, analytics, staff;
  final String role;
  final CpCaps caps;
  final List<CpSession> lectures, sections;
  final List<Map<String, dynamic>> certificates, announcements;
  final Map<String, dynamic>? archive, archivePolicy;
  final List<CpVersion> versions;

  /// The session the single "Open attendance" button opens (live now / nearest today); null → the picker.
  final CpSession? attendanceTarget;

  /// The Overview's data (D-1090); null from an older server.
  late final CoursePage? page = CoursePage.of(raw);

  int get id => _i(course['id']);
  bool get isOrg => course['kind'] == 'org';
  bool get closed => raw['closed'] == true;
  bool get readOnly => raw['read_only'] == true;
  bool get isStudent => role == 'student';
  bool get isStaff => role == 'admin' || role == 'instructor' || role == 'ta';
  bool get isFull => role == 'admin' || role == 'instructor';
  String get archiveState => (archive?['state'] ?? 'open').toString();
  String get archiveEffectiveMode => (archive?['effective_mode'] ?? 'request').toString();
  Map<String, dynamic> get grant => _m(raw['grant']);
  List<Map<String, dynamic>> get assistants => _l(staff['assistants']);
  Map<String, dynamic>? get instructor => staff['instructor'] is Map ? _m(staff['instructor']) : null;
  Map<String, dynamic> get progress => _m(analytics['progress']);

  /// An earlier run opened from "Versions": read-only for everyone.
  bool get pastVersion => _m(raw['version'])['past'] == true;
  int? get runId => _m(raw['version'])['run_id'] is num ? _i(_m(raw['version'])['run_id']) : null;

  /// The student's approved grade for this run (registrar), or null.
  Map<String, dynamic>? get grade => analytics['grade'] is Map ? _m(analytics['grade']) : null;

  /// Sessions this user may take attendance for, in course order (lectures, then sections) — the picker's list.
  List<CpSession> get attendableSessions => [
        if (caps.attendLecture) ...lectures,
        if (caps.attendSection) ...sections,
      ];

  String name(bool ar) {
    final a = (course['name_ar'] ?? '').toString(), e = (course['name_en'] ?? '').toString();
    return ar ? (a.isNotEmpty ? a : e) : (e.isNotEmpty ? e : a);
  }

  List<CpSession> track(String t) => t == 'lecture' ? lectures : sections;

  /// Sections / labs exist only when the course has some (or the user can add them).
  bool get hasSections => sections.isNotEmpty || caps.manageSection && isOrg;
}

/// Tabs the page shows for this profile, in order. Pure — tested.
///   student      review: overview (progress · check-in · grade) · material · attendance · announcements · certificates
///   TA           its part + attendance + team (own grant) + versions
///   instructor   everything; admins also archive approval and the org archive rules
///   earlier run  read-only: material, attendance and announcements only
List<String> cpTabs(CourseProfile p) {
  if (p.pastVersion) {
    return [
      'overview',
      'lecture',
      if (p.sections.isNotEmpty) 'section',
      if (p.announcements.isNotEmpty) 'announcements',
      if (p.caps.viewAttendance && p.isStaff) 'attendance',
    ];
  }
  return [
    'overview',
    'lecture',
    if (p.hasSections) 'section',
    if (p.caps.viewAttendance && !p.readOnly) 'attendance',
    if (p.caps.announce || p.announcements.isNotEmpty) 'announcements',
    if (p.certificates.isNotEmpty || p.caps.manageCertificates) 'certificates',
    if (p.caps.manageStaff || p.role == 'ta') 'team',
    if (p.caps.manageArchive || p.caps.approveArchive || p.caps.viewVersions || (p.closed && p.isStudent)) 'archive',
  ];
}

/// Term kind → (ar, en).
(String, String) cpTermKindLabel(String kind) => switch (kind) {
      'term1' => ('الفصل الأول', 'Term 1'),
      'term2' => ('الفصل الثاني', 'Term 2'),
      'summer' => ('الفصل الصيفي', 'Summer term'),
      _ => ('فصل', 'Term'),
    };

/// "Term 1 · 2026/2027" for a version / term map.
String cpTermLabel(Map<String, dynamic> term, bool ar) {
  final k = cpTermKindLabel('${term['kind'] ?? ''}');
  return [ar ? k.$1 : k.$2, '${term['year_label'] ?? ''}'].where((s) => s.trim().isNotEmpty).join(' · ');
}

/// The course's state for the header pill: archived · live · running · upcoming (no session held yet).
String cpStatus(CourseProfile p) {
  if (p.closed) return 'archived';
  final all = [...p.lectures, ...p.sections];
  if (all.any((s) => s.liveNow)) return 'live';
  if (all.isNotEmpty && all.every((s) => s.upcoming)) return 'upcoming';
  return 'running';
}

/// Announcement audience → (ar, en).
(String, String) cpAudienceLabel(String track) => switch (track) {
      'lecture' => ('طلاب المحاضرات', 'Lecture students'),
      'section' => ('السكاشن والمعامل', 'Sections & labs'),
      _ => ('كل الطلاب', 'All students'),
    };

/// Material counters for the hero / overview.
({int materials, int videos, int done}) cpMaterialStats(CourseProfile p) {
  var n = 0, v = 0, d = 0;
  for (final s in [...p.lectures, ...p.sections]) {
    for (final m in s.materials) {
      n++;
      final t = (m['type'] ?? '').toString();
      if (t == 'video' || t == 'recorded') v++;
      if (m['completed'] == true) d++;
    }
  }
  return (materials: n, videos: v, done: d);
}

/// The session a student should open next: the first one with unfinished material, else the next upcoming one.
CpSession? cpContinue(CourseProfile p) {
  for (final s in [...p.lectures, ...p.sections]) {
    if (s.materials.isNotEmpty && s.done == false) return s;
  }
  final up = [...p.lectures, ...p.sections].where((s) => s.upcoming && s.scheduledAt != null).toList()
    ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
  return up.isEmpty ? null : up.first;
}

/// Attendance report (GET …/attendance).
class CpAttendance {
  CpAttendance(Map<String, dynamic> j)
      : sessions = _l(j['sessions']),
        students = _l(j['students']),
        missedByStaff = _i(j['missed_by_staff']),
        held = _i(j['held']);
  final List<Map<String, dynamic>> sessions, students;
  final int missedByStaff, held;

  /// Students sorted by most absences first (the instructor's at-risk view).
  List<Map<String, dynamic>> get byRisk =>
      [...students]..sort((a, b) => (_d(b['absence_pct']) ?? 0).compareTo(_d(a['absence_pct']) ?? 0));

  List<Map<String, dynamic>> filtered(String track) =>
      track == 'all' ? sessions : sessions.where((s) => s['track'] == track).toList();
}

/// Certificate scope label key → (ar, en).
(String, String) cpScopeLabel(String scope) => switch (scope) {
      'lecture' => ('المحاضرات', 'Lectures'),
      'section' => ('السكاشن والمعامل', 'Sections & labs'),
      _ => ('المحاضرات والسكاشن', 'Lectures & sections'),
    };

/// Archive access mode → (ar, en).
(String, String) cpArchiveModeLabel(String mode) => switch (mode) {
      'auto' => ('تلقائي للطلاب المسجّلين', 'Automatic for enrolled students'),
      'code' => ('بكود', 'With a code'),
      _ => ('بطلب يوافق عليه المسؤول', 'By request (admin approval)'),
    };

/// Server error codes of the course profile → (ar, en).
(String, String)? cpErrorText(String? code) => switch (code) {
      'course_archived' => ('المقرر مؤرشف — المحتوى للقراءة فقط', 'The course is archived — read only'),
      // D-1090: sections and course rules
      'section_group_in_use' => ('لا يمكن حذف سكشن به طلاب أو جلسات', 'A section with students or sessions cannot be removed'),
      'sections_from_registrar' => ('السكاشن تأتي من تسجيل المؤسسة ولا تُعدَّل هنا', "Sections come from the organization's registration and are not edited here"),
      'section_mode_from_org' => ('طريقة توزيع السكاشن تحددها إدارة المؤسسة', "The organization's admin decides how sections are given"),
      'section_pick_not_allowed' => ('اختيار السكشن غير متاح في هذا الكورس', 'Picking a section is not open in this course'),
      'section_already_set' => ('اخترت سكشنك من قبل؛ اطلب من المحاضر تغييره', 'You already have a section; ask the teacher to change it'),
      'section_group_not_found' => ('هذا السكشن غير موجود', 'This section does not exist'),
      'not_your_section' => ('هذه الجلسة لسكشن آخر', 'This session belongs to another section'),
      'grade_breakdown_total' => ('مجموع توزيع الدرجات يجب أن يكون 100', 'The grade breakdown must add up to 100'),
      'not_assistant' => ('هذا العضو ليس معيداً في المقرر', 'This member is not an assistant of the course'),
      'no_students' => ('اختر طلاباً أو «المكملين فقط»', 'Pick students or “completers only”'),
      'not_enrolled' => ('بعض الطلاب غير مسجلين في المقرر', 'Some students are not enrolled'),
      'not_taken' => ('لم تكن مسجّلاً في هذه النسخة', 'You were not enrolled in this run'),
      'pending' => ('طلبك قيد المراجعة', 'Your request is under review'),
      'code_not_enabled' => ('الدخول بالكود غير مفعّل لهذا المقرر', 'Code access is not enabled for this course'),
      'bad_code' => ('الكود غير صحيح', 'Wrong code'),
      'not_member' => ('هذا الأرشيف لأعضاء المؤسسة فقط', 'This archive is for members of the organization'),
      'ta_section_only' => ('المعيد ينشر لجمهور السكاشن والمعامل فقط', 'Assistants post to sections & labs only'),
      'course_forbidden' => ('ليست لديك صلاحية لهذا الإجراء', 'You do not have permission for this'),
      'version_not_found' => ('هذه النسخة من المقرر غير موجودة', 'This version of the course was not found'),
      'session_not_found' => ('الجلسة غير موجودة', 'Session not found'),
      'session_not_started' => ('لم يبدأ موعد الجلسة بعد', 'The session has not started yet'),
      _ => null,
    };
