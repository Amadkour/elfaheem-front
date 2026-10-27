// lib/core/app_navigator.dart
//
// One place that knows how to open a "module" from a notification tap, a push, a dialog button
// or a shared link. Everything goes through navigatorKey (main.dart).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../core/api_client.dart';
import '../../core/app_mode.dart';
import '../../core/attention/attention_service.dart' show AttentionService, OrgTabRequest;
import '../../features/org/org_my_exams.dart' show MyExamsScreen;
import '../../features/org/org_reports/report_page.dart' show OrgReceivedReportsPage;
import '../../features/shared/course_profile/course_profile_screen.dart' show CourseProfileScreen;
import '../../features/student/courses/details/course_link_loader.dart';
import '../../main.dart';
import '../top_route_observer.dart' show topRouteObserver;
import 'view_as_state.dart';

class AppNavigator {
  AppNavigator._();

  /// AppShell listens to this: set it to a ShellPage.id (e.g. 'profile') to switch tab.
  static final ValueNotifier<String?> requestedTab = ValueNotifier<String?>(null);

  /// Teachers have their own course screen. Set this once (e.g. in main()) to build it:
  ///   AppNavigator.teacherCourseBuilder = (course) => TeacherCourseScreen(course: course);
  /// Left null → teachers also get the shared CourseDetailScreen.
  static Widget Function(Map<String, dynamic> courseJson)? teacherCourseBuilder;

  static Future<void> openCourse(int courseId, {int? ref}) async {
    await navigatorKey.currentState?.push(MaterialPageRoute(
      settings: const RouteSettings(name: '/course-by-id'),
      builder: (_) => CourseLinkLoader(courseId: courseId, ref: ref),
    ));
  }

  /// module: profile | course | course_profile | notifications | my_courses | subscription | org_exams | calendar |
  /// org_reports | org_timetable (needs [orgId]: the organization's Timetable section, on that draft)
  static Future<void> openModule(String? module, {int? targetId, int? orgId}) async {
    final nav = navigatorKey.currentState;
    final ctx = navigatorKey.currentContext;
    if (nav == null || ctx == null || !ctx.mounted) return;
    // Not logged in (or an admin is only LOOKING at a user's app): never navigate on that user's behalf.
    if (!ctx.read<MyAuthProvider>().isAuthenticated || ViewAsState.active) return;
    switch (module) {
      case 'course':
        if (targetId != null) {
          await openCourse(targetId);
        } else {
          await nav.pushNamed('/notifications'); // "course" button without a course id: do not do nothing
        }
        return;
      case 'course_profile': // announcement · "attendance is open" · archive decision → the course profile
        if (targetId != null) {
          await nav.push(MaterialPageRoute(
              settings: RouteSettings(name: '/course-profile', arguments: targetId),
              builder: (_) => CourseProfileScreen(courseId: targetId)));
        } else {
          await nav.pushNamed('/notifications');
        }
        return;
      case 'notifications':
        await nav.pushNamed('/notifications');
        return;
      case 'subscription':
        await nav.pushNamed('/subscription');
        return;
      case 'calendar': // meeting invitation / answer → the calendar on that meeting
        await nav.pushNamed('/calendar', arguments: targetId);
        return;
      case 'org_exams': // "exam timetable published" → My exams (the organization is already open)
        await nav.push(MaterialPageRoute(builder: (_) => const MyExamsScreen()));
        return;
      case 'org_reports': // a report sent to me → Received reports
        await nav.push(MaterialPageRoute(builder: (_) => const OrgReceivedReportsPage()));
        return;
      case 'org_timetable': // a draft timetable is ready / failed → the org dashboard's Timetable section on it
        if (orgId == null) {
          await nav.pushNamed('/notifications');
          return;
        }
        AttentionService.instance.orgTabRequest.value = OrgTabRequest(orgId, 'timetable', targetId != null ? 'open:$targetId' : 'generate');
        if (topRouteObserver.currentRoute?.settings.name != '/org_dashboard') await nav.pushNamed('/org_dashboard');
        return;
      case 'profile':
        await nav.pushNamed('/profile');
      case 'my_courses':
      // These are tabs inside the dashboards: pop to the root and ask the AppShell to switch.
        nav.popUntil((r) => r.isFirst);
        requestedTab.value = null; // re-fire even if the same id is requested twice
        requestedTab.value = module;
        return;
      default:
      // A module this app version does not know (server added a new one) → the notifications list
      // is the safest place to land instead of silently ignoring the tap.
        await nav.pushNamed('/${module??''}');
    }
  }

