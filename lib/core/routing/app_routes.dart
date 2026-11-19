// The app's route registry (D-170): every page that has a URL, under a STABLE id.
//
// The id is the page's name everywhere: the browser URL is built from it, the router opens it, and it is the `page_id`
// the Info button and the RAG assistant's deep links use ("open course 12" = `AppRoutes.location('course', {'courseId':
// 12})`). Ids never change once released (a renamed page keeps its id); a URL may get a new spelling, with the old one
// kept in `aliases` so bookmarks and shared links still open.
//
// Pure Dart (no widgets): the screens are built by main.dart's router from the [AppRouteMatch] — importing every screen
// here would pull them all into the first download (deferred loading, docs/perf/deferred-loading.md).
//
//   AppRoutes.match('/courses/12')        → AppRouteMatch(course, {courseId: '12'})
//   AppRoutes.location('course', {...})   → '/courses/12'
//   AppRoutes.locationOf(settings)        → the URL of a pushed route ('/course-profile' + 12 → '/courses/12'), or null
//                                           for a route without one (the page keeps the URL of the page under it)
//   AppRoutes.tabLocation(home, tab)      → '/dashboard/my-courses' (a role home on one of its tabs)
//
// Pages pushed as plain `MaterialPageRoute`s (most of the app, D-081) have no URL of their own: they keep the URL of the
// page under them, and Back / Forward still step through them one by one (lib/core/routing/web_history.dart). To give
// such a page a URL, add it here and open it by name (or with `settings: RouteSettings(name: AppRoutes.location(…))`).
library;

/// One page with a URL.
class AppRouteDef {
  const AppRouteDef(this.id, this.path, {this.aliases = const [], this.signIn = true, this.description = ''});

  /// The stable page id (snake_case, dotted by area): the route name, the Info button's and the assistant's `page_id`.
  final String id;

  /// The URL pattern: `/courses/:courseId` (a `:name` segment is a parameter).
  final String path;

  /// Older spellings of the same page (still opened, never produced).
  final List<String> aliases;

  /// Needs an account (the router's guard sends a signed-out person to the login, then back here).
  final bool signIn;

  /// What the page is, for people reading this file and for the assistant's page list.
  final String description;

  List<String> get params => [
        for (final s in path.split('/'))
          if (s.startsWith(':')) s.substring(1),
      ];
}

/// A URL matched to a page.
class AppRouteMatch {
  const AppRouteMatch(this.route, this.params, this.query);

  final AppRouteDef route;
  final Map<String, String> params;
  final Map<String, String> query;

  String get id => route.id;

  int? intParam(String name) => int.tryParse(params[name] ?? '');
}

class AppRoutes {
  AppRoutes._();

  // ── Sign-in ────────────────────────────────────────────────────────────────
  static const login = AppRouteDef('auth.login', '/login', signIn: false, description: 'Sign in');
  static const register = AppRouteDef('auth.register', '/register', signIn: false, description: 'Create an account');
  static const forgotPassword =
      AppRouteDef('auth.forgot_password', '/forgot-password', signIn: false, description: 'Reset the password');
  static const privacy = AppRouteDef('legal.privacy', '/privacy', signIn: false, description: 'Privacy policy (D-308)');
  static const terms = AppRouteDef('legal.terms', '/terms', signIn: false, description: 'Terms of service (D-308)');

  // ── Role homes (each tab: `<home>/<tab>`, see [tabLocation]) ──────────────
  static const studentHome = AppRouteDef('home.student', '/dashboard', signIn: false, description: 'Student home');
  static const teacherHome = AppRouteDef('home.teacher', '/teacher_dashboard', description: 'Teacher home');
  static const adminHome = AppRouteDef('home.admin', '/admin_dashboard', description: 'Admin home');
  static const parentHome = AppRouteDef('home.parent', '/parent_dashboard', description: 'Parent home');
  static const orgHome = AppRouteDef('home.org', '/org_dashboard',
      description: 'Organization dashboard (every non-student org role, D-103)');

