// lib/features/auth/biometric.dart
// ─────────────────────────────────────────────────────────────────────────────
// Fingerprint / Face ID sign-in (D-082). Android 9+ and iOS only; never on web.
//
// The refresh token is NOT kept across a sign-out. Each phone enrolls its own device-bound key instead:
//   enrol   an Ed25519 key pair made here (package:cryptography, pure Dart); the private seed goes to the keystore
//           (BiometricKeyStore in lib/core/token_storage.dart), the public key to POST /auth/biometric/enroll with
//           the login answer's `biometric_enroll_token` (or the password, from the Security switch).
//   sign in the system prompt (local_auth, biometricOnly: never the device PIN) → POST /auth/biometric/challenge →
//           sign `nextbrain/biometric-login/v1\n<credential>\n<challenge>\n<X-Device-Id>` → POST /auth/biometric/login,
//           whose answer is the password login's (tokens, or the MFA step: the key replaces the password only).
//   forget  "Not you?", the switch off, or a server answer that the key is dead (revoked / expired / blocked device).
// The record keeps the account's name / avatar / identifier, so the login screen can greet them after a sign-out
// (which wipes the cached user).
//
// Pure, unit-tested parts (test/auth/biometric_test.dart): BiometricRecord, biometricMessage, biometricKindOf,
// biometricCodeForgetsKey, showBiometricButton, shouldAutoPromptBiometric, shouldOfferBiometric, enrollTokenFresh.
// BiometricAuth is the app-wide service (one instance); the widgets live in biometric_widgets.dart.
// Server: ../back/services/biometric_service.py, routers/auth.py (/auth/biometric/*).
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import '../../core/api_client.dart';
import '../../core/token_storage.dart';
import '../student/courses/security/device_id_service.dart';

/// Kill switch: hides the login button, the offer and the Security switch.
const kBiometricFeatureKey = 'auth.biometric';

/// The first line of every signed message (the server builds the same lines, biometric_service.message).
const kBiometricMessagePrefix = 'nextbrain/biometric-login/v1';

/// How long the login answer's enrol token is used (the server accepts it for 10 minutes).
const kBiometricEnrollTokenLife = Duration(minutes: 9);

// ── Pure parts ───────────────────────────────────────────────────────────────

/// What the phone offers, for the label and the icon.
enum BiometricKind { fingerprint, face, touchId, generic }

/// The kind from what local_auth reports. Android reports strength classes (weak / strong) rather than the sensor: a
/// strong class is a fingerprint on almost every phone, a weak-only one is usually face unlock.
BiometricKind biometricKindOf(List<BiometricType> types, {required bool ios}) {
  if (ios) {
    if (types.contains(BiometricType.face)) return BiometricKind.face;
    if (types.contains(BiometricType.fingerprint)) return BiometricKind.touchId;
    return BiometricKind.generic;
  }
  if (types.contains(BiometricType.fingerprint) || types.contains(BiometricType.strong)) {
    return BiometricKind.fingerprint;
  }
  if (types.contains(BiometricType.face)) return BiometricKind.face;
  return BiometricKind.generic;
}

/// "Sign in with fingerprint / Face ID / Touch ID / fingerprint or face".
String biometricActionLabel(BiometricKind k) => switch (k) {
      BiometricKind.fingerprint => 'bio_sign_in_fingerprint',
      BiometricKind.face => 'bio_sign_in_face',
      BiometricKind.touchId => 'bio_sign_in_touch',
      BiometricKind.generic => 'bio_sign_in_generic',
    }.tr;

/// The Security switch's label.
String biometricSettingLabel(BiometricKind k) => switch (k) {
      BiometricKind.fingerprint => 'bio_setting_fingerprint',
      BiometricKind.face => 'bio_setting_face',
      BiometricKind.touchId => 'bio_setting_touch',
      BiometricKind.generic => 'bio_setting_generic',
    }.tr;

/// The offer's title.
String biometricOfferTitle(BiometricKind k) => switch (k) {
      BiometricKind.fingerprint => 'bio_offer_title_fingerprint',
      BiometricKind.face => 'bio_offer_title_face',
      BiometricKind.touchId => 'bio_offer_title_touch',
      BiometricKind.generic => 'bio_offer_title_generic',
    }.tr;

