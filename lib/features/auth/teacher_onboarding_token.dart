// The teacher onboarding token (back/docs/SECURITY_SCAN.md F2). verify-otp, login and teacher-profile hand it to a
// teacher who still owes the profile / documents; the onboarding routes (POST /auth/teacher-profile and
// /auth/teacher-documents/*) take it as `X-Onboarding-Token`, so they no longer act on an account by e-mail alone.
// In memory only: it lives for one onboarding run (6 h on the server) and is cleared at logout.
class TeacherOnboardingToken {
  TeacherOnboardingToken._();

  static String? value;

  /// Remembers the token of a server answer; an answer that carries `onboarding_token: null` (onboarding done)
  /// forgets it. Answers without the field leave it as it is.
  static void readFrom(dynamic body) {
    if (body is! Map || !body.containsKey('onboarding_token')) return;
    final v = body['onboarding_token'];
    value = (v is String && v.isNotEmpty) ? v : null;
  }

  /// The header to add to an onboarding call (null when there is no token).
  static Map<String, String>? get headers => value == null ? null : {'X-Onboarding-Token': value!};

  static void clear() => value = null;
}
