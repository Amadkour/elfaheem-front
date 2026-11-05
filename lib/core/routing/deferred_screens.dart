// lib/core/routing/deferred_screens.dart
//
// Deferred loading (web start-up). `main.dart.js` used to hold the whole app (18 MB: the organization console, the
// admin console, the exam authoring tools, the export designers, the live room ...), so every visitor paid for all
// of it before the first frame. A screen only one role (or one rare action) opens is now a `deferred as` library:
// dart2js moves it, and everything only it reaches, into a `main.dart.js_N.part.js` that is fetched the first time
// the screen opens. On Android / iOS `loadLibrary()` completes at once, so nothing changes there.
//
// Rules
//   * An eager file never builds a heavy screen directly: it calls one of the factories below.
//   * Types and constants a caller needs stay in eager libraries (a `deferred as` prefix can't give a type or a
//     const), so the factories take plain values only.
//   * [DeferredPage] shows the look the person already sees while the part downloads (see [DeferredLook]) and a
//     retry when the download fails; a page draws nothing for its first 150 ms, so a fast load never flashes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_education_app/design/boot_splash.dart' show BootSplash;
import 'package:flutter_education_app/utils/widget/url_strategy.dart' show reloadPage;
import 'package:flutter_education_app/features/shared/course_profile/course_profile_hub.dart' show CourseProfileHub;
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart' show TeacherCourse;

import '../../features/admin/admin_dashboard_screen.dart' deferred as admin_dashboard;
import '../../features/admin/app_releases/app_release_detail.dart' deferred as app_release_detail;
import '../../features/admin/app_releases/app_releases_page.dart' deferred as app_releases_page;
import '../../features/org/org_academic_pages.dart' deferred as org_academic;
import '../../features/org/org_access_joining.dart' deferred as org_access_joining;
import '../../features/org/org_availability_pages.dart' deferred as org_availability;
import '../../features/org/org_billing_page.dart' deferred as org_billing_page;
import '../../features/org/org_dashboard_screen.dart' deferred as org_dashboard;
import '../../features/org/org_invitations_pages.dart' deferred as org_invitations_pages;
import '../../features/org/org_member_dashboard.dart' deferred as org_member_dashboard;
import '../../features/org/org_member_pages.dart' deferred as org_member_pages;
import '../../features/org/org_member_space.dart' deferred as org_member_space;
import '../../features/org/org_my_exams.dart' deferred as org_my_exams;
import '../../features/org/org_reports/report_page.dart' deferred as org_report_page;
import '../../features/parent/parent_dashboard_screen.dart' deferred as parent_dashboard;
import '../../features/parent/parent_org_view.dart' deferred as parent_org_view;
import '../../features/teacher/analysis/exam/teacher_exam_hub_screen.dart' deferred as exam_hub;
import '../../features/teacher/certificates/certificate_requests_screen.dart' deferred as cert_requests;
import '../../features/teacher/certificates/designer/certificate_designs_screen.dart' deferred as cert_designs;
import '../../features/teacher/courses/course_form_screen.dart' deferred as course_form;
import '../../features/teacher/dashboard/teacher_dashboard_screen.dart' deferred as teacher_dashboard;
import '../../features/teacher/data_lab/data_lab_screen.dart' deferred as data_lab;
import '../../features/teacher/sessions/live/join_args.dart' show JoinArgs;
import '../../features/teacher/sessions/live/prejoin.dart' deferred as prejoin;
import '../../features/teacher/sessions/sessions_screen.dart' deferred as sessions;

/// What the person sees while a part downloads.
enum DeferredLook {
  /// A role home right after sign-in / app start: the boot splash they were just looking at.
  splash,

  /// An inner page: the page background, then (after 150 ms) list skeletons.
  page,

  /// A block inside a page that already shows this skeleton while its data loads (the organization home).
  inline,
}

/// How long a page placeholder stays blank before the skeleton appears.
const Duration kDeferredQuietTime = Duration(milliseconds: 150);

final Map<String, Future<void>> _loading = {};
final Set<String> _loaded = {};

/// Loads the part [id] once (every caller shares the future); a failure is forgotten so the next call retries.
Future<void> loadDeferred(String id, Future<void> Function() load) {
  if (_loaded.contains(id)) return SynchronousFuture<void>(null);
  return _loading[id] ??= load().then((_) {
    _loaded.add(id);
    _loading.remove(id);
  }, onError: (Object e, StackTrace s) {
    _loading.remove(id);
    Error.throwWithStackTrace(e, s);
  });
}

