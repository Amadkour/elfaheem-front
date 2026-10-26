// Two-factor authentication (TOTP) for admins — brief §12. Server: back/services/mfa_service.py.
//
//   POST /api/v1/auth/login | /google      200 {mfa_required, mfa_token, expires_in, attempts_left}
//                                          or  {mfa_enrollment_required, mfa_enroll_token, expires_in, role}
//   POST /api/v1/auth/mfa/verify           {mfa_token, code | recovery_code} → the normal login answer
//   GET  /api/v1/auth/mfa/status           {enabled, pending, allowed, required, recovery_codes_left, confirmed_at}
//   POST /api/v1/auth/mfa/setup            {password} (not with an enrollment token) → {secret, otpauth_uri, …}
//   POST /api/v1/auth/mfa/confirm          {code} → login answer (fresh token pair: every other session ends)
//                                          + {recovery_codes}
//   POST /api/v1/auth/mfa/disable          {password, code | recovery_code}
//   POST /api/v1/auth/mfa/recovery-codes   {code} → {recovery_codes}
//   POST /api/v1/auth/mfa/users/{id}/reset super admin: remove another user's MFA → {reset: true}
//
// The enrollment token is not a session: it is sent by hand (`auth: false` + Authorization header) and only the
// three enrollment routes accept it. Everything here is pure or a thin API; the screens are in
// mfa_verify_screen.dart (login step) and features/admin/admin_mfa_page.dart (enroll / manage).
library;

import 'package:flutter_education_app/core/api_client.dart';

import '../admin/admin_common.dart' show t;

int _int(dynamic v, [int fallback = 0]) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fallback);

/// What a login answer asks for next.
enum MfaStepKind { none, verify, enroll }

/// The second step a login answer asks for (or [MfaStepKind.none] for a normal answer with tokens).
class MfaLoginStep {
  const MfaLoginStep(this.kind, {this.token, this.expiresIn = 0, this.attemptsLeft = 5});
  final MfaStepKind kind;
  final String? token;
  final int expiresIn;
  final int attemptsLeft;

  static const none = MfaLoginStep(MfaStepKind.none);

  factory MfaLoginStep.fromLogin(dynamic body) {
    if (body is! Map) return none;
    if (body['mfa_required'] == true && '${body['mfa_token'] ?? ''}'.isNotEmpty) {
      return MfaLoginStep(MfaStepKind.verify,
          token: '${body['mfa_token']}', expiresIn: _int(body['expires_in'], 300),
          attemptsLeft: _int(body['attempts_left'], 5));
    }
    if (body['mfa_enrollment_required'] == true && '${body['mfa_enroll_token'] ?? ''}'.isNotEmpty) {
      return MfaLoginStep(MfaStepKind.enroll,
          token: '${body['mfa_enroll_token']}', expiresIn: _int(body['expires_in'], 900));
    }
    return none;
  }
}

class MfaStatus {
  const MfaStatus({
    this.enabled = false,
    this.pending = false,
    this.allowed = false,
    this.required = false,
    this.recoveryCodesLeft = 0,
    this.confirmedAt,
  });

  final bool enabled, pending, allowed, required;
  final int recoveryCodesLeft;
  final DateTime? confirmedAt;

  static const empty = MfaStatus();

  factory MfaStatus.fromJson(dynamic j) {
    if (j is! Map) return empty;
    final at = '${j['confirmed_at'] ?? ''}';
    return MfaStatus(
      enabled: j['enabled'] == true,
      pending: j['pending'] == true,
      allowed: j['allowed'] == true,
      required: j['required'] == true,
      recoveryCodesLeft: _int(j['recovery_codes_left']),
      // naive server times are UTC
      confirmedAt: at.isEmpty || at == 'null' ? null : DateTime.tryParse(at.endsWith('Z') ? at : '${at}Z')?.toUtc(),
    );
  }
}

