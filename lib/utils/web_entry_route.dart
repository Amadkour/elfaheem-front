// The route a browser URL asks for when the web app starts (M20): `/notifications`, `/profile`, … opened directly
// or after a refresh. The boot splash runs its own MaterialApp first; its Navigator takes over the browser's
// navigation, and the engine then resets `defaultRouteName` to `/` — so the real app never saw the URL and opened
// the home. main() reads the URL BEFORE the splash ([webEntryRouteFromUri]) and the real app starts on it, when
// [resolveWebEntry] says the person may open it there. Pure, unit-tested (test/ui/web_entry_route_test.dart).
library;

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

/// URLs that name a tab of the person's home (N10): the app starts on the home and switches to that tab
/// (`/profile` is the account tab, not the edit-account form, which is `/edit-account`).
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
  return null; // unknown, a home tab ([webEntryTab]) or needs arguments: the home
}

/// The home tab a browser [entry] route names (`/profile` → 'profile'), for a signed-in start; else null.
String? webEntryTab(String? entry) {
  if (entry == null || entry.isEmpty) return null;
  return kWebTabPages[Uri.tryParse(entry)?.path ?? entry];
}
