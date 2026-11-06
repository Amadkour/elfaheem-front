// lib/core/app_navigator.dart
//
// One place that knows how to open a "module" from a notification tap, a push, a dialog button
// or a shared link. Everything goes through navigatorKey (main.dart) — and, while a role shell is on screen, into
// its visible tab's navigator (D-081: the page keeps the tab bar; [_nav]). Org dashboards, sign-in and other role
// homes still land on the root navigator (AppTabNavigator hands them up).
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter_education_app/core/routing/app_routes.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../core/api_client.dart';
import '../../core/app_mode.dart';
import '../../core/offline/downloads_availability.dart' show linkAvailableHere;
import '../../core/attention/attention_service.dart' show AttentionService, OrgTabRequest;
import '../../features/shared/course_profile/course_profile_hub.dart' show CoursePageLoader;
import '../../features/shared/inbox/inbox_page.dart' show inboxTabFromName, InboxTab;
import '../../features/shared/profile/compalints/complaint_provider.dart' show ComplaintProvider;
import '../../features/shared/profile/compalints/complaints_screen.dart' show ComplaintDetailScreen, ComplaintsScreen;
import '../../features/shared/profile/compalints/complaints_hub_page.dart' show openComplaintsHub;
import '../../features/student/courses/details/course_link_loader.dart';
import '../../features/shared/public_profile/public_profile_page.dart' show PublicProfileScreen;
import '../../main.dart';
import '../top_route_observer.dart' show topRouteObserver;
import 'view_as_state.dart';
import '../../design/app_shell_nav.dart' show AppShellNav;
import '../../design/context_switcher.dart' show closeOrgPages;
import '../../features/org/org_providers.dart' show OrgSession;
import '../../features/org/org_invitation_prompt.dart' show OrgInvitationPrompt;
import '../../features/org/org_invitations.dart' show invitationsFeatureKey;
import '../../features/org/governance/gov_wiring.dart' deferred as gov_wiring;
import '../../features/org/advising/adv_wiring.dart' deferred as adv_wiring;
import '../../features/shared/live/live_room.dart' show LiveRoomRef, kLiveLobbyFeatureKey;
import '../../features/shared/live/live_lobby_sheets.dart' show showLobbySheet;
import '../../features/shared/points/points_api.dart' show kPointsFeatureKey, pointsModuleFor;
import '../../features/shared/points/points_wallet_page.dart' show PointsWalletPage;
import '../../features/shared/rag/rag_admin_links.dart' deferred as rag_admin_links;
import '../../features/shared/identity/identity_request_gate.dart' show openIdentityRequestsFromLink;
import '../../features/shared/exam_engine/paper/exam_setup_wizard.dart' deferred as exam_setup_wizard;
import '../../features/shared/exam_engine/exam_notice.dart' deferred as exam_notice;
import '../../features/admin/app_releases/app_releases_page.dart' show AppReleasesPage, kAppReleasesFeatureKey;

class AppNavigator {
  AppNavigator._();

  /// AppShell listens to this: set it to a ShellPage.id (e.g. 'profile') to switch tab.
  static final ValueNotifier<String?> requestedTab = ValueNotifier<String?>(null);

  /// Teachers have their own course screen. Set this once (e.g. in main()) to build it:
  ///   AppNavigator.teacherCourseBuilder = (course) => TeacherCourseScreen(course: course);
  /// Left null → teachers also get the shared CourseDetailScreen.
  static Widget Function(Map<String, dynamic> courseJson)? teacherCourseBuilder;

  /// Where a deep link pushes: the visible tab of the role shell on screen, else the root navigator.
  static NavigatorState? get _nav => AppShellNav.pushTarget() ?? navigatorKey.currentState;

  /// The org dashboard is the root navigator's top (its own tab pages included).
  static bool get _onOrgDashboard => topRouteObserver.rootRoute?.settings.name == '/org_dashboard';

  /// Runs [run] once the deferred part [id] is loaded (web: downloaded on the first deep link into it).
  static Future<T> _deferred<T>(String id, Future<void> Function() load, Future<T> Function() run) async {
    await loadDeferred(id, load);
    return run();
  }

