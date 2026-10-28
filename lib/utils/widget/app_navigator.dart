// lib/core/app_navigator.dart
//
// One place that knows how to open a "module" from a notification tap, a push, a dialog button
// or a shared link. Everything goes through navigatorKey (main.dart).
import 'dart:async' show unawaited;

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
import '../../features/shared/profile/compalints/complaint_provider.dart' show ComplaintProvider;
import '../../features/shared/profile/compalints/complaints_screen.dart' show ComplaintDetailScreen, ComplaintsScreen;
import '../../features/student/courses/details/course_link_loader.dart';
import '../../features/shared/public_profile/public_profile_page.dart' show PublicProfileScreen;
import '../../main.dart';
import '../top_route_observer.dart' show topRouteObserver;
import 'view_as_state.dart';
import '../../features/org/governance/gov_wiring.dart' show govOpenAssignmentsLink, govOpenDelegationLink, govOpenItemLink, govOpenSessionLink;
import '../../features/shared/live/live_room.dart' show LiveRoomRef, kLiveLobbyFeatureKey;
import '../../features/shared/live/live_lobby_sheets.dart' show showLobbySheet;
import '../../features/shared/points/points_api.dart' show kPointsFeatureKey, pointsModuleFor;
import '../../features/shared/points/points_wallet_page.dart' show PointsWalletPage;
import '../../features/shared/rag/rag_admin_links.dart' show openRagAdminModule;

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

  /// A public profile by @username (profile links `https://nextbrain.site/@name`, D-074).
  static Future<void> openProfile(String username) async {
    await navigatorKey.currentState?.push(MaterialPageRoute(
      settings: RouteSettings(name: '/@$username'),
      builder: (_) => PublicProfileScreen(username: username),
    ));
  }

  /// module: profile | course | course_profile | notifications | support (the help center) | my_courses | subscription | org_exams | calendar |
  /// org_reports | org_timetable (needs [orgId]: the organization's Timetable section, on that draft) |
  /// live_lobby ([kind] `session` | `meeting` + [targetId]: that room's admission lobby, live-rooms-spec §4) |
  /// points (top-up approved / rejected → the wallet) | live_plan (plan bought / free time over → the wallet with
  /// the live-meeting plan sheet open, live-rooms-spec §8 – §9; also live_plan_expiring · live_plan_renewed ·
  /// live_plan_renew_failed, Part 3 §15) | rag_learning · rag_alerts (platform admins only: the assistant's Learning
  /// page / the console's Alerts tab, `rag_admin_links.dart`; anyone else the notifications list)
  static Future<void> openModule(String? module, {int? targetId, int? orgId, String? kind}) async {
    final nav = navigatorKey.currentState;
    final ctx = navigatorKey.currentContext;
    if (nav == null || ctx == null || !ctx.mounted) return;
    // Not logged in (or an admin is only LOOKING at a user's app): never navigate on that user's behalf.
    if (!ctx.read<MyAuthProvider>().isAuthenticated || ViewAsState.active) return;
    // The assistant's notices to platform admins (rag_learning · rag_alerts): their own pages, else the list.
    if (await openRagAdminModule(nav, module, role: ctx.read<MyAuthProvider>().currentUser?.role)) return;
    if (!ctx.mounted) return;
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
      case 'support': // "Contact support" from the assistant (Track F) → the help center (complaints)
        if (targetId != null) { // a complaint notification / @mention (D-075) → that complaint
          await nav.push(MaterialPageRoute(
              settings: const RouteSettings(name: '/complaint'),
              builder: (_) => ChangeNotifierProvider<ComplaintProvider>(
                  create: (_) => ComplaintProvider(), child: ComplaintDetailScreen(complaintId: targetId))));
          return;
        }
        await nav.push(MaterialPageRoute(
            settings: const RouteSettings(name: '/help-center'),
            builder: (_) => ChangeNotifierProvider<ComplaintProvider>(create: (_) => ComplaintProvider(), child: const ComplaintsScreen())));
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
      // governance (D-057): an item · a council session · a delegation · a form I must answer
      case 'org_work':
        if (targetId != null) await govOpenItemLink(nav, ctx, targetId, orgId: orgId);
        return;
      case 'org_council':
        if (targetId != null) await govOpenSessionLink(nav, ctx, targetId, orgId: orgId);
        return;
      case 'org_delegations':
        await govOpenDelegationLink(nav, ctx, null, orgId: orgId);
        return;
      case 'org_assignments':
        await govOpenAssignmentsLink(nav);
        return;
      case 'live_lobby': // someone waits at the door of a room I host → the meeting / session with its lobby sheet
        await openLiveLobby(LiveRoomRef.parse(kind, targetId));
        return;
      case 'points':
      case 'live_plan':
      case 'live_plan_expiring': // Part 3 §15: the plan ends within 3 days · renewed · could not renew → the plan
      case 'live_plan_renewed':
      case 'live_plan_renew_failed':
        if (AppConfig.disableList.contains(kPointsFeatureKey)) {
          await nav.pushNamed('/notifications');
          return;
        }
        await nav.push(MaterialPageRoute(
            settings: const RouteSettings(name: '/points'),
            builder: (_) => PointsWalletPage(openPlan: pointsModuleFor(module) == 'live_plan')));
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
      // the wallet / plan notifications (points_topup, live_plan*) when the server names no module
      final module = r['module']?.toString() ?? pointsModuleFor((r['type'] ?? r['related_type'])?.toString());
      final courseId = int.tryParse('${r['course_id'] ?? ''}');
      final orgId = int.tryParse('${r['org_id'] ?? ''}');
      if (orgId != null && await _openOrgFirst(orgId, module == null && courseId == null)) return;
      await openModule(module,
          targetId: courseId ?? int.tryParse('${r['target_id'] ?? ''}'),
          orgId: orgId,
          kind: (r['kind'] ?? r['related_type'])?.toString());
    } catch (_) {/* tapping must never crash */}
  }

  /// The `live_lobby` deep link: a meeting opens the calendar on that meeting, a course session stays where the
  /// host is; the lobby sheet (waiting list, Admit / Reject) opens on top either way.
  static Future<void> openLiveLobby(LiveRoomRef? ref) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (ref == null || AppConfig.disableList.contains(kLiveLobbyFeatureKey)) {
      await nav.pushNamed('/notifications');
      return;
    }
    if (ref.isMeeting && topRouteObserver.currentRoute?.settings.name != '/calendar') {
      unawaited(nav.pushNamed('/calendar', arguments: ref.id));
      await Future<void>.delayed(const Duration(milliseconds: 350)); // let the calendar settle under the sheet
    }
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showLobbySheet(ctx, ref);
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
    // a join request for a room I host: {type: live_lobby, kind, id} (live-rooms-spec §4)
    if (data['type'] == 'live_lobby') {
      return openModule('live_lobby', targetId: int.tryParse('${data['id'] ?? data['target_id'] ?? ''}'), kind: '${data['kind'] ?? ''}');
    }
    // course-profile notifications carry {type: course_profile, id: <course id>} (services/organization notify_users)
    final profile = data['type'] == 'course_profile';
    final timetable = data['type'] == 'org_timetable';        // a draft timetable is ready (schedule_auto / autopilot)
    // the wallet and the plan push {type: points | live_plan | live_plan_expiring | live_plan_renewed | …} (spec §9, §15)
    final module = data['module']?.toString() ??
        (profile ? 'course_profile' : (timetable ? 'org_timetable' : pointsModuleFor(data['type']?.toString())));
    final govPush = (module ?? '').startsWith('org_');        // governance pushes carry {module, id}
    final target = int.tryParse('${data['target_id'] ?? data['course_id'] ?? (profile || timetable || govPush ? data['id'] : null) ?? ''}');
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