/// Forgets what was loaded (tests).
void resetDeferredLoads() {
  _loading.clear();
  _loaded.clear();
}

/// Builds [builder] once the part [id] is loaded. [load] is the library's `loadLibrary`.
class DeferredPage extends StatefulWidget {
  const DeferredPage({super.key, required this.id, required this.load, required this.builder, this.look = DeferredLook.page});

  /// Names the part (one per library) so a second open builds at once.
  final String id;
  final Future<void> Function() load;
  final WidgetBuilder builder;
  final DeferredLook look;

  @override
  State<DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<DeferredPage> {
  bool _ready = false, _failed = false, _quiet = true;
  int _failures = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ready = _loaded.contains(widget.id);
    if (!_ready) _start();
  }

  void _start() {
    _failed = false;
    _quiet = widget.look == DeferredLook.page;
    _timer?.cancel();
    if (_quiet) {
      _timer = Timer(kDeferredQuietTime, () {
        if (mounted) setState(() => _quiet = false);
      });
    }
    loadDeferred(widget.id, widget.load).then((_) {
      if (mounted) setState(() => _ready = true);
    }, onError: (Object _) {
      _failures++;
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.builder(context);
    // a part that fails twice is most likely gone from the server (a deploy since this page loaded): the retry reloads
    // the page onto the new build instead of asking for the old file again
    if (_failed) return _DeferredFailed(onRetry: () => kIsWeb && _failures >= 2 ? reloadPage() : setState(_start));
    if (widget.look == DeferredLook.splash) return const BootSplash();
    if (widget.look == DeferredLook.inline) return const SizedBox(height: 320, child: AppListSkeleton(items: 4));
    return Scaffold(
      backgroundColor: context.colors.background,
      body: _quiet ? const SizedBox.shrink() : const SafeArea(child: AppListSkeleton()),
    );
  }
}

/// A small block of an eager page that lives in a deferred part: nothing while it downloads, nothing if it fails
/// (the block is a nicety), the block once loaded.
class DeferredSlot extends StatefulWidget {
  const DeferredSlot({super.key, required this.id, required this.load, required this.builder});
  final String id;
  final Future<void> Function() load;
  final WidgetBuilder builder;

  @override
  State<DeferredSlot> createState() => _DeferredSlotState();
}

class _DeferredSlotState extends State<DeferredSlot> {
  late bool _ready = _loaded.contains(widget.id);

  @override
  void initState() {
    super.initState();
    if (!_ready) {
      loadDeferred(widget.id, widget.load).then((_) {
        if (mounted) setState(() => _ready = true);
      }, onError: (Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) => _ready ? widget.builder(context) : const SizedBox.shrink();
}

class _DeferredFailed extends StatelessWidget {
  const _DeferredFailed({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ar = AppConfig.lang == 'ar';
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 48),
            const SizedBox(height: 12),
            Text(ar ? 'تعذّر تحميل الصفحة. تحقق من الاتصال وحاول مجدداً.' : 'This page could not be loaded. Check the connection and try again.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(ar ? 'إعادة المحاولة' : 'Retry')),
          ]),
        ),
      ),
    );
  }
}

// ─── role homes (main.dart `_router`) ───────────────────────────────────────────────────────────────────────────

Widget deferredAdminDashboard() => DeferredPage(
    id: 'admin_dashboard', load: admin_dashboard.loadLibrary, look: DeferredLook.splash, builder: (_) => admin_dashboard.AdminDashboardScreen());

Widget deferredTeacherDashboard() => DeferredPage(
    id: 'teacher_dashboard', load: teacher_dashboard.loadLibrary, look: DeferredLook.splash, builder: (_) => teacher_dashboard.TeacherDashboardScreen());

Widget deferredParentDashboard() => DeferredPage(
    id: 'parent_dashboard', load: parent_dashboard.loadLibrary, look: DeferredLook.splash, builder: (_) => parent_dashboard.ParentDashboardScreen());

Widget deferredOrgDashboard() => DeferredPage(
    id: 'org_dashboard', load: org_dashboard.loadLibrary, look: DeferredLook.splash, builder: (_) => org_dashboard.OrgDashboardScreen());

Widget deferredOrgMemberDashboard({int? orgId}) => DeferredPage(
    id: 'org_member_dashboard',
    load: org_member_dashboard.loadLibrary,
    look: DeferredLook.splash,
    builder: (_) => org_member_dashboard.OrgMemberDashboardScreen(orgId: orgId));

/// `/my-organizations` (D-283): memberships, join requests and the invitations waiting for me.
Widget deferredOrgMemberships() => DeferredPage(
    id: 'org_memberships', load: org_member_pages.loadLibrary, builder: (_) => org_member_pages.OrgMembershipScreen());

/// `/j/<CODE>` (D-283): the join page with the code filled in; a signed-out visitor is asked to sign in first.
Widget deferredOrgJoinLink({required String code}) => DeferredPage(
    id: 'org_join_link', load: org_access_joining.loadLibrary, builder: (_) => org_access_joining.OrgJoinLinkPage(code: code));

/// `/i/<token>` (D-283): an organization invitation; the preview needs no account, accepting does.
Widget deferredOrgInvitation({required String token}) => DeferredPage(
    id: 'org_invitation', load: org_invitations_pages.loadLibrary, builder: (_) => org_invitations_pages.OrgInviteePage(token: token));

/// Invitations (D-283): the invitee's page, the admin's list / invite sheet and "my invitations" card are ONE part,
/// fetched when the first of them opens; the eager org screens reach them only through these.
const _kInvitationsPart = 'org_invitation';
Future<void> _loadInvitationsPart() => loadDeferred(_kInvitationsPart, org_invitations_pages.loadLibrary);

/// The invite sheet (`GET`-free: it only draws a form); resolves when the sheet is closed.
Future<void> showDeferredOrgInviteSheet(BuildContext context, {required int orgId, String orgName = '', String initialRole = 'student'}) async {
  await _loadInvitationsPart();
  if (!context.mounted) return;
  await org_invitations_pages.showOrgInviteSheet(context, orgId: orgId, orgName: orgName, initialRole: initialRole);
}

/// The admin's list of sent invitations (push it inside the OrgSession provider).
Widget deferredOrgInvitationsPage({required int orgId, String orgName = ''}) => DeferredPage(
    id: _kInvitationsPart,
    load: org_invitations_pages.loadLibrary,
    builder: (_) => org_invitations_pages.OrgInvitationsPage(orgId: orgId, orgName: orgName));

/// "Invitations waiting for me" on the memberships page; nothing while the part downloads (or if it can't).
Widget deferredOrgMyInvitationsCard({VoidCallback? onChanged}) => DeferredSlot(
    id: _kInvitationsPart,
    load: org_invitations_pages.loadLibrary,
    builder: (_) => org_invitations_pages.OrgMyInvitationsCard(onChanged: onChanged == null ? null : (_) => onChanged()));

/// The organization's billing page (read-only), pushed from the dashboard's settings.
Widget deferredOrgBillingPage({required int? orgId}) =>
    DeferredPage(id: 'org_billing', load: org_billing_page.loadLibrary, builder: (_) => org_billing_page.OrgBillingPage(orgId: orgId));

/// The parent home's "my children's organizations" strip: asks nothing (and downloads nothing) while organizations
/// are off or `parent.org_view` is switched off; draws nothing while the part downloads.
Widget deferredParentOrgChildrenCard() {
  if (!AppConfig.orgsEnabled || AppConfig.disableList.contains('parent.org_view')) return const SizedBox.shrink();
  return const _ParentOrgChildrenSlot();
}

/// The card's request starts with the parent home (in parallel with its own call), not after the card's deferred
/// part arrived: on the web that part is one more round trip. The first load reads that answer; Retry calls again.
class _ParentOrgChildrenSlot extends StatefulWidget {
  const _ParentOrgChildrenSlot();

