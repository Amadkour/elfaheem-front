// lib/features/courses/course_profile/course_page_api.dart
//
// The course page's writes and side reads (D-1090): section groups, who is in which, how students get one, a
// student's one pick, and the course rules. Every call throws ApiException (show `cpErrorMessage(e)`); the server
// checks every permission again.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_models.dart';

class CoursePageApi {
  const CoursePageApi(this.courseId);

  final int courseId;

  String get _base => '/api/v1/course-profile/$courseId';

  static Map<String, dynamic> _map(dynamic r) => r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};

  // ── sections ──

  Future<CourseSections> sections() async => CourseSections.fromJson(_map(await ApiClient().get('$_base/sections')));

  /// Replaces the whole list of groups (a group left out is deleted; 409 section_group_in_use while students or
  /// sessions use it).
  Future<void> saveGroups(List<({int? groupNo, String? label, int? taUserId})> groups) => ApiClient().put(
    '$_base/sections/groups',
    body: {
      'groups': [
        for (final g in groups)
          {'group_no': ?g.groupNo, 'label': ?g.label, 'ta_user_id': ?g.taUserId},
      ],
    },
  );

  /// A personal course only: teacher_assigns · student_picks_once.
  Future<void> setMode(String mode) => ApiClient().put('$_base/sections/mode', body: {'mode': mode});

  /// Assigns students to groups (null = no group).
  Future<void> assign(Map<int, int?> studentToGroup) => ApiClient().put(
    '$_base/sections/students',
    body: {
      'assignments': [
        for (final e in studentToGroup.entries) {'student_id': e.key, 'group_no': e.value},
      ],
    },
  );

  /// A student picks their group once.
  Future<void> pick(int groupNo) => ApiClient().post('$_base/sections/pick', body: {'group_no': groupNo});

  // ── attendance on/off (D-1110) ──

  /// The course switch, its sessions' counts and what turning it off / on would do.
  Future<CourseAttendanceFlag> attendanceFlag() async =>
      CourseAttendanceFlag.fromJson(_map(await ApiClient().get('$_base/attendance-flag')));

  /// On: every session on. Off: every session off except the ones that already have attendance.
  Future<CourseAttendanceFlagResult> setAttendanceFlag(bool enabled) async =>
      CourseAttendanceFlagResult.fromJson(_map(await ApiClient().put('$_base/attendance-flag', body: {'enabled': enabled})));

  /// One session (409 attendance_already_taken to turn off a session that has attendance).
  Future<void> setSessionAttendance(int sessionId, bool enabled) =>
      ApiClient().put('$_base/sessions/$sessionId/attendance-flag', body: {'enabled': enabled});

  // ── rules ──

  Future<CourseRules> rules() async => CourseRules.fromJson(_map(await ApiClient().get('$_base/rules')));

  /// The three ready-made rules, all sent together (null = off). Grade weights must total 100.
  Future<void> savePresets({int? absenceLimit, List<CourseGradePart> grades = const [], String? latePolicy}) => ApiClient().put(
    '$_base/rules',
    body: {
      'absence_limit': absenceLimit,
      'grade_breakdown': grades.isEmpty ? null : [for (final g in grades) {'label': g.label, 'weight': g.weight}],
      'late_policy': (latePolicy ?? '').trim().isEmpty ? null : latePolicy!.trim(),
    },
  );

  Future<void> addRule(String text) => ApiClient().post('$_base/rules/items', body: {'text': text});

  Future<void> editRule(int id, String text) => ApiClient().put('$_base/rules/items/$id', body: {'text': text});

  Future<void> deleteRule(int id) => ApiClient().delete('$_base/rules/items/$id');

  Future<void> reorderRules(List<int> ids) => ApiClient().put('$_base/rules/items/order', body: {'ids': ids});
}