class MfaSetupInfo {
  const MfaSetupInfo({required this.secret, required this.otpauthUri, this.issuer = '', this.account = ''});
  final String secret, otpauthUri, issuer, account;

  factory MfaSetupInfo.fromJson(dynamic j) {
    final m = j is Map ? j : const {};
    return MfaSetupInfo(
      secret: '${m['secret'] ?? ''}',
      otpauthUri: '${m['otpauth_uri'] ?? ''}',
      issuer: '${m['issuer'] ?? ''}',
      account: '${m['account'] ?? ''}',
    );
  }
}

/// "JBSWY3DPEHPK3PXP" → "JBSW Y3DP EHPK 3PXP" (easier to type into an authenticator by hand).
String groupSecret(String secret) {
  final s = secret.replaceAll(RegExp(r'\s'), '');
  final b = StringBuffer();
  for (var i = 0; i < s.length; i += 4) {
    if (i > 0) b.write(' ');
    b.write(s.substring(i, i + 4 > s.length ? s.length : i + 4));
  }
  return b.toString();
}

/// Digits only, without spaces ("123 456" → "123456"); Arabic-Indic digits become ASCII.
String normalizeTotp(String raw) {
  const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in raw.split('')) {
    final a = arabic.indexOf(ch), p = persian.indexOf(ch);
    if (a >= 0) {
      b.write(a);
    } else if (p >= 0) {
      b.write(p);
    } else if (RegExp(r'[0-9]').hasMatch(ch)) {
      b.write(ch);
    }
  }
  return b.toString();
}

bool isTotpCode(String raw) => RegExp(r'^\d{6}$').hasMatch(normalizeTotp(raw)) &&
    raw.replaceAll(RegExp(r'[\s٠-٩۰-۹0-9]'), '').isEmpty;

/// A recovery code as typed (any case, spaces or dashes) is valid when it has 16 letters/digits.
bool looksLikeRecoveryCode(String raw) => raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length == 16;

/// Bilingual text for the server's MFA codes; [fallback] otherwise.
String mfaCodeText(String? code, String fallback) => switch (code) {
      'mfa_code_invalid' => t('رمز التحقق غير صحيح', 'The code is not correct'),
      'mfa_token_invalid' || 'mfa_token_used' => t('انتهت خطوة التحقق، سجّل الدخول مرة أخرى',
          'This sign-in step is no longer valid. Please sign in again'),
      'mfa_token_expired' => t('انتهت مهلة خطوة التحقق، سجّل الدخول مرة أخرى',
          'The sign-in step timed out. Please sign in again'),
      'mfa_token_locked' => t('محاولات خاطئة كثيرة، سجّل الدخول مرة أخرى',
          'Too many wrong codes. Please sign in again'),
      'too_many_attempts' => t('محاولات كثيرة، انتظر قليلاً ثم حاول مرة أخرى',
          'Too many attempts. Wait a little and try again'),
      'mfa_unavailable' => t('التحقق الثنائي غير متاح مؤقتاً، تواصل مع الدعم',
          'Two-step verification is unavailable right now. Contact support'),
      'mfa_already_enabled' => t('التحقق الثنائي مفعّل بالفعل', 'Two-step verification is already on'),
      'mfa_not_pending' => t('ابدأ الإعداد من جديد', 'Start the setup again'),
      'mfa_not_enabled' => t('التحقق الثنائي غير مفعّل', 'Two-step verification is off'),
      'mfa_not_available' => t('التحقق الثنائي غير متاح لهذا الحساب', 'Two-step verification is not available for this account'),
      'password_invalid' => t('كلمة المرور غير صحيحة', 'The password is not correct'),
      'mfa_enrollment_required' => t('يجب تفعيل التحقق الثنائي لحسابك أولاً', 'Turn on two-step verification first'),
      'mfa_reset_self' => t('استخدم إيقاف التحقق الثنائي لحسابك', 'Use “turn off” for your own account'),
      _ => fallback,
    };