  // ── Pages ─────────────────────────────────────────────────────────────────
  static const course = AppRouteDef('course', '/courses/:courseId',
      aliases: ['/course-profile/:courseId'], description: 'The course page (D-111), every role');
  static const orgMember =
      AppRouteDef('org.member', '/org/:orgId', description: "A student's organization page (Organization mode)");
  static const orgOnboardingCase = AppRouteDef('org.onboarding_case', '/org/:orgId/onboarding/:caseId',
      description: "One admission case on its own page (staff review), opened from a notification or a link (D-1200)");
  static const orgMemberships = AppRouteDef('org.memberships', '/my-organizations',
      description: 'My organizations: memberships, join requests and invitations (D-283)');
  static const calendar = AppRouteDef('calendar', '/calendar', description: 'The schedule page (D-085)');
  static const inbox = AppRouteDef('inbox', '/inbox', description: 'Inbox and notifications (`?tab=`)');
  static const notifications = AppRouteDef('inbox.notifications', '/notifications', description: 'The Notifications tab of the inbox');
  static const subscription = AppRouteDef('account.subscription', '/subscription', description: 'Subscription');
  static const editAccount = AppRouteDef('account.edit', '/edit-account', description: 'Edit the account');
  static const changePassword = AppRouteDef('account.change_password', '/change-password', description: 'Change the password');
  static const profile = AppRouteDef('account.profile', '/profile', description: "The home's account tab");
  static const downloads = AppRouteDef('downloads', '/downloads', description: 'Offline downloads (phones / desktop only)');
  static const exports = AppRouteDef('exports', '/exports', description: 'Export Studio hub');
  static const exportLog = AppRouteDef('exports.log', '/exports/log', description: 'Export log');
  static const exportSchedules = AppRouteDef('exports.schedules', '/exports/schedules', description: 'Scheduled exports');
  static const exportLinks = AppRouteDef('exports.links', '/exports/links', description: 'Export share links');
  static const meetingLinks = AppRouteDef('meetings.links', '/meeting-links',
      description: 'Meeting links: every live session and meeting link to join, copy or share (D-307)');
  static const entityView = AppRouteDef('entity.view', '/view/:kind/:id',
      description: 'A student, course, teacher or category on a page of its own (D-290), every role');

  // ── Public links (no account needed, or sign-in first then the page) ─────
  static const courseLink = AppRouteDef('link.course', '/c/:courseId', description: 'A course share link (`?ref=`)');
  static const profileLink = AppRouteDef('link.profile', '/@:username', description: 'A public profile (D-074)');
  static const liveLink = AppRouteDef('link.live', '/live/:token', signIn: false, description: "A live session's guest link");
  static const verifyHome = AppRouteDef('link.verify_home', '/verify',
      signIn: false, description: 'Certificate verification: type a number or scan a QR code (D-420)');
  static const verifyLink =
      AppRouteDef('link.verify', '/verify/:token', signIn: false, description: "A certificate's verification page");
  static const exportLink = AppRouteDef('link.export', '/e/:token', description: 'An Export Studio share link (D-134)');
  static const orgJoinLink = AppRouteDef('link.org_join', '/j/:code',
      signIn: false, description: "An organization's join link: the join page with the code filled in (D-283)");
  static const shareLink = AppRouteDef('link.share', '/s/:kind/:id',
      signIn: false, description: 'A share link (D-307): a lesson, session, meeting, path, teacher, course or page');
  static const orgInvitationLink = AppRouteDef('link.org_invitation', '/i/:token',
      signIn: false, description: 'An organization invitation: accept or decline, after signing in (D-283)');
  static const onboardIntakeLink = AppRouteDef('link.onboard', '/onboard/:code',
      signIn: false, description: "A member onboarding intake link: the public preview, then sign in and start the application (D-1200)");

  /// Every page, in match order.
  static const all = <AppRouteDef>[
    login, register, forgotPassword,
    studentHome, teacherHome, adminHome, parentHome, orgHome,
    course, orgMember, orgOnboardingCase, orgMemberships, calendar, inbox, notifications, subscription, editAccount, changePassword, profile,
    downloads, exports, exportLog, exportSchedules, exportLinks, entityView, meetingLinks,
    courseLink, profileLink, liveLink, verifyHome, verifyLink, exportLink, orgJoinLink, orgInvitationLink, onboardIntakeLink, shareLink,
    privacy, terms,
  ];

