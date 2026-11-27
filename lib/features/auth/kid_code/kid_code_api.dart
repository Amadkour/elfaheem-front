// features/auth/kid_code/kid_code_api.dart
//
// The child's side of "the parent creates the child's account" (docs/redesign/api/child_code.md, WP7): no account and
// no sign-in yet, so both calls are unauthenticated. Kill switch `auth.child_code` (403 feature_disabled).
//
//   POST /api/v1/auth/child-code/lookup  {code}                      → the "is this your account?" card
//   POST /api/v1/auth/child-code/claim   {code, password, username?}  → the same answer as POST /auth/login
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

/// The kill switch of the whole child-code entry.
const String kKidCodeFeature = 'auth.child_code';

/// Six digits: Arabic-Indic and Persian digits become Latin, spaces and dashes are dropped.
String kidCodeDigits(String raw) {
  final b = StringBuffer();
  for (final r in raw.runes) {
    if (r >= 0x30 && r <= 0x39) {
      b.writeCharCode(r);
    } else if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    }
  }
  return b.toString();
}

/// What the lookup tells the child: only what the confirm card needs.
class KidCodeAccount {
  const KidCodeAccount({
    required this.firstName,
    this.lastName = '',
    this.gradeAr = '',
    this.gradeEn = '',
    this.parentName = '',
  });

  final String firstName;
  final String lastName;
  final String gradeAr;
  final String gradeEn;
  final String parentName;

  String get name => [firstName, lastName].where((p) => p.trim().isNotEmpty).join(' ');

  String get grade => AppConfig.lang == 'ar' ? (gradeAr.isNotEmpty ? gradeAr : gradeEn) : (gradeEn.isNotEmpty ? gradeEn : gradeAr);

  String get initial => name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first);

  factory KidCodeAccount.fromJson(Map<dynamic, dynamic> j) => KidCodeAccount(
        firstName: j['first_name']?.toString() ?? '',
        lastName: j['last_name']?.toString() ?? '',
        gradeAr: j['grade_name_ar']?.toString() ?? '',
        gradeEn: j['grade_name_en']?.toString() ?? '',
        parentName: j['parent_name']?.toString() ?? '',
      );
}

class KidCodeApi {
  KidCodeApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<KidCodeAccount> lookup(String code) async {
    final r = await _api.post('/api/v1/auth/child-code/lookup', auth: false, body: {'code': kidCodeDigits(code)});
    return KidCodeAccount.fromJson(r is Map ? r : const {});
  }

  /// The session map (tokens, user, …) exactly like POST /auth/login.
  Future<Map<dynamic, dynamic>> claim(String code, String password, {String? username}) async {
    final r = await _api.post('/api/v1/auth/child-code/claim', auth: false, body: {
      'code': kidCodeDigits(code),
      'password': password,
      if (username != null && username.trim().isNotEmpty) 'username': username.trim(),
    });
    return r is Map ? r : const {};
  }
}
