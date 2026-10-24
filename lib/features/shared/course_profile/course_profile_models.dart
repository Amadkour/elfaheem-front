// lib/features/shared/course_profile/course_profile_models.dart
//
// Pure models + helpers of the course profile (GET /api/v1/course-profile/{id}). No Flutter, no ApiClient:
// everything here is unit-tested (test/ui/course_profile_test.dart).
library;

import '../../org/org_v3.dart' show orgParseUtc;

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _l(dynamic v) => v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
double? _d(dynamic v) => v is num ? v.toDouble() : null;
int _i(dynamic v) => v is num ? v.toInt() : 0;

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
  bool manage(String track) => track == 'lecture' ? manageLecture : manageSection;
  bool get anyManage => manageLecture || manageSection;
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
        staff = _m(raw['staff']);
  final Map<String, dynamic> raw, course, analytics, staff;
  final String role;
  final CpCaps caps;
  final List<CpSession> lectures, sections;
  final List<Map<String, dynamic>> certificates, announcements;
  final Map<String, dynamic>? archive, archivePolicy;

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

  String name(bool ar) {
    final a = (course['name_ar'] ?? '').toString(), e = (course['name_en'] ?? '').toString();
    return ar ? (a.isNotEmpty ? a : e) : (e.isNotEmpty ? e : a);
  }

  List<CpSession> track(String t) => t == 'lecture' ? lectures : sections;

  /// Sections / labs exist only when the course has some (or the user can add them).
  bool get hasSections => sections.isNotEmpty || caps.manageSection && isOrg;
}

/// Tabs the page shows for this profile, in order. Pure — tested.
List<String> cpTabs(CourseProfile p) => [
      'overview',
      'lecture',
      if (p.hasSections) 'section',
      if (p.caps.announce || p.announcements.isNotEmpty) 'announcements',
      if (p.caps.viewAttendance && !p.readOnly) 'attendance',
      if (p.certificates.isNotEmpty || p.caps.manageCertificates) 'certificates',
      if (p.caps.manageStaff || p.role == 'ta') 'team',
      if (p.caps.manageArchive || p.caps.approveArchive || (p.closed && p.isStudent)) 'archive',
    ];

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
      _ => null,
    };
