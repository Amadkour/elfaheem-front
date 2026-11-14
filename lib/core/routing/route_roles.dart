// Which signed-in roles may open a role-only home (S4). main.dart's `_Guard` asks [routeRoleRedirect] after the
// "signed in" check: a student who opens /app/admin_dashboard by URL, or edits the cached user, lands on their own
// home instead of the admin shell (the server refuses every call of that shell anyway). Routes not listed here are
// open to every signed-in role (the student dashboard is also the personal home of org roles; /org_dashboard draws
// its own "staff only" page for a student).

/// Route → the user roles that may open it.
const roleOnlyRoutes = <String, Set<String>>{
  '/admin_dashboard': {'admin', 'super-admin', 'developer'},
  '/teacher_dashboard': {'teacher'},
  '/parent_dashboard': {'parent'},
};

/// Null when [role] may open [route]; otherwise [homeRoute], where the user is sent instead. A missing role reads as
/// a student (like `MyAuthProvider.homeRoute`). [viewAs]: a platform admin looking at another user's app opens that
/// user's home on purpose (`startViewAs`), so nothing is redirected then.
String? routeRoleRedirect(String? route, {required String? role, required String homeRoute, bool viewAs = false}) {
  final roles = roleOnlyRoutes[route == null ? null : (Uri.tryParse(route)?.path ?? route)]; // '/admin_dashboard?x' too
  if (roles == null || viewAs || route == homeRoute) return null;
  return roles.contains(role ?? 'student') ? null : homeRoute;
}
