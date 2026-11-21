// lib/features/org/students/students_wiring.dart — every plug-in point of the Students section (D-1400, phase 1).
//
// THE only file other code calls (the dashboard, the People page, AppNavigator, the start-URL parser):
//
//   studentsEnabled()                              kill switch `org.students` is on
//   studentsSub(OrgSession s)                      the People sub-page tuple (`OrgSub` of org_dashboard_screen.dart),
//                                                  null without `students` or with the switch off
//   openStudentFile(context, orgId, uid, {name})   pushes the unified student file (the session carried over)
//   openStudentsList(context, orgId)               pushes the Students list on its own (a deep link, the palette)
//   openStudentFromLink(nav, orgId:, uid:)         the deep link `org_student` {org_id, id} / `/org/:orgId/students/:uid`
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../admin/admin_common.dart' show t;
import '../org_providers.dart' show OrgSession;
import 'student_file_page.dart';
import 'students_models.dart' show StudentRow, kStudentsFeatureKey;
import 'students_page.dart' show OrgStudentsPage;

bool studentsEnabled() => !AppConfig.disableList.contains(kStudentsFeatureKey);

/// A row of the Students list opens the student's file.
void _openRow(BuildContext context, int orgId, StudentRow row) =>
    openStudentFile(context, orgId, row.id, name: row.name);

/// The Students sub-page of People, first in `_peopleSubs`: `('students', title, icon, page)`. null when the
/// caller may not see students, no organization is open or the switch is off.
(String, String, IconData, Widget)? studentsSub(OrgSession s) {
  final oid = s.currentId;
  if (oid == null || !s.can('students') || !studentsEnabled()) return null;
  return ('students', t('الطلاب', 'Students'), Icons.school_rounded, OrgStudentsPage(orgId: oid, onOpenStudent: _openRow));
}

/// Pushes the unified file of student [uid] ([name] is the title until it loads).
Future<void> openStudentFile(BuildContext context, int orgId, int uid, {String? name}) =>
    pushStudentPage<void>(context, OrgStudentFilePage(orgId: orgId, uid: uid, name: name));

/// Pushes the Students list as a page of its own.
Future<void> openStudentsList(BuildContext context, int orgId) =>
    pushStudentPage<void>(context, OrgStudentsPage(orgId: orgId, onOpenStudent: _openRow, pushed: true));

/// The deep link to one student's file. `AppNavigator` opens the organization first. False with the switch off (the
/// caller falls back to the member page or the notifications).
Future<bool> openStudentFromLink(NavigatorState nav, {required int orgId, required int uid}) async {
  if (!studentsEnabled()) return false;
  await nav.push(MaterialPageRoute<void>(builder: (_) => OrgStudentFilePage(orgId: orgId, uid: uid)));
  return true;
}
