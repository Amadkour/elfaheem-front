// Where a signed-out start lands (pure, unit-tested in test/ui/onboarding_start_route_test.dart).
//
//   signed in                      -> null (the usual role home, unchanged)
//   a link / URL entry             -> null (the router / resolveWebEntry decide, as before)
//   web, no URL                    -> /login (the website already did the pitch)
//   app, onboarding not seen       -> /onboarding
//   app, onboarding seen           -> /guest-search (it has Log in / Create account)
library;

String? decideSignedOutStart({
  required bool isAuthenticated,
  required bool isWeb,
  required bool onboardingSeen,
  required bool hasEntryLink,
}) {
  if (isAuthenticated || hasEntryLink) return null;
  if (isWeb) return '/login';
  return onboardingSeen ? '/guest-search' : '/onboarding';
}

/// The filters of an `/explore?subject=&level=&mode=&lang=` URL.
class ExploreRequest {
  const ExploreRequest({this.subject, this.level, this.mode = 'any', this.lang});

  final int? subject;
  final int? level;
  final String mode; // any | online | center
  final String? lang; // ar | en

  /// The category to open: the level when there is one, else the subject.
  int? get categoryId => level ?? subject;

  static bool matches(String? route) => route != null && (Uri.tryParse(route)?.path == '/explore');

  static ExploreRequest parse(String? route) {
    final q = Uri.tryParse(route ?? '')?.queryParameters ?? const <String, String>{};
    final mode = q['mode'];
    final lang = q['lang'];
    return ExploreRequest(
      subject: int.tryParse(q['subject'] ?? ''),
      level: int.tryParse(q['level'] ?? ''),
      mode: (mode == 'online' || mode == 'center') ? mode! : 'any',
      lang: (lang == 'ar' || lang == 'en') ? lang : null,
    );
  }
}

/// `/start/institution` (the landing's "register my institution" link).
bool isInstitutionRoute(String? route) => route != null && Uri.tryParse(route)?.path == '/start/institution';

/// The role a `/register?role=teacher` URL asks to preselect.
String? registerRoleFromRoute(String? route) {
  final u = Uri.tryParse(route ?? '');
  if (u == null || u.path != '/register') return null;
  final r = u.queryParameters['role'];
  return (r == 'teacher' || r == 'student' || r == 'parent') ? r : null;
}
