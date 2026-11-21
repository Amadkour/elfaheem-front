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
//   studentRequestsSub(OrgSession s)               the People sub-page "Student requests" (under org.students; with
//                                                  org.students.asks off only its ask parts hide)
//   openStudentRequestsFromLink(nav, orgId:)       the deep link `org_student` with focus `asks` → the requests inbox
//   openStudentAskFromLink(nav, askId)             the student's deep link `student_ask` {id} → their ask page
//   openLifecycleRequestFromLink(nav, orgId:, id:, role:)   a lifecycle request notice (`org_work` + lifecycle_request_id):
//                                                  staff → the request sheet, the student → My requests
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../admin/admin_common.dart' show t;
import '../org_providers.dart' show OrgSession;
import 'my_ask_page.dart' show myAsksEnabled, openMyAsk;
import 'my_requests.dart' show openMyRequests;
import 'student_request_detail.dart' show openStudentRequest;
import 'student_file_page.dart';
import 'student_requests_page.dart' show OrgStudentRequestsPage;
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

/// The "Student requests" sub-page of People, right after Students: `('student_requests', title, icon, page)`. null
/// without `students` / `student_status` rights, with no organization open or with the Students switch off. Asks off
/// (`org.students.asks`) keeps it: it also holds lifecycle requests and admission files; only its ask parts hide.
(String, String, IconData, Widget)? studentRequestsSub(OrgSession s) {
  final oid = s.currentId;
  if (oid == null || !(s.can('students') || s.can('student_status')) || !studentsEnabled()) return null;
  return ('student_requests', t('طلبات الطلاب', 'Student requests'), Icons.assignment_turned_in_rounded,
      OrgStudentRequestsPage(orgId: oid, canFullscreen: s.can('student_status', 'update')));
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

/// The staff deep link `org_student` with focus `asks` (a student answered an ask): the requests inbox, where it is
/// decided. False with the Students switch off (the caller falls back to the file / the notifications).
Future<bool> openStudentRequestsFromLink(NavigatorState nav, {required int orgId}) async {
  if (!studentsEnabled()) return false;
  await nav.push(MaterialPageRoute<void>(builder: (_) => OrgStudentRequestsPage(orgId: orgId, pushed: true)));
  return true;
}

/// A lifecycle request notice: `org_work` + `lifecycle_request_id` [id] + `role`. Staff get the request sheet, the
/// request's own student ([role] `student`) My requests. False with the switch off (the caller opens the Governance
/// item, as an older app does).
Future<bool> openLifecycleRequestFromLink(NavigatorState nav, {required int orgId, required int id, String? role}) async {
  if (!studentsEnabled()) return false;
  if (role == 'student') {
    await openMyRequests(nav.context, orgId);
  } else {
    await openStudentRequest(nav.context, orgId, id);
  }
  return true;
}

/// The student's deep link `student_ask` {id}: their ask page. False with asks switched off.
Future<bool> openStudentAskFromLink(NavigatorState nav, int askId) async {
  if (!myAsksEnabled()) return false;
  await openMyAsk(nav, askId);
  return true;
}
