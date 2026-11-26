// Which signed-in roles may open a role-only home (S4). main.dart's `_Guard` asks [routeRoleRedirect] after the
// "signed in" check: a student who opens /app/admin_dashboard by URL, or edits the cached user, lands on their own
// home instead of the admin shell (the server refuses every call of that shell anyway). Routes not listed here are
// open to every signed-in role (the student dashboard is also the personal home of org roles; /org_dashboard draws
// its own "staff only" page for a student).

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

/// Route → the user roles that may open it.
const roleOnlyRoutes = <String, Set<String>>{
  '/admin_dashboard': {'admin', 'super-admin', 'developer'},
  '/teacher_dashboard': {'teacher'},
  '/parent_dashboard': {'parent'},
  '/kit_gallery': {'super-admin', 'developer'},
};

/// Routes every signed-in role may open in a debug build (developer tools).
const debugOpenRoutes = <String>{'/kit_gallery'};

/// True in debug builds; a test sets it false to check the release behaviour.
@visibleForTesting
bool debugOpenRoutesEnabled = kDebugMode;

/// Null when [role] may open [route]; otherwise [homeRoute], where the user is sent instead. A missing role reads as
/// a student (like `MyAuthProvider.homeRoute`). [viewAs]: a platform admin looking at another user's app opens that
/// user's home on purpose (`startViewAs`), so nothing is redirected then.
String? routeRoleRedirect(String? route, {required String? role, required String homeRoute, bool viewAs = false}) {
  final path = route == null ? null : (Uri.tryParse(route)?.path ?? route); // '/admin_dashboard?x' too
  final roles = roleOnlyRoutes[path];
  if (roles == null || viewAs || route == homeRoute) return null;
  if (debugOpenRoutesEnabled && debugOpenRoutes.contains(path)) return null;
  return roles.contains(role ?? 'student') ? null : homeRoute;
}