  /// `exam:<id>` → the engine exam id (a copy of exam_setup.dart's `examIdFromRef`, which sits in a deferred part).
  static int? _examIdFromRef(Object? ref) {
    final m = RegExp(r'^exam:(\d+)$').firstMatch('${ref ?? ''}');
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static Future<void> openCourse(int courseId, {int? ref}) async {
    await _nav?.push(MaterialPageRoute(
      settings: const RouteSettings(name: '/course-by-id'),
      builder: (_) => CourseLinkLoader(courseId: courseId, ref: ref),
    ));
  }

  /// A public profile by @username (profile links `https://nextbrain.site/@name`, D-074).
  static Future<void> openProfile(String username) async {
    await _nav?.push(MaterialPageRoute(
      settings: RouteSettings(name: '/@$username'),
      builder: (_) => PublicProfileScreen(username: username),
    ));
  }

  /// module: profile | course | course_profile | notifications (the inbox page on its Notifications tab) | inbox ([kind]
  /// names the tab: todo · notifications · announcements / news / offers · done; To do by default) | support (the help
  /// center) | my_courses | subscription | org_exams | calendar |
  /// org_reports | org_timetable (needs [orgId]: the organization's Timetable section, on that draft) |
  /// live_lobby ([kind] `session` | `meeting` + [targetId]: that room's admission lobby, live-rooms-spec §4) |
  /// points (top-up approved / rejected → the wallet) | live_plan (plan bought / free time over → the wallet with
  /// the live-meeting plan sheet open, live-rooms-spec §8 – §9; also live_plan_expiring · live_plan_renewed ·
  /// live_plan_renew_failed, Part 3 §15) | rag_learning · rag_alerts (platform admins only: the assistant's Learning
  /// page / the console's Alerts tab, `rag_admin_links.dart`; anyone else the notifications list) | app_release ·
  /// app_releases (super admins only, D-143: [targetId] = the release → its page, else App versions)
  ///
  /// org_invitations (a push / notification for a phone invitation; no org_id, I am not a member yet) → My organizations with the invitations card.
  ///
  /// exam_notice (D-247; also exam_appeal · exam_result): [data] is the push / notification target (`exam_id`, `attempt_id`,
  /// `kind` …), else [targetId] is the exam.
  static Future<void> openModule(String? module, {int? targetId, int? orgId, String? kind, Map<String, dynamic> data = const {}}) async {
    final root = navigatorKey.currentState;
    final ctx = navigatorKey.currentContext;
    final nav = _nav;
    if (root == null || nav == null || ctx == null || !ctx.mounted) return;
    // Not logged in (or an admin is only LOOKING at a user's app): never navigate on that user's behalf.
    if (!ctx.read<MyAuthProvider>().isAuthenticated || ViewAsState.active) return;
    // The assistant's notices to platform admins (rag_learning · rag_alerts): their own pages, else the list.
    if (await _deferred('rag_admin_links', rag_admin_links.loadLibrary, () => rag_admin_links.openRagAdminModule(nav, module, role: ctx.read<MyAuthProvider>().currentUser?.role))) return;
    if (!ctx.mounted) return;
    // the Downloads page lives in the phone / desktop app only: on the web such a link stays where it is
    if (!linkAvailableHere(module)) return;
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
              builder: (_) => CoursePageLoader(courseId: targetId))); // the one course page, at the smart tab (D-111)
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
        // the platform's admin console for the roles on the admin dashboard; everyone else the profile's
        // Complaints page (New complaint · My complaints · To resolve, D-086)
        if (const ['admin', 'super-admin', 'developer'].contains(ctx.read<MyAuthProvider>().currentUser?.role)) {
          await nav.push(MaterialPageRoute(
              settings: const RouteSettings(name: '/help-center'),
              builder: (_) => ChangeNotifierProvider<ComplaintProvider>(create: (_) => ComplaintProvider(), child: const ComplaintsScreen())));
        } else {
          await openComplaintsHub(nav);
        }
        return;
      case 'app_release': // App versions (D-143): a build finished / failed → that release; super admins only
      case 'app_releases':
        if (ctx.read<MyAuthProvider>().currentUser?.role != 'super-admin' || AppConfig.disableList.contains(kAppReleasesFeatureKey)) {
          await nav.pushNamed('/notifications');
        } else if (targetId != null) {
          await nav.push(MaterialPageRoute(
              settings: RouteSettings(name: '${AppReleasesPage.routeName}/$targetId'), builder: (_) => deferredAppReleaseDetail(targetId)));
        } else {
          await nav.push(MaterialPageRoute(settings: const RouteSettings(name: AppReleasesPage.routeName), builder: (_) => deferredAppReleases()));
        }
        return;
      case 'notifications':
        await nav.pushNamed('/notifications');
        return;
      case 'inbox': // a to-do / an announcement / an offer → the inbox page on that tab
        await nav.pushNamed('/inbox', arguments: inboxTabFromName(kind) ?? InboxTab.todo);
        return;
      case 'subscription':
        await nav.pushNamed('/subscription');
        return;
      case 'identity_requests': // a teacher needs an exam identifier → the student's dialog (D-150)
        return openIdentityRequestsFromLink(root);
      case 'exam':
      case 'exam_notice': // an appeal / results published / batch or session done (D-247): the screen it points at
      case 'omr_batch': // scan batch done (data.module)
      case 'mark_session': // grade-review session done
      case 'exam_appeal':
      case 'exam_result':
      case 'exam_results':
        if (!await _deferred('exam_notice', exam_notice.loadLibrary, () => exam_notice.openExamNotice(nav, exam_notice.ExamNotice.parse({...data, if (data['kind'] == null && kind != null) 'kind': kind, if (data['exam_id'] == null && data['data'] == null) 'exam_id': targetId, if (data['org_id'] == null) 'org_id': orgId}, module: module),
            teacher: const ['teacher', 'org-admin', 'org-staff', 'admin', 'super-admin'].contains(ctx.read<MyAuthProvider>().currentUser?.role)))) {
          await nav.pushNamed('/notifications');
        }
        return;
      case 'exam_identifiers': // a duplicate identifier → the exam's setup on its students step
        return _deferred('exam_setup_wizard', exam_setup_wizard.loadLibrary, () => exam_setup_wizard.openExamIdentifiersFromLink(nav, targetId));
      case 'calendar': // meeting invitation / answer → the calendar on that meeting
        await nav.pushNamed('/calendar', arguments: targetId);
        return;
      case 'org_exams': // "exam timetable published" → My exams (the organization is already open)
        await nav.push(MaterialPageRoute(builder: (_) => deferredMyExams()));
        return;
      case 'org_invitation': // an organization invited an existing account (C7): the accept / reject dialog for it
        if (AppConfig.orgsEnabled && !AppConfig.disableList.contains(invitationsFeatureKey)) {
          await OrgInvitationPrompt.instance.showFor(targetId);
          return;
        }
        await nav.pushNamed(AppRoutes.location(AppRoutes.orgMemberships.id));
        return;
      case 'org_invitations': // an invitation to join an organization (phone invites, push + notification tap) → My organizations, which shows the invitations card
        await nav.pushNamed(AppRoutes.location(AppRoutes.orgMemberships.id));
        return;
      case 'org_reports': // a report sent to me → Received reports
        await nav.push(MaterialPageRoute(builder: (_) => deferredOrgReceivedReports()));
        return;
      case 'org_timetable': // a draft timetable is ready / failed → the org dashboard's Timetable section on it
        if (orgId == null) {
          await nav.pushNamed('/notifications');
          return;
        }
        AttentionService.instance.orgTabRequest.value = OrgTabRequest(orgId, 'timetable', targetId != null ? 'open:$targetId' : 'generate');
        if (_onOrgDashboard) {
          WidgetsBinding.instance.addPostFrameCallback((_) => AppShellNav.popVisibleToRoot()); // the section, not a page above it
        } else {
          await root.pushNamed('/org_dashboard');
        }
        return;
      // academic advising (D-289): an urgent flag · an escalation · a review due names the student → their 360
      case 'advising':
        final inner = data['data'];
        final member = int.tryParse('${data['member_id'] ?? (inner is Map ? inner['member_id'] : null) ?? ''}');
        // Phase 6 early warning: a notice naming a screen (alerts · workspace · advisor) or "propose a meeting"
        final flat = <String, dynamic>{...data, if (inner is Map) for (final e in inner.entries) '${e.key}': e.value};
        if (orgId != null && !AppConfig.disableList.contains('org.advising') && (flat['screen'] != null || flat['action'] == 'propose_meeting')) {
          if (await _deferred('adv_wiring', adv_wiring.loadLibrary, () => adv_wiring.advOpenScreenLink(nav, orgId: orgId, data: flat))) return;
        }
        if (member != null && orgId != null && !AppConfig.disableList.contains('org.advising')) {
          await _deferred('adv_wiring', adv_wiring.loadLibrary, () => adv_wiring.advOpenStudentLink(nav, orgId: orgId, memberId: member));
        } else {
          await nav.pushNamed('/notifications');
        }
        return;
      // governance (D-057): an item · a council session · a delegation · a form I must answer
      case 'org_work':
        if (targetId != null) await _deferred('gov_wiring', gov_wiring.loadLibrary, () => gov_wiring.govOpenItemLink(nav, ctx, targetId, orgId: orgId));
        return;
      case 'org_council':
        if (targetId != null) await _deferred('gov_wiring', gov_wiring.loadLibrary, () => gov_wiring.govOpenSessionLink(nav, ctx, targetId, orgId: orgId));
        return;
      case 'org_delegations':
        await _deferred('gov_wiring', gov_wiring.loadLibrary, () => gov_wiring.govOpenDelegationLink(nav, ctx, null, orgId: orgId));
        return;
      case 'org_assignments':
        await _deferred('gov_wiring', gov_wiring.loadLibrary, () => gov_wiring.govOpenAssignmentsLink(nav));
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
      case 'profile': // the account tab (N10: '/profile' used to open the edit-account form)
      case 'my_courses':
      // These are tabs inside the dashboards: pop to the root and ask the AppShell to switch (the shell then shows
      // that tab's root page, D-081).
        root.popUntil((r) => r.isFirst);
        requestedTab.value = null; // re-fire even if the same id is requested twice
        requestedTab.value = module;
        AppShellNav.popVisibleToRootAfterSwitch();
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
          kind: (r['kind'] ?? r['related_type'])?.toString(),
          data: Map<String, dynamic>.from(r));
    } catch (_) {/* tapping must never crash */}
  }

  /// The `live_lobby` deep link: a meeting opens the calendar on that meeting, a course session stays where the
  /// host is; the lobby sheet (waiting list, Admit / Reject) opens on top either way.
  static Future<void> openLiveLobby(LiveRoomRef? ref) async {
    final nav = _nav;
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
        (profile ? 'course_profile' : (timetable ? 'org_timetable' : (data['type'] == 'exam_notice' ? 'exam_notice' : data['type'] == 'org_invitation' ? 'org_invitation' : pointsModuleFor(data['type']?.toString()))));
    final govPush = (module ?? '').startsWith('org_');        // governance pushes carry {module, id}
    final target = int.tryParse('${data['target_id'] ?? data['course_id'] ?? (profile || timetable || govPush ? data['id'] : null) ?? (module == 'org_invitation' ? data['related_id'] : null) ?? ''}') ?? _examIdFromRef(data['exam_ref']);
    final orgId = int.tryParse('${data['org_id'] ?? ''}');
    if (orgId != null && await _openOrgFirst(orgId, module == null && target == null)) return;
    if (module != null) {
      return openModule(module,
          targetId: target, orgId: orgId, kind: module == 'inbox' ? '${data['tab'] ?? data['segment'] ?? data['kind'] ?? ''}' : null, data: data);
    }
    if (target != null) return openCourse(target);
    await _nav?.pushNamed('/notifications');
  }

  /// Organization notification (push data / tap target carry `org_id`): open that organization BEFORE routing, so the
  /// screen it leads to shows that organization (its timezone and feature offs too). The organization is selected in
  /// BOTH [AppModeController] and [OrgSession] (before, only the mode followed, so a push for org B opened B's page
  /// under A's dashboard), and when it is a different organization from the one open, A's org pages close first.
  /// An organization where I am staff opens its dashboard ([AppModeController.opensDashboard]); one where I study,
  /// the member home. Returns true when it already navigated (nothing more specific to open: back to the home root /
  /// the dashboard, now in that organization). Never throws: tapping must never crash.
  static Future<bool> _openOrgFirst(int orgId, bool homeOnly) async {
    if (!AppConfig.orgsEnabled) return false;
    final ctl = AppModeController.instance;
    OrgSession? session;
    try {
      session = navigatorKey.currentContext?.read<OrgSession>();
    } catch (_) {/* no provider in scope */}
    bool? staff;
    try {
      // cold start: the memberships are not known yet - wait for them (bounded) before deciding staff or student
      if (!ctl.loaded) await ctl.ready();
      await ctl.openOrg(orgId);
      staff = ctl.opensDashboardFor(orgId);
      // the overview does not list it (it failed / is slow): the dashboard's own list decides
      if (staff == null && session != null) {
        if (!session.loaded) await session.load().timeout(const Duration(seconds: 6), onTimeout: () {});
        if (session.loaded && !session.loadFailed) staff = session.items.any((o) => o['id'] == orgId);
      }
      final other = session != null && session.currentId != null && session.currentId != orgId;
      // an organization where I only study is never selected in the dashboard's session
      if (staff != false) session?.open(orgId);
      if (other) {
        // org A -> org B: A's pages go, B is selected (OrgSession.select clears A's context)
        final root = navigatorKey.currentState;
        if (root != null) closeOrgPages(root);
      }
    } catch (_) {/* never block the tap */}
    if (!homeOnly) return false;
    final root = navigatorKey.currentState;
    if (staff == true) {
      // the staff dashboard of that organization: reuse the one on screen, else open it
      if (_onOrgDashboard) {
        if (root != null) closeOrgPages(root);
      } else {
        root?.popUntil((r) => r.isFirst);
        if (topRouteObserver.rootRoute?.settings.name != '/org_dashboard') unawaited(root?.pushNamed('/org_dashboard'));
      }
      return true;
    }
    root?.popUntil((r) => r.isFirst);
    AppShellNav.popVisibleToRoot(); // and the tab on screen back to its own first page
    return true;
  }

  static String get homeRoute {
    final ctx = navigatorKey.currentContext;
    return ctx == null ? '/login' : ctx.read<MyAuthProvider>().homeRoute;
  }
}