IconData biometricIcon(BiometricKind k) => switch (k) {
      BiometricKind.face => Icons.face_retouching_natural_rounded,
      _ => Icons.fingerprint_rounded,
    };

/// The bytes the device signs (UTF-8 of these lines).
String biometricMessage(String credentialId, String challenge, String deviceId) =>
    [kBiometricMessagePrefix, credentialId, challenge, deviceId.trim()].join('\n');

/// Server codes after which the key can never work again: the app forgets it and shows the password form.
bool biometricCodeForgetsKey(String? code) => const {
      'biometric_invalid',
      'biometric_revoked',
      'biometric_expired',
      'biometric_device_blocked',
    }.contains(code);

/// The quick sign-in panel on the login screen.
bool showBiometricButton({required bool supported, required bool featureOn, required bool hasRecord}) =>
    supported && featureOn && hasRecord;

/// The system prompt opens by itself once per app run, never right after a sign-out (the person just chose to leave)
/// and never twice.
bool shouldAutoPromptBiometric({required bool visible, required bool alreadyPrompted, required bool suppressed}) =>
    visible && !alreadyPrompted && !suppressed;

/// The "use your fingerprint next time?" sheet after a sign-in: offered once per account and phone, only with a fresh
/// enrol token, and not when this account already holds the phone's key.
bool shouldOfferBiometric({
  required bool supported,
  required bool featureOn,
  required bool hasEnrollToken,
  required int userId,
  int? enrolledUserId,
  required bool declined,
}) =>
    supported && featureOn && hasEnrollToken && userId > 0 && enrolledUserId != userId && !declined;

/// The enrol token of the last login answer is still worth sending.
bool enrollTokenFresh(DateTime? receivedAt, DateTime now) =>
    receivedAt != null && now.difference(receivedAt) < kBiometricEnrollTokenLife;

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int> _b64urlDecode(String s) => base64Url.decode(s + '=' * ((4 - s.length % 4) % 4));

/// What this phone keeps for one account (secure storage). [seed] is the Ed25519 private key (32 bytes, base64url).
@immutable
class BiometricRecord {
  const BiometricRecord({
    required this.credentialId,
    required this.seed,
    required this.userId,
    required this.name,
    this.identifier,
    this.imageUrl,
  });

  final String credentialId;
  final String seed;
  final int userId;
  final String name;

  /// What the person types to sign in (e-mail / @username), to prefill the password form.
  final String? identifier;
  final String? imageUrl;

  String get firstName {
    final n = name.trim();
    if (n.isEmpty) return '';
    return n.split(RegExp(r'\s+')).first;
  }

  /// Up to two initials for the avatar fallback.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String lead(String s) => String.fromCharCode(s.runes.first);
    final first = lead(parts.first);
    return parts.length == 1 ? first.toUpperCase() : '$first${lead(parts.last)}'.toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'credential_id': credentialId,
        'seed': seed,
        'user_id': userId,
        'name': name,
        'identifier': identifier,
        'image_url': imageUrl,
      };

  /// Null for anything unreadable (a damaged or foreign record is treated as none).
  static BiometricRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final cid = raw['credential_id'], seed = raw['seed'], uid = raw['user_id'];
    if (cid is! String || cid.isEmpty || seed is! String || seed.isEmpty || uid is! int) return null;
    return BiometricRecord(
      credentialId: cid,
      seed: seed,
      userId: uid,
      name: raw['name']?.toString() ?? '',
      identifier: raw['identifier']?.toString(),
      imageUrl: raw['image_url']?.toString(),
    );
  }

  BiometricRecord withProfile({String? name, String? imageUrl}) => BiometricRecord(
        credentialId: credentialId,
        seed: seed,
        userId: userId,
        name: (name == null || name.trim().isEmpty) ? this.name : name,
        identifier: identifier,
        imageUrl: imageUrl ?? this.imageUrl,
      );
}

// ── Key operations (pure Dart Ed25519) ───────────────────────────────────────

/// A new key pair: (seed, public key), both base64url.
Future<(String, String)> newBiometricKey() async {
  final kp = await Ed25519().newKeyPair();
  final seed = await kp.extractPrivateKeyBytes();
  final pub = await kp.extractPublicKey();
  return (_b64url(seed), _b64url(pub.bytes));
}

/// The public key of a stored seed (base64url).
Future<String> biometricPublicKey(String seed) async {
  final kp = await Ed25519().newKeyPairFromSeed(_b64urlDecode(seed));
  return _b64url((await kp.extractPublicKey()).bytes);
}