  /// Notification list tap / push tap. Asks the server where the notification points.
  static Future<void> openNotification(String notificationId) async {
    try {
      final r = await ApiClient().get('/api/v1/notifications/$notificationId/target');
      if (r is! Map) return;
      final module = r['module']?.toString();
      final courseId = int.tryParse('${r['course_id'] ?? ''}');
      final orgId = int.tryParse('${r['org_id'] ?? ''}');
      if (orgId != null && await _openOrgFirst(orgId, module == null && courseId == null)) return;
      await openModule(module, targetId: courseId ?? int.tryParse('${r['target_id'] ?? ''}'), orgId: orgId);
    } catch (_) {/* tapping must never crash */}
  }

  /// The "Generate now" button of a "term without a timetable" push (data: org_id, term_id, action: generate):
  /// runs the one-tap generation (POST …/schedules/auto) and opens the Timetable section on the draft — or, when
  /// the server still refuses, on the term card with the reasons. Returns a text to show, null when nothing to say.
  static Future<String?> generateTermFromPush(Map<String, dynamic> data) async {
    final orgId = int.tryParse('${data['org_id'] ?? ''}');
    final termId = int.tryParse('${data['term_id'] ?? ''}');
    if (orgId == null || termId == null || ViewAsState.active) {
      await openFromPush(data);
      return null;
    }
    int? sid;
    String? text;
    try {
      final r = await ApiClient().post('/api/v1/org/orgs/$orgId/schedules/auto', body: {'term_id': termId});
      sid = r is Map ? int.tryParse('${(r['schedule'] as Map?)?['id'] ?? ''}') : null;
    } catch (e) {
      final err = ApiException.from(e);
      final run = (ApiException.asMap(err.body)?['detail'] as Map?)?['run'];
      sid = run is Map ? int.tryParse('${run['schedule_id'] ?? ''}') : null;   // already running: follow it
      if (err.code != 'generation_running') text = err.message;
    }
    await _openOrgFirst(orgId, false);
    await openModule('org_timetable', targetId: sid, orgId: orgId);
    return text;
  }

  /// FCM payload (tap or foreground). Uses explicit fields when present, else course_id.
  static Future<void> openFromPush(Map<String, dynamic> data) async {
    if (ViewAsState.active) return;
    // course-profile notifications carry {type: course_profile, id: <course id>} (services/organization notify_users)
    final profile = data['type'] == 'course_profile';
    final timetable = data['type'] == 'org_timetable';        // a draft timetable is ready (schedule_auto / autopilot)
    final module = data['module']?.toString() ?? (profile ? 'course_profile' : (timetable ? 'org_timetable' : null));
    final target = int.tryParse('${data['target_id'] ?? data['course_id'] ?? (profile || timetable ? data['id'] : null) ?? ''}');
    final orgId = int.tryParse('${data['org_id'] ?? ''}');
    if (orgId != null && await _openOrgFirst(orgId, module == null && target == null)) return;
    if (module != null) return openModule(module, targetId: target, orgId: orgId);
    if (target != null) return openCourse(target);
    await navigatorKey.currentState?.pushNamed('/notifications');
  }

  /// Organization notification (push data / tap target carry `org_id`): open that organization in Organization
  /// mode BEFORE routing, so the screen it leads to shows that organization (its timezone and feature offs too).
  /// Returns true when it already navigated (nothing more specific to open: back to the home root, now in that
  /// organization).
  static Future<bool> _openOrgFirst(int orgId, bool homeOnly) async {
    if (!AppConfig.orgsEnabled) return false;
    try {
      await AppModeController.instance.openOrg(orgId);
    } catch (_) {/* never block the tap */}
    if (!homeOnly) return false;
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    return true;
  }

  static String get homeRoute {
    final ctx = navigatorKey.currentContext;
    return ctx == null ? '/login' : ctx.read<MyAuthProvider>().homeRoute;
  }
}