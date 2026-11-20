// `/join?role=student|teacher|parent&lang=` — the landing website's four entry buttons (CONTRACT §4). Pure, so the
// router and the web entry check share it. `role=org` belongs to the institution application (`/start/institution`).
library;

/// The kill switch of the join flow (CONTRACT §4): off = `/join` opens the guest search instead.
const kJoinFlowKey = 'join.flow';

class JoinRequest {
  const JoinRequest({this.role, this.lang});

  /// The join flow is switched off in [disabled] (AppConfig.disableList): the router opens `/guest-search`.
  static bool switchedOff(Iterable<String> disabled) => disabled.contains(kJoinFlowKey);

  /// student · teacher · parent; null = ask on the first step.
  final String? role;

  /// ar · en, applied before the first step.
  final String? lang;

  static bool matches(String? route) => route != null && Uri.tryParse(route)?.path == '/join';

  /// `role=org` asks for the institution application instead of the join flow.
  static bool isOrg(String? route) => matches(route) && Uri.tryParse(route!)?.queryParameters['role'] == 'org';

  static JoinRequest parse(String? route) {
    final q = Uri.tryParse(route ?? '')?.queryParameters ?? const <String, String>{};
    final role = q['role'];
    final lang = q['lang'];
    return JoinRequest(
      role: const ['student', 'teacher', 'parent'].contains(role) ? role : null,
      lang: (lang == 'ar' || lang == 'en') ? lang : null,
    );
  }
}