/// Ed25519 signature (base64url) of [message] with the stored [seed].
Future<String> signBiometricMessage(String seed, String message) async {
  final algo = Ed25519();
  final kp = await algo.newKeyPairFromSeed(_b64urlDecode(seed));
  final sig = await algo.sign(utf8.encode(message), keyPair: kp);
  return _b64url(sig.bytes);
}

// ── The service ──────────────────────────────────────────────────────────────

/// What the system prompt answered.
enum BiometricPrompt { ok, cancelled, lockout, unavailable, failed }

/// The outcome of a fingerprint sign-in.
enum BiometricOutcome { session, mfa, cancelled, lockout, unavailable, gone, failed }

class BiometricLoginResult {
  const BiometricLoginResult(this.outcome, {this.body, this.message});

  final BiometricOutcome outcome;

  /// The server's login answer (tokens + user, or the MFA step) for [BiometricOutcome.session] / [BiometricOutcome.mfa].
  final Map<String, dynamic>? body;

  /// A sentence to show for [BiometricOutcome.failed].
  final String? message;
}

/// The outcome of an enrolment.
enum BiometricEnrollOutcome { enabled, needsPassword, cancelled, lockout, unavailable, failed }

class BiometricEnrollResult {
  const BiometricEnrollResult(this.outcome, {this.mfa = false, this.message});

  final BiometricEnrollOutcome outcome;

  /// [BiometricEnrollOutcome.needsPassword]: the account has MFA, so the code is asked for too.
  final bool mfa;
  final String? message;
}

/// The app-wide fingerprint sign-in state: platform support, the stored record, the last login's enrol token.
class BiometricAuth extends ChangeNotifier {
  BiometricAuth._({LocalAuthentication? localAuth, ApiClient? api, BiometricKeyStore? store})
      : _la = localAuth ?? LocalAuthentication(),
        _apiOverride = api,
        _store = store ?? const BiometricKeyStore();

  static final BiometricAuth instance = BiometricAuth._();

  final LocalAuthentication _la;
  final ApiClient? _apiOverride;
  final BiometricKeyStore _store;

  ApiClient get _api => _apiOverride ?? ApiClient();

  bool _loaded = false;
  bool _supported = false;
  BiometricKind _kind = BiometricKind.fingerprint;
  BiometricRecord? _record;

  String? _enrollToken;
  DateTime? _enrollTokenAt;

  bool _autoPrompted = false;
  bool _suppressAuto = false;
  bool _debugHeld = false;

  bool get loaded => _loaded;

  /// Android 9+ / iOS with an enrolled fingerprint or face.
  bool get supported => _supported;
  BiometricKind get kind => _kind;
  BiometricRecord? get record => _record;

  bool get featureOn => !AppConfig.disableList.contains(kBiometricFeatureKey);

  /// The login screen's quick sign-in panel is shown.
  bool get available => showBiometricButton(supported: _supported, featureOn: featureOn, hasRecord: _record != null);

  String? get enrollToken => enrollTokenFresh(_enrollTokenAt, DateTime.now()) ? _enrollToken : null;

