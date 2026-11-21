// The route a browser URL asks for when the web app starts (M20): `/notifications`, `/profile`, … opened directly
// or after a refresh. The boot splash runs its own MaterialApp first; its Navigator takes over the browser's
// navigation, and the engine then resets `defaultRouteName` to `/` — so the real app never saw the URL and opened
// the home. main() reads the URL BEFORE the splash ([webEntryRouteFromUri]) and the real app starts on it, when
// [resolveWebEntry] says the person may open it there. Pure, unit-tested (test/ui/web_entry_route_test.dart).
//
// D-170: the pages of the route registry with a path of their own (`/courses/12`, `/org/5`, core/routing/app_routes
// .dart) open the same way, a role home's tab has its URL (`/dashboard/my-courses`), and a page that needs an account
// opened signed out comes back after the sign-in ([SignInReturn]).
library;

import '../core/routing/app_routes.dart';
import 'web_base_path.dart';

/// The dashboards: a URL never opens another role's home; the person's own home is used instead.
const kWebDashboardRoutes = {
  '/home',
  '/dashboard',
  '/teacher_dashboard',
  '/admin_dashboard',
  '/org_member',
  '/org_dashboard',
  '/parent_dashboard',
};

/// Pages that need no arguments and may be opened by URL by a signed-in person (each stays behind the router's
/// own guard): they open on top of the person's home, so Back leads there.
const kWebUrlPages = {'/notifications', '/inbox', '/change-password', '/subscription', '/calendar', '/downloads', '/edit-account'};

/// Registry pages (by id) with a path of their own that a signed-in person may open by URL, over the home.
const kWebUrlRouteIds = {
  'course', 'org.member', 'org.onboarding_case', 'org.memberships', 'exports', 'exports.log', 'exports.schedules', 'exports.links',
  'entity.view', 'meetings.links', 'store.item', 'store.library',
  'games.progress', 'games.play', 'nahw.lesson', 'quran.progress', 'quran.teacher',
};

/// URLs that name a tab of the person's home (N10): the app starts on the home and switches to that tab
/// (`/profile` is the account tab, not the edit-account form, which is `/edit-account`). Every home also has
/// `<home>/<tab>` ([AppRoutes.splitTab]).
const kWebTabPages = {'/profile': 'profile'};

/// The sign-in pages, which a signed-out person may open by URL.
const kWebAuthRoutes = {'/login', '/register', '/forgot-password'};

/// [path] without the document's base path ([basePath], e.g. `/app/`): `/app/c/12` -> `/c/12`, `/app` and `/app/`
/// -> `/`; a path outside the base (`/application`) is returned unchanged. A base of `/` changes nothing.
String stripWebBasePath(String path, [String? basePath]) {
  var b = basePath ?? webBasePath;
  if (b.isEmpty || b == '/') return path;
  if (!b.endsWith('/')) b = '$b/';
  final bare = b.substring(0, b.length - 1); // `/app`
  if (path == bare || path == b) return '/';
  if (path.startsWith(b)) return '/${path.substring(b.length)}';
  return path;
}

/// The route of a browser URL (path + query) relative to the base path, or null for the root.
String? webEntryRouteFromUri(Uri base, {String? basePath}) {
  final path = stripWebBasePath(base.path, basePath);
  if (path.isEmpty || path == '/') return null;
  return base.query.isEmpty ? path : '$path?${base.query}';
}

/// Where the app starts for a browser [entry] route: null = the usual start (the home or the login); else the
/// route, and whether the person's [home] goes under it. [isLink] recognises the share links the router resolves
/// itself (guest live, course, profile), signed in or not.
({String route, bool overHome})? resolveWebEntry(String? entry,
    {required bool signedIn, required String home, required bool Function(String route) isLink}) {
  if (entry == null || entry.isEmpty || entry == '/') return null;
  if (isLink(entry)) return (route: entry, overHome: false);
  final path = Uri.tryParse(entry)?.path ?? entry;
  if (!signedIn) {
    if (kWebAuthRoutes.contains(path)) return (route: path, overHome: false);
    return null; // a page that needs an account: the login
  }
  if (kWebAuthRoutes.contains(path) || kWebDashboardRoutes.contains(path) || path == home) return null;
  if (kWebUrlPages.contains(path)) return (route: path, overHome: true);
  final page = AppRoutes.match(entry);
  if (page != null && kWebUrlRouteIds.contains(page.id)) return (route: path, overHome: true);
  return null; // unknown, a home tab ([webEntryTab]) or needs arguments: the home
}

/// The home tab a browser [entry] route names (`/profile` → 'profile', `/dashboard/my-courses` → 'my_courses'), for a
/// signed-in start; else null.
String? webEntryTab(String? entry) {
  if (entry == null || entry.isEmpty) return null;
  return kWebTabPages[Uri.tryParse(entry)?.path ?? entry] ?? AppRoutes.splitTab(entry)?.tab;
}

/// A URL a signed-out person opened that needs an account: worth coming back to after the sign-in.
bool needsSignInFirst(String entry) {
  final path = Uri.tryParse(entry)?.path ?? entry;
  if (kWebAuthRoutes.contains(path)) return false;
  if (kWebUrlPages.contains(path) || kWebTabPages.containsKey(path) || AppRoutes.splitTab(entry) != null) return true;
  final page = AppRoutes.match(entry);
  return page != null && kWebUrlRouteIds.contains(page.id);
}

/// The page asked for by URL before the sign-in (D-170): opened once, by the first signed-in page ([consume] in
/// main.dart's route guard), through [opener] (main.dart's `_openLocation`). It is forgotten after [maxAge]: a sign-in
/// page left open (or given up for the guest pages) must not send the next person who signs in on that tab there.
class SignInReturn {
  SignInReturn._();

  static const Duration maxAge = Duration(minutes: 30);
  static String? _pending;
  static DateTime _at = DateTime.now();

  static String? get pending => _pending != null && DateTime.now().difference(_at) <= maxAge ? _pending : null;
  static set pending(String? location) {
    _pending = location;
    _at = DateTime.now();
  }

  static Future<bool> Function(String location)? opener;

  static void consume() {
    final p = pending;
    final open = opener;
    if (p == null || open == null) return;
    _pending = null;
    open(p);
  }
}