  /// The role homes, by path (their tabs are `<home>/<tab>`).
  static const homes = <AppRouteDef>[studentHome, teacherHome, adminHome, parentHome, orgHome];

  static AppRouteDef? byId(String id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// The page a URL (path + query, or a full URL) opens, or null.
  static AppRouteMatch? match(String? location) {
    if (location == null || location.isEmpty) return null;
    final uri = Uri.tryParse(location);
    if (uri == null) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    for (final r in all) {
      for (final pattern in [r.path, ...r.aliases]) {
        final params = _matchPath(pattern, segs);
        if (params != null) return AppRouteMatch(r, params, uri.queryParameters);
      }
    }
    return null;
  }

  static Map<String, String>? _matchPath(String pattern, List<String> segs) {
    final parts = pattern.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length != segs.length) return null;
    final out = <String, String>{};
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      final s = segs[i];
      if (p.startsWith(':')) {
        out[p.substring(1)] = s;
      } else if (p.startsWith('@:')) {
        // `/@:username`: the segment is `@name`
        if (!s.startsWith('@') || s.length < 2) return null;
        out[p.substring(2)] = s.substring(1);
      } else if (p != s) {
        return null;
      }
    }
    return out;
  }

  /// The URL of page [id] with [params] (and an optional [query]). Throws on an unknown id or a missing parameter:
  /// a typo must fail in development, not open the home.
  static String location(String id, [Map<String, Object?> params = const {}, Map<String, String>? query]) {
    final r = byId(id);
    if (r == null) throw ArgumentError.value(id, 'id', 'no such page');
    final path = r.path.split('/').map((s) {
      if (s.startsWith('@:')) return '@${Uri.encodeComponent(_param(params, s.substring(2), id))}';
      if (s.startsWith(':')) return Uri.encodeComponent(_param(params, s.substring(1), id));
      return s;
    }).join('/');
    if (query == null || query.isEmpty) return path;
    return Uri(path: path, queryParameters: query).toString();
  }

  static String _param(Map<String, Object?> params, String name, String id) {
    final v = params[name];
    if (v == null || '$v'.isEmpty) throw ArgumentError('page $id needs the parameter $name');
    return '$v';
  }

  /// The course id of the object a `'/course-detail'` route carries (main.dart sets it: a `CourseModel`); this file
  /// stays free of feature imports.
  static int? Function(Object? arguments)? courseIdOf;

  /// The URL a pushed route shows in the address bar, or null when it has none of its own (it keeps the URL of the
  /// page under it). Old route names that carry their id as an argument get their path form here.
  static String? locationOf(String? name, Object? arguments) {
    if (name == null || !name.startsWith('/')) return null;
    switch (name) {
      case '/course-profile':
        return arguments is int ? location(course.id, {'courseId': arguments}) : null;
      case '/org_member':
        return arguments is int ? location(orgMember.id, {'orgId': arguments}) : name;
      case '/course-detail': // the course page built from an in-memory course: its id gives it the course URL
        final id = arguments is int ? arguments : courseIdOf?.call(arguments);
        return id != null && id > 0 ? location(course.id, {'courseId': id}) : null;
      case '/otp':
        return null; // a sign-in step: a refresh could not rebuild it
    }
    return name;
  }

  /// The URL of a role home showing one of its tabs (`/dashboard/my-courses`); the first tab is the home itself.
  static String tabLocation(String home, String tab) => '$home/${tab.replaceAll('_', '-')}';

  /// A home-tab URL split into its home and the tab's key (`/dashboard/my-courses` → ('/dashboard', 'my_courses')).
  static ({String home, String tab})? splitTab(String? location) {
    if (location == null) return null;
    final segs = (Uri.tryParse(location)?.pathSegments ?? const <String>[]).where((s) => s.isNotEmpty).toList();
    if (segs.length != 2) return null;
    final home = '/${segs[0]}';
    if (!homes.any((h) => h.path == home)) return null;
    return (home: home, tab: segs[1].replaceAll('-', '_'));
  }
}
