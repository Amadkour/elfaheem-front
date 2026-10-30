// The route a browser URL asks for when the web app starts (M20): `/notifications`, `/profile`, … opened directly
// or after a refresh. The boot splash runs its own MaterialApp first; its Navigator takes over the browser's
// navigation, and the engine then resets `defaultRouteName` to `/` — so the real app never saw the URL and opened
// the home. main() reads the URL BEFORE the splash ([webEntryRouteFromUri]) and the real app starts on it, when
// [resolveWebEntry] says the person may open it there. Pure, unit-tested (test/ui/web_entry_route_test.dart).
library;

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
const kWebUrlPages = {'/notifications', '/profile', '/change-password', '/subscription', '/calendar', '/downloads'};

/// The sign-in pages, which a signed-out person may open by URL.
const kWebAuthRoutes = {'/login', '/register', '/forgot-password'};

/// The route of a browser URL (path + query), or null for the root.
String? webEntryRouteFromUri(Uri base) {
  final path = base.path;
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
  return null; // unknown or needs arguments: the home
}