  @override
  State<_ParentOrgChildrenSlot> createState() => _ParentOrgChildrenSlotState();
}

class _ParentOrgChildrenSlotState extends State<_ParentOrgChildrenSlot> {
  static const _path = '/api/v1/org/parent/children';
  Future<dynamic>? _first;

  @override
  void initState() {
    super.initState();
    _first = ApiClient().get(_path)..ignore();       // its error is read by the card's first load
  }

  Future<dynamic> _answer() {
    final first = _first;
    _first = null;
    return first ?? ApiClient().get(_path);
  }

  @override
  Widget build(BuildContext context) => DeferredSlot(
      id: 'parent_org_view', load: parent_org_view.loadLibrary,
      // a closure, not a method: a deferred type cannot be named in a declaration
      builder: (_) => parent_org_view.ParentOrgChildrenCard(
          loader: () async => parent_org_view.parseParentChildren(await _answer())));
}

// ─── inner pages ────────────────────────────────────────────────────────────────────────────────────────────────

Widget deferredTeacherSessionsScreen({bool? expandDetails, CourseProfileHub? profileHub, String? initialTab}) => DeferredPage(
    id: 'sessions',
    load: sessions.loadLibrary,
    builder: (_) => sessions.TeacherSessionsScreen(expandDetails: expandDetails, profileHub: profileHub, initialTab: initialTab));

Widget deferredCourseForm({TeacherCourse? course}) =>
    DeferredPage(id: 'course_form', load: course_form.loadLibrary, builder: (_) => course_form.CourseFormScreen(course: course));

Widget deferredTeacherExamHub({
  required int courseId,
  required String courseTitle,
  int? initialSessionId,
  bool openCreateOnStart = false,
  int? orgId,
}) =>
    DeferredPage(
        id: 'exam_hub',
        load: exam_hub.loadLibrary,
        builder: (_) => exam_hub.TeacherExamHubScreen(
            courseId: courseId, courseTitle: courseTitle, initialSessionId: initialSessionId, openCreateOnStart: openCreateOnStart, orgId: orgId));

Widget deferredDataLab({required int courseId, required String courseTitle}) =>
    DeferredPage(id: 'data_lab', load: data_lab.loadLibrary, builder: (_) => data_lab.DataLabScreen(courseId: courseId, courseTitle: courseTitle));

Widget deferredCertificateDesigns({int? orgId, int? certificateId}) => DeferredPage(
    id: 'cert_designs', load: cert_designs.loadLibrary, builder: (_) => cert_designs.CertificateDesignsScreen(orgId: orgId, certificateId: certificateId));

Widget deferredCertificateRequests() =>
    DeferredPage(id: 'cert_requests', load: cert_requests.loadLibrary, builder: (_) => cert_requests.CertificateRequestsScreen());

Widget deferredOrgReceivedReports() =>
    DeferredPage(id: 'org_report_page', load: org_report_page.loadLibrary, builder: (_) => org_report_page.OrgReceivedReportsPage());

Widget deferredAppReleases() =>
    DeferredPage(id: 'app_releases_page', load: app_releases_page.loadLibrary, builder: (_) => app_releases_page.AppReleasesPage());

Widget deferredAppReleaseDetail(int id) =>
    DeferredPage(id: 'app_release_detail', load: app_release_detail.loadLibrary, builder: (_) => app_release_detail.AppReleaseDetailPage(id: id));

/// The organization home block inside the student / teacher home (Organization mode).
Widget deferredOrgMemberHome({bool showPickerInHero = true}) => DeferredPage(
    id: 'org_member_dashboard',
    load: org_member_dashboard.loadLibrary,
    look: DeferredLook.inline,
    builder: (_) => org_member_dashboard.OrgMemberHome(showPickerInHero: showPickerInHero));

/// The live room's "ready to join" page (LiveKit, the room, the whiteboard: one deferred part).
Widget deferredPreJoin({required JoinArgs args, bool startMic = true, bool? startCam}) => DeferredPage(
    id: 'prejoin', load: prejoin.loadLibrary, builder: (_) => prejoin.PreJoinPage(args: args, startMic: startMic, startCam: startCam));

// ─── organization member pages opened from the inbox / the member home ─────────────────────────────────────────────

Widget deferredOrgMemberSpace({required Map<String, dynamic> org, int initialTab = 0}) => DeferredPage(
    id: 'org_member_space', load: org_member_space.loadLibrary, builder: (_) => org_member_space.OrgMemberSpace(org: org, initialTab: initialTab));

Widget deferredOrgFormFill(int formId) =>
    DeferredPage(id: 'org_member_space', load: org_member_space.loadLibrary, builder: (_) => org_member_space.OrgFormFillScreen(formId: formId));

Widget deferredAvailabilityRequest(int requestId) => DeferredPage(
    id: 'org_availability', load: org_availability.loadLibrary, builder: (_) => org_availability.AvailabilityRequestScreen(requestId: requestId));

Widget deferredMyAcademicPath(int orgId) =>
    DeferredPage(id: 'org_academic', load: org_academic.loadLibrary, builder: (_) => org_academic.MyAcademicPathPage(orgId: orgId));

Widget deferredMyExams({int? orgId}) =>
    DeferredPage(id: 'org_my_exams', load: org_my_exams.loadLibrary, builder: (_) => org_my_exams.MyExamsScreen(orgId: orgId));

/// The approval sheet of the member home (needs the organization entry): loads the member dashboard part first.
Future<void> openOrgApprovalDeferred(BuildContext context, int orgId, String what) async {
  await loadDeferred('org_member_dashboard', org_member_dashboard.loadLibrary);
  if (!context.mounted) return;
  return org_member_dashboard.openOrgApproval(context, orgId, what);
}