  /// Reads platform support and the stored record (cheap; safe to call again, e.g. on every login screen).
  Future<void> load() async {
    if (_debugHeld) return;
    _supported = await _platformSupported();
    if (_supported) {
      try {
        final types = await _la.getAvailableBiometrics();
        if (types.isEmpty) {
          _supported = false;
        } else {
          _kind = biometricKindOf(types, ios: defaultTargetPlatform == TargetPlatform.iOS);
        }
      } catch (_) {
        _supported = false;
      }
    }
    final raw = await _store.read();
    BiometricRecord? rec;
    if (raw != null) {
      try {
        rec = BiometricRecord.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    _record = rec;
    _loaded = true;
    notifyListeners();
  }

  Future<bool> _platformSupported() async {
    if (kIsWeb) return false;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          break;
        case TargetPlatform.android:
          // Android 9+ only: BiometricPrompt is native there; the older fingerprint dialog needs an AppCompat theme
          // this app does not use (D-082).
          if ((await DeviceInfoPlugin().androidInfo).version.sdkInt < 28) return false;
        default:
          return false;
      }
      return await _la.isDeviceSupported() && await _la.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Every login answer passes through here (MyAuthProvider.completeSession): keeps its enrol token for the offer.
  void noteLoginAnswer(Map<dynamic, dynamic> result) {
    final t = result['biometric_enroll_token'];
    if (t is String && t.isNotEmpty) {
      _enrollToken = t;
      _enrollTokenAt = DateTime.now();
    }
  }

  /// The login screen calls this before opening the prompt by itself: true at most once per app run.
  bool takeAutoPrompt() {
    final go = shouldAutoPromptBiometric(visible: available, alreadyPrompted: _autoPrompted, suppressed: _suppressAuto);
    if (go) _autoPrompted = true;
    return go;
  }

  /// A sign-out: the login screen that follows must not open the prompt by itself.
  void suppressAutoPrompt() {
    _suppressAuto = true;
    _enrollToken = null;
    _enrollTokenAt = null;
  }

  /// The system prompt, biometrics only (never the device PIN / pattern).
  Future<BiometricPrompt> prompt(String reason) async {
    try {
      final ok = await _la.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return ok ? BiometricPrompt.ok : BiometricPrompt.cancelled;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.authInProgress =>
          BiometricPrompt.cancelled,
        LocalAuthExceptionCode.temporaryLockout || LocalAuthExceptionCode.biometricLockout => BiometricPrompt.lockout,
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          BiometricPrompt.unavailable,
        _ => BiometricPrompt.failed,
      };
    } catch (_) {
      return BiometricPrompt.failed;
    }
  }

  /// Prompt → challenge → signature → login. The caller turns [BiometricOutcome.session] / [BiometricOutcome.mfa]
  /// into a session exactly like a password login (MyAuthProvider.loginWithBiometric).
  Future<BiometricLoginResult> signIn() async {
    final rec = _record;
    if (rec == null) return const BiometricLoginResult(BiometricOutcome.gone);
    final p = await prompt('bio_prompt_reason'.tr);
    switch (p) {
      case BiometricPrompt.ok:
        break;
      case BiometricPrompt.cancelled:
        return const BiometricLoginResult(BiometricOutcome.cancelled);
      case BiometricPrompt.lockout:
        return const BiometricLoginResult(BiometricOutcome.lockout);
      case BiometricPrompt.unavailable:
        return const BiometricLoginResult(BiometricOutcome.unavailable);
      case BiometricPrompt.failed:
        return const BiometricLoginResult(BiometricOutcome.failed);
    }
    final deviceId = await DeviceIdService.instance.id();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final ch = await _api.post('/api/v1/auth/biometric/challenge', auth: false, body: {'credential_id': rec.credentialId});
        final challenge = ch is Map ? ch['challenge']?.toString() : null;
        if (challenge == null || challenge.isEmpty) throw ApiException.from('empty answer');
        final signature = await signBiometricMessage(rec.seed, biometricMessage(rec.credentialId, challenge, deviceId));
        final r = await _api.post('/api/v1/auth/biometric/login', auth: false, body: {
          'credential_id': rec.credentialId,
          'challenge': challenge,
          'signature': signature,
        });
        if (r is! Map) throw ApiException.from('empty answer');
        final body = Map<String, dynamic>.from(r);
        final mfa = body['mfa_required'] == true || body['mfa_enrollment_required'] == true;
        if (!mfa && body['access_token'] == null) throw ApiException.from('empty answer');
        return BiometricLoginResult(mfa ? BiometricOutcome.mfa : BiometricOutcome.session, body: body);
      } catch (e) {
        final ex = ApiException.from(e);
        // the challenge was used / expired in between (a slow network): one fresh one
        if (ex.code == 'biometric_challenge_invalid' && attempt == 0) continue;
        if (biometricCodeForgetsKey(ex.code)) {
          await forget();
          return const BiometricLoginResult(BiometricOutcome.gone);
        }
        return BiometricLoginResult(BiometricOutcome.failed, message: ex.message);
      }
    }
    return const BiometricLoginResult(BiometricOutcome.failed);
  }

  /// After a successful sign-in: keep the name / avatar the login screen shows up to date.
  Future<void> refreshProfile({required int userId, String? name, String? imageUrl}) async {
    final rec = _record;
    if (rec == null || rec.userId != userId) return;
    final next = rec.withProfile(name: name, imageUrl: imageUrl);
    _record = next;
    await _store.write(jsonEncode(next.toJson()));
    notifyListeners();
  }

  /// Turns fingerprint sign-in on for the signed-in account: the system prompt first ([confirm]), then a new key
  /// registered with the login's enrol token, or [password] (+ [code]) when there is none.
  Future<BiometricEnrollResult> enroll({
    required int userId,
    required String name,
    String? identifier,
    String? imageUrl,
    String? password,
    String? code,
    bool confirm = true,
  }) async {
    if (confirm) {
      final p = await prompt('bio_enable_reason'.tr);
      if (p != BiometricPrompt.ok) {
        return BiometricEnrollResult(switch (p) {
          BiometricPrompt.lockout => BiometricEnrollOutcome.lockout,
          BiometricPrompt.unavailable => BiometricEnrollOutcome.unavailable,
          BiometricPrompt.failed => BiometricEnrollOutcome.failed,
          _ => BiometricEnrollOutcome.cancelled,
        });
      }
    }
    final token = enrollToken;
    if (token == null && (password == null || password.isEmpty)) {
      return const BiometricEnrollResult(BiometricEnrollOutcome.needsPassword);
    }
    try {
      final (seed, publicKey) = await newBiometricKey();
      final r = await _api.post('/api/v1/auth/biometric/enroll', body: {
        'public_key': publicKey,
        'enroll_token': ?token,
        if (password != null && password.isNotEmpty) 'password': password,
        if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
        'device_name': await DeviceIdService.instance.name(),
        'platform': DeviceIdService.platform,
      });
      final cid = r is Map ? r['credential_id']?.toString() : null;
      if (cid == null || cid.isEmpty) throw ApiException.from('empty answer');
      final rec = BiometricRecord(
        credentialId: cid,
        seed: seed,
        userId: userId,
        name: name,
        identifier: identifier,
        imageUrl: imageUrl,
      );
      await _store.write(jsonEncode(rec.toJson()));
      _record = rec;
      _enrollToken = null;
      _enrollTokenAt = null;
      notifyListeners();
      return const BiometricEnrollResult(BiometricEnrollOutcome.enabled);
    } catch (e) {
      final ex = ApiException.from(e);
      if (ex.code == 'biometric_reauth_required') {
        final d = ApiException.asMap(ex.body)?['detail'];
        _enrollToken = null;
        return BiometricEnrollResult(BiometricEnrollOutcome.needsPassword, mfa: d is Map && d['mfa'] == true);
      }
      return BiometricEnrollResult(BiometricEnrollOutcome.failed, message: ex.message);
    }
  }

  /// The Security switch off: the server forgets the key (best effort), then this phone does.
  Future<void> disable() async {
    final rec = _record;
    if (rec != null) {
      try {
        await _api.delete('/api/v1/auth/biometric/${rec.credentialId}');
      } catch (_) {/* offline: the key dies with the local seed, and the server's idle limit closes it */}
    }
    await forget();
  }

  /// "Not you?" / a dead key: only this phone forgets it.
  Future<void> forget() async {
    _record = null;
    await _store.clear();
    notifyListeners();
  }

  // ── "Not now" on the offer, remembered per account on this phone ──────────

  static String _declinedKey(int userId) => 'biometric.offer_declined.$userId';

  Future<bool> declined(int userId) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_declinedKey(userId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setDeclined(int userId, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      value ? await p.setBool(_declinedKey(userId), true) : await p.remove(_declinedKey(userId));
    } catch (_) {}
  }

  /// Tests / visual renders: fixed values that [load] then leaves alone (until [debugReset]).
  @visibleForTesting
  void debugSet({
    bool? supported,
    BiometricKind? kind,
    BiometricRecord? record,
    bool clearRecord = false,
    bool autoPrompt = false,
  }) {
    _debugHeld = true;
    _loaded = true;
    if (supported != null) _supported = supported;
    if (kind != null) _kind = kind;
    if (record != null) _record = record;
    if (clearRecord) _record = null;
    _autoPrompted = !autoPrompt; // no platform prompt in a test unless asked for
    _suppressAuto = false;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _debugHeld = false;
    _loaded = false;
    _supported = false;
    _kind = BiometricKind.fingerprint;
    _record = null;
    _enrollToken = null;
    _enrollTokenAt = null;
    _autoPrompted = false;
    _suppressAuto = false;
  }
}