/// True when a failed second step cannot be retried with another code (the user must sign in again).
bool mfaStepIsDead(String? code) =>
    code == 'mfa_token_invalid' || code == 'mfa_token_used' || code == 'mfa_token_expired' || code == 'mfa_token_locked';

/// True when a failed second step leaves nothing to retry: a dead token ([mfaStepIsDead]), or the last allowed
/// wrong code (400 `mfa_code_invalid` with `attempts_left: 0`: the server has already burned the challenge, so the
/// next try could only answer `mfa_token_used`).
bool mfaFailureEndsStep(String? code, int? attemptsLeft) =>
    mfaStepIsDead(code) || (code == 'mfa_code_invalid' && attemptsLeft != null && attemptsLeft <= 0);

/// `attempts_left` of a 400 `mfa_code_invalid`, if the server sent it.
int? attemptsLeftOf(ApiException e) {
  final d = ApiException.asMap(e.body)?['detail'];
  return d is Map && d['attempts_left'] != null ? _int(d['attempts_left']) : null;
}

// ── API ──────────────────────────────────────────────────────────────────────

abstract class MfaApi {
  Future<MfaStatus> status();
  Future<MfaSetupInfo> setup({String? password});

  /// The login answer (a fresh token pair) + `recovery_codes`.
  Future<Map<String, dynamic>> confirm(String code);
  Future<void> disable({required String password, String? code, String? recoveryCode});
  Future<List<String>> regenerateRecoveryCodes(String code);
}

/// Super admin only: removes another user's two-step verification (lost phone AND lost recovery codes). The server
/// signs that user out everywhere; they enroll again at the next login when their role requires it. 400
/// `mfa_reset_self` for the caller's own account, 409 `mfa_not_enabled` when the user has none, 404 unknown user.
Future<void> resetUserMfa(int userId, {ApiClient? api}) async {
  await (api ?? ApiClient()).post('/api/v1/auth/mfa/users/$userId/reset');
}

List<String> recoveryCodesOf(dynamic body) =>
    body is Map && body['recovery_codes'] is List ? (body['recovery_codes'] as List).map((e) => '$e').toList() : const [];

class RemoteMfaApi implements MfaApi {
  /// [enrollToken]: the token a login hands to an admin who must enroll; null = the stored session.
  RemoteMfaApi({ApiClient? api, this.enrollToken}) : _api = api ?? ApiClient();
  final ApiClient _api;
  final String? enrollToken;
  static const _base = '/api/v1/auth/mfa';

  bool get _auth => enrollToken == null;
  Map<String, String>? get _headers => enrollToken == null ? null : {'Authorization': 'Bearer $enrollToken'};

  @override
  Future<MfaStatus> status() async =>
      MfaStatus.fromJson(await _api.get('$_base/status', auth: _auth, headers: _headers));

  @override
  Future<MfaSetupInfo> setup({String? password}) async => MfaSetupInfo.fromJson(await _api.post('$_base/setup',
      body: {'password': ?password}, auth: _auth, headers: _headers));

  @override
  Future<Map<String, dynamic>> confirm(String code) async {
    final r = await _api.post('$_base/confirm', body: {'code': normalizeTotp(code)}, auth: _auth, headers: _headers);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  @override
  Future<void> disable({required String password, String? code, String? recoveryCode}) async {
    await _api.post('$_base/disable', body: {
      'password': password,
      if (code != null && code.trim().isNotEmpty) 'code': normalizeTotp(code),
      if (recoveryCode != null && recoveryCode.trim().isNotEmpty) 'recovery_code': recoveryCode.trim(),
    });
  }

  @override
  Future<List<String>> regenerateRecoveryCodes(String code) async =>
      recoveryCodesOf(await _api.post('$_base/recovery-codes', body: {'code': normalizeTotp(code)}));
}
