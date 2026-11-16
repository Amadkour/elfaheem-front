// lib/core/personal_access.dart
//
// One account, optional personal profile (UX v3 phase 3). A member of an organization may switch their personal
// profile off: the public profile, personal courses and the "Personal" side of the context switcher disappear and
// the app always opens the organization. The data is kept, only hidden; turning it on brings everything back.
//
//   PersonalAccess.enabled            THE question every screen asks ("may I show the personal space?")
//   PersonalAccess.homeFor(role, …)   the cold-start home of a role, pure (MyAuthProvider.homeRoute)
//   PersonalAccess.instance.set(on)   PUT /api/v1/me/personal {enabled} → {personal_enabled}
//   enablePersonalFix(onRetry:)       the one handler of the server's fix_action `enable_personal` (403 personal_off)
//
// The flag comes from the signed-in user (`personal_enabled`; an older server sends none → on, today's behaviour).
// A person without any organization never loses anything: [enabled] is only false for an organization member.
library;

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../design/app_notice.dart' show showAppNotice;
import 'api_client.dart';
import 'app_mode.dart';

class PersonalAccess extends ChangeNotifier {
  PersonalAccess._();
  static final PersonalAccess instance = PersonalAccess._();

  static const String path = '/api/v1/me/personal';

  /// The server's 403 code and the fix_action it carries.
  static const String offCode = 'personal_off';
  static const String fixAction = 'enable_personal';

  bool _flag = true;
  String? _role;

  /// What the server said (`personal_enabled`), before the "never without an organization" guard.
  bool get flag => _flag;

  /// MyAuthProvider calls this whenever the signed-in user changes (signed out = on).
  void bind({bool personalEnabled = true, String? role}) {
    if (_flag == personalEnabled && _role == role) return;
    _flag = personalEnabled;
    _role = role;
    notifyListeners();
  }

  static bool isOrgRole(String? role) => role == 'org-admin' || role == 'org-staff';

  /// An organization member: an organization role, or any organization in the membership overview.
  bool get hasOrg => isOrgRole(_role) || AppModeController.instance.entries.isNotEmpty;

  /// Known to belong to no organization: no organization role, and the overview answered with none. (Before it
  /// answers, the server's `personal_enabled: false` is trusted: it only sends that to a member.)
  bool get knownNoOrg {
    final m = AppModeController.instance;
    return !isOrgRole(_role) && m.loaded && !m.refreshFailed && m.entries.isEmpty;
  }

  /// May the personal space (switcher entry, personal courses, public profile) be shown?
  static bool get enabled => decide(flag: instance._flag, noOrg: instance.knownNoOrg);

  /// Pure: off only for an organization member whose personal profile is off; never for a person without one.
  static bool decide({required bool flag, required bool noOrg}) => flag || noOrg;

  /// The cold-start home of [role], pure. Personal off: every non-student organization role opens the organization
  /// dashboard (a remembered Personal choice is ignored); a student opens '/dashboard', where Organization mode is
  /// forced ([AppModeController.mode]). Personal on: today's rule (org roles honour the remembered choice).
  static String homeFor(String role, {bool personalEnabled = true, bool? rememberedPersonal}) {
    const org = '/org_dashboard';
    return switch (role) {
      'admin' || 'super-admin' || 'developer' => '/admin_dashboard',
      'org-admin' || 'org-staff' => personalEnabled ? AppModeController.orgRoleHome(org, personal: rememberedPersonal) : org,
      'teacher' => personalEnabled ? '/teacher_dashboard' : org,
      'parent' => personalEnabled ? '/parent_dashboard' : org,
      _ => '/dashboard',
    };
  }

  /// Sends the switch. Replaceable in tests.
  @visibleForTesting
  static Future<dynamic> Function(bool on) send = (on) => ApiClient().put(path, body: {'enabled': on});

  /// Keeps the cached user in step (MyAuthProvider registers it).
  static Future<void> Function(bool on)? onChanged;

  /// PUT /api/v1/me/personal. Returns the server's answer; throws ApiException.
  Future<bool> set(bool on) async {
    final r = await send(on);
    final v = r is Map && r['personal_enabled'] is bool ? r['personal_enabled'] as bool : on;
    if (v != _flag) {
      _flag = v;
      notifyListeners();
    }
    await onChanged?.call(v);
    return v;
  }
}

String _tx(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The label of the `enable_personal` fix.
String enablePersonalLabel() => _tx('فعّل الحساب الشخصي', 'Turn on personal account');

/// The one handler of fix_action `enable_personal`: turns the personal profile on, says so, then runs [onRetry]
/// (the action the server refused). A failure is a plain notice (no loop of fixes).
Future<void> enablePersonalFix({VoidCallback? onRetry}) async {
  try {
    await PersonalAccess.instance.set(true);
    showAppNotice(_tx('فُعّل حسابك الشخصي', 'Your personal account is on'));
    onRetry?.call();
  } catch (e) {
    showAppNotice(ApiException.from(e).message, error: true);
  }
}
