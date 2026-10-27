library;

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../config/storage_service.dart';
import '../../core/api_client.dart';
import '../../core/base_provider.dart';
import '../../utils/helpers.dart';
import '../../utils/widget/view_as_state.dart';
import '../../core/app_mode.dart';
import '../shared/category/categories_provider.dart';
import '../shared/notification/notification_service.dart';
import 'mfa.dart';
import 'teacher_onboarding_token.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class UserModel {
  final int id;
  final String name;
  final String gmail;
  final String role;
  final String? phone;
  final String? country;
  final String? dob;
  final String? bio;
  final String? imageUrl;
  final String? registrationStep;
  final DateTime lastLogin;

  const UserModel({
    required this.id,
    required this.name,
    required this.gmail,
    required this.role,
    this.phone,
    this.country,
    this.dob,
    this.bio,
    this.imageUrl,
    this.registrationStep,
    required this.lastLogin,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
    id: j['id'] as int,
    name: j['name'] as String,
    gmail: j['gmail'] as String,
    role: j['role'] as String,
    phone: j['phone'] as String?,
    lastLogin: j['last_login'] == null
        ? DateTime.now()
        : (j['last_login'] as String).toLocalSaTime,
    country: j['country'] as String?,
    dob: j['dob'] as String?,
    bio: j['bio'] as String?,
    imageUrl: j['image_url'] as String?,
    registrationStep: j['registration_step'] as String?,
  );

  /// Convert back to JSON for caching in SharedPreferences.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'gmail': gmail,
    'role': role,
    'phone': phone,
    'country': country,
    'dob': dob,
    'bio': bio,
    'last_login': lastLogin.toIso8601String(),
    'image_url': imageUrl,
    'registration_step': registrationStep,
  };
}

/// A phone-verification-by-link session (Telegram / WhatsApp), from POST /auth/phone-link/start.
class PhoneLinkSession {
  final String token;
  final bool verified;

  /// Methods the admin allowed and the server configured, highest priority first
  /// ("telegram" always comes before "whatsapp").
  final List<String> methods;
  final int expiresIn;
  final String? telegramUrl; // https://t.me/<bot>?start=<token>
  final String? telegramAppUrl; // tg://resolve?... (opens the app directly)
  final String? whatsappUrl; // https://wa.me/<number>?text=...

  const PhoneLinkSession({
    required this.token,
    required this.verified,
    required this.methods,
    required this.expiresIn,
    this.telegramUrl,
    this.telegramAppUrl,
    this.whatsappUrl,
  });

  factory PhoneLinkSession.fromJson(Map j) {
    final tg = j['telegram'] is Map ? j['telegram'] as Map : const {};
    final wa = j['whatsapp'] is Map ? j['whatsapp'] as Map : const {};
    return PhoneLinkSession(
      token: (j['token'] ?? '').toString(),
      verified: j['verified'] == true,
      methods: j['methods'] is List
          ? (j['methods'] as List).map((e) => e.toString()).toList()
          : const [],
      expiresIn: (j['expires_in'] as num?)?.toInt() ?? 600,
      telegramUrl: tg['url']?.toString(),
      telegramAppUrl: tg['app_url']?.toString(),
      whatsappUrl: wa['url']?.toString(),
    );
  }
}

/// A way a password-reset code can be sent by, with the masked destination
/// (from POST /auth/forgot-password -> `ways`).
class ResetWay {
  final String way; // email | whatsapp | sms
  final String? masked;

  const ResetWay(this.way, this.masked);
}

/// Outcome of [MyAuthProvider.googleAuth].
enum GoogleAuthResult {
  /// Signed in (account created first when the e-mail was new).
  success,

  /// New e-mail: the app must ask for a role, then call again with it.
  roleRequired,

  /// Account exists but a channel (usually the phone) still needs verifying.
  needsVerification,

  /// Google was fine, the account needs its second factor ([MyAuthProvider.mfaStep]: a code, or an enrollment).
  mfa,

  failed,
}

// ── Provider ──────────────────────────────────────────────────────────────────

class MyAuthProvider extends BaseProvider {
  final ApiClient _api;
  final StorageService _storage;

  // ── Admin-controlled auth policy (GET /auth/policy) ────────────────────────
  /// email | phone | both  — what a new account must verify.
  String verificationMethod = 'email';
  /// email | phone | either — what the login form accepts.
  String loginIdentifier = 'email';
  /// sms | whatsapp | telegram | whatsapp_link | telegram_whatsapp — how the phone is verified.
  /// sms / whatsapp send a code; the others make the student message us through a link.
  String otpPhoneChannel = 'sms';
  bool policyLoaded = false;

  /// Every way the admin allows AND the server can send, in offering order
  /// (Telegram > E-mail > WhatsApp > SMS, or the admin's default first).
  List<String> verificationWays = const ['email'];

  /// The way offered first.
  String defaultWay = 'email';

  /// E-mail AND phone must both be verified (otherwise any one way is enough).
  bool requireAll = false;

  /// What the login form accepts: any of "email" / "phone".
  List<String> loginIdentifiers = const ['email'];

  /// How WhatsApp is verified: "link" (student messages us) or "code" (we send a code).
  String whatsappDelivery = 'link';

  /// True when [way] ("telegram" | "whatsapp" | "email" | "sms") is verified by a link, not a code.
  bool wayIsLink(String way) =>
      way == 'telegram' || (way == 'whatsapp' && whatsappDelivery == 'link');

  bool get hasPhoneWays => verificationWays.any((w) => w != 'email');

  /// True when at least one phone way is verified by a Telegram / WhatsApp link.
  bool get phoneUsesLink =>
      verificationWays.any((w) => w != 'email' && wayIsLink(w));

  /// Password-reset ways of the account that is resetting (filled by [forgotPassword]).
  List<ResetWay> resetWays = const [];

  /// The way the reset code was sent by.
  String? resetSentVia;

  /// Where a password-reset code really went when the student asked by phone number
  /// but phone verification is link-based (the code goes to the e-mail). Null otherwise.
  String? resetEmailMasked;

  /// A phone is ALWAYS required to register (e-mail is not a way, or both are required).
  /// When it is only needed for the picked way, the register screen decides.
  bool get verifyByPhone =>
      hasPhoneWays && (requireAll || !verificationWays.contains('email'));
  bool get loginAllowsEmail => loginIdentifiers.contains('email');
  bool get loginAllowsPhone => loginIdentifiers.contains('phone');

  /// Filled by register/login/verify: channels still to verify ("email"/"phone")
  /// and the data the OTP screen needs.
  List<String> pendingChannels = const ['email'];
  String? pendingGmail;
  String? pendingPhoneMasked;

  Future<void> loadPolicy() async {
    try {
      final r = await _api.get('/api/v1/auth/policy', auth: false);
      if (r is Map) {
        verificationMethod = (r['verification_method'] ?? 'email').toString();
        loginIdentifier = (r['login_identifier'] ?? 'email').toString();
        otpPhoneChannel = (r['otp_phone_channel'] ?? 'sms').toString();
        // New checkbox policy (an older server only sends the three values above).
        if (r['verification_ways'] is List &&
            (r['verification_ways'] as List).isNotEmpty) {
          verificationWays =
              (r['verification_ways'] as List).map((e) => e.toString()).toList();
          defaultWay = (r['default_way'] ?? verificationWays.first).toString();
          requireAll = r['require_all'] == true;
          whatsappDelivery = (r['whatsapp_delivery'] ?? 'link').toString();
        } else {
          final both = verificationMethod == 'both';
          final phone = verificationMethod != 'email';
          verificationWays = [
            if (verificationMethod != 'phone') 'email',
            if (phone)
              ...switch (otpPhoneChannel) {
                'telegram' => ['telegram'],
                'whatsapp_link' || 'whatsapp' => ['whatsapp'],
                'telegram_whatsapp' => ['telegram', 'whatsapp'],
                _ => ['sms'],
              },
          ];
          defaultWay = verificationWays.first;
          requireAll = both;
          whatsappDelivery = otpPhoneChannel == 'whatsapp' ? 'code' : 'link';
        }
        loginIdentifiers = r['login_identifiers'] is List
            ? (r['login_identifiers'] as List).map((e) => e.toString()).toList()
            : switch (loginIdentifier) {
                'phone' => ['phone'],
                'either' => ['email', 'phone'],
                _ => ['email'],
              };
        policyLoaded = true;
        notifyListeners();
      }
    } catch (e) {
      log('loadPolicy failed: $e'); // keep defaults (email / email)
    }
  }

  List<String> _channelsFrom(dynamic v, List<String> fallback) =>
      v is List ? v.map((e) => e.toString()).toList() : fallback;

  MyAuthProvider({ApiClient? api, required StorageService storage})
      : _api = api ?? ApiClient(),
        _storage = storage {
    // Restore the user from disk immediately so role/isTeacher are ready
    // before the first frame is drawn — no async gap, no null user.
    loadCachedUser();
  }

  Future<void> loadSpecialization(BuildContext context) async {
    makeLoading();
    specializations = await context
        .read<CategoriesProvider>()
        .getSpecialization();
    stopLoading();
  }

  // ── Dropdown options ──────────────────────────────────────────────────────────
  List<Map<String, String>> teachingTypes = [
    {'text': 'live'},
    {'text': 'recorded'},
    {'text': 'both'},
  ];
  List<Map<String, String>> paymentTypes = [
    {'text': 'free'},
    {'text': 'paid'},
  ];
  List<Map<String, String>> roles = [
    {'text': 'student'},
    {'text': 'teacher'},
    {'text': 'parent'},
  ];
  late List<Map<String, dynamic>> specializations;
  Map<String, dynamic>? selectedTeachingType;
  Map<String, dynamic>? selectedPaymentType;
  Map<String, dynamic>? selectedSpecialization;
  Map<String, dynamic>? selectedRole;

  // ── State ─────────────────────────────────────────────────────────────────────
  UserModel? _currentUser;
  bool isLoadingAdditionalRegistration = false;
  bool isLoadingRegistration = false;
  bool isLoadingLogin = false;

  /// Set by login() when the server answers 403 (account inactive / unverified).
  bool needsVerification = false;
  String? pendingRole; // role from the 403 body, if the backend sends it

  /// From the login answer: an account a teacher created by importing a sheet must first be completed
  /// (new password, missing e-mail / phone / name). Read by DataLabGate right after login. null = nothing to do.
  Map<String, dynamic>? accountSetup;

  /// Set by [login] / [googleAuth] when the server asks for the second factor (or for an enrollment) instead of
  /// handing out tokens. Cleared by every new login and by [logout].
  MfaLoginStep mfaStep = MfaLoginStep.none;

  /// Text of the last failed [verifyMfa], and how many codes the step still accepts.
  String? mfaError;
  int? mfaAttemptsLeft;
  bool isVerifyingMfa = false;

  /// True when the step token is dead (expired, used, 5 wrong codes): the user must sign in again.
  bool mfaStepDead = false;

  /// Second login step: an authenticator [code] or a [recoveryCode]. On success the session is saved exactly like
  /// a normal login. Not wrapped in run(): the error code and the attempts left matter here.
  Future<bool> verifyMfa({String? code, String? recoveryCode}) async {
    final token = mfaStep.token;
    if (mfaStep.kind != MfaStepKind.verify || token == null) return false;
    isVerifyingMfa = true;
    mfaError = null;
    notifyListeners();
    try {
      final r = await _api.post('/api/v1/auth/mfa/verify', auth: false, body: {
        'mfa_token': token,
        if (code != null && code.trim().isNotEmpty) 'code': normalizeTotp(code),
        if (recoveryCode != null && recoveryCode.trim().isNotEmpty) 'recovery_code': recoveryCode.trim(),
      });
      if (r is! Map || r['access_token'] == null) throw ApiException.from('empty answer');
      await completeSession(r);
      mfaStep = MfaLoginStep.none;
      return true;
    } catch (e) {
      final ex = ApiException.from(e);
      mfaAttemptsLeft = attemptsLeftOf(ex);
      mfaStepDead = mfaFailureEndsStep(ex.code, mfaAttemptsLeft);
      // the last wrong code burned the step: say so ("sign in again"), not just "the code is not correct"
      final burned = mfaStepDead && !mfaStepIsDead(ex.code);
      mfaError = burned ? mfaCodeText('mfa_token_locked', ex.message) : mfaCodeText(ex.code, ex.message);
      return false;
    } finally {
      isVerifyingMfa = false;
      notifyListeners();
    }
  }

  /// Saves a login answer (tokens + user) and registers the push token: used by [login], [googleAuth], the second
  /// step and the MFA confirmation (which rotates the token pair).
  Future<void> completeSession(Map<dynamic, dynamic> result) async {
    await _persistTokens(result);
    TeacherOnboardingToken.readFrom(result);
    _readAccountSetup(result);
    final userJson = result['user'];
    if (userJson is Map) {
      final m = Map<String, dynamic>.from(userJson);
      _currentUser = UserModel.fromJson(m);
      await _storage.saveUser(m);
    }
    await NotificationService.instance.registerWithBackend(_api);
    notifyListeners();
  }

  void _resetMfa() {
    mfaStep = MfaLoginStep.none;
    mfaError = null;
    mfaAttemptsLeft = null;
    mfaStepDead = false;
  }

  void _readAccountSetup(Map result) {
    final s = result['account_setup'];
    accountSetup = (s is Map && s['required'] == true) ? Map<String, dynamic>.from(s) : null;
  }
  UserModel? get currentUser => _currentUser;

  bool get isStudent => currentUser?.role == 'student';

  bool get selectedRoleIsStudent => selectedRole!['text'] == 'student';

  /// Teacher-only registration extras (specialization, teaching type …) must key off THIS,
  /// not off `!selectedRoleIsStudent`, now that a third role (parent) exists.
  bool get selectedRoleIsTeacher => selectedRole!['text'] == 'teacher';

  bool get isTeacher => currentUser?.role == 'teacher';

  bool get isParent => currentUser?.role == 'parent';

  bool get isAdmin => currentUser?.role == 'admin';

  bool get isSuper => currentUser?.role == 'super-admin';

  /// A cached user AND a stored session: logout, a rejected refresh or a wipe of secure storage all end it.
  bool get isAuthenticated => _currentUser != null && _api.hasSession;

  String get homeRoute => switch (currentUser?.role ?? 'student') {
    'admin' => '/admin_dashboard',
    'super-admin' => '/admin_dashboard',
    'developer' => '/admin_dashboard',
    'teacher' => '/teacher_dashboard',
    'parent' => '/parent_dashboard',
    // organizations: org admins and their staff (admin assistants, department staff) open the org dashboard
    // (both: the personal dashboard instead when they left their organization last time — remembered per user)
    'org-admin' => AppModeController.orgRoleHome('/org_dashboard', personal: _personalHome),
    // … unless the member dashboard already knows this staff member manages nothing (e.g. an assistant only)
    // (on a cold start the overview is not loaded yet → the answer cached by the last run)
    'org-staff' => AppModeController.orgRoleHome(
        AppModeController.orgStaffHome(
            loaded: AppModeController.instance.loaded,
            managesNothing: AppModeController.instance.managesNothing,
            cached: currentUser == null ? null : _storage.getFlag(AppModeController.managesNothingKey(currentUser!.id))),
        personal: _personalHome),
    _ => '/dashboard',
  };

  bool? get _personalHome =>
      currentUser == null ? null : _storage.getFlag(AppModeController.personalHomeKey(currentUser!.id));

  // ── Cold-start restore ────────────────────────────────────────────────────────

  void loadCachedUser() {
    final saved = _storage.savedUser;
    if (saved != null) {
      _currentUser = UserModel.fromJson(saved);
    }
  }

  // ── Step 1: Register ──────────────────────────────────────────────────────────

  Future<bool> register({
    required String name,
    required String gmail,
    required String password,
    String? phone,
    String? country,
    String? dob,
    String? way,
  }) async {
    isLoadingRegistration = true;
    notifyListeners();
    final result = await run(
          () => _api.post(
        '/api/v1/auth/register',
        body: {
      'name': name,
      'gmail': gmail,
      'password': password,
      'role': selectedRole!['text'],
      'phone': ?phone,
      'country': ?country,
      'dob': ?dob,
      'way': ?way,
      },
        auth: false,
      ),
    );

    if (result is Map) {
      pendingGmail = result['gmail']?.toString() ?? gmail;
      pendingChannels = _channelsFrom(result['pending_channels'], const ['email']);
      pendingPhoneMasked = phone;
      if (result['otp_phone_channel'] != null) {
        otpPhoneChannel = result['otp_phone_channel'].toString();
      }
    }
    isLoadingRegistration = false;
    notifyListeners();
    return result != null;
  }

  // ── Step 2: Verify OTP ────────────────────────────────────────────────────────

  /// On success the server returns the same shape as login:
  ///   { registration_step, ... }
  /// We save the user here so teachers know they need step 3.
  /// [channel] = "email" | "phone". After a success, [pendingChannels] holds what is
  /// still left (e.g. ["phone"] when the admin requires both) — empty = fully verified.
  Future<bool> verifyOtp({
    required String gmail,
    required String code,
    String? channel,
    String? way,
  }) async {
    final result = await run(
          () => _api.post(
        '/api/v1/auth/verify-otp',
        body: {'gmail': gmail, 'code': code, 'channel': ?channel, 'way': ?way},
        auth: false,
      ),
    );

    if (result != null && result is Map) {
      TeacherOnboardingToken.readFrom(result); // a teacher who still owes profile / documents
      pendingChannels = _channelsFrom(result['pending_channels'], const []);
      // The verify-otp response does NOT return tokens — the user still
      // needs to log in (or the server returns tokens — adapt if needed).
      // If your server returns user data here, save it:
      if (result.containsKey('user')) {
        final userJson = result['user'] as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(userJson);
        await _storage.saveUser(userJson);
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Phone verification by Telegram / WhatsApp link ──────────────────────────

  /// Creates a link session for [gmail] (e-mail or phone). Null on error (see errorMessage).
  Future<PhoneLinkSession?> startPhoneLink(String gmail) async {
    final result = await run(
          () => _api.post(
        '/api/v1/auth/phone-link/start',
        body: {'gmail': gmail},
        auth: false,
      ),
    );
    if (result is Map) return PhoneLinkSession.fromJson(result);
    return null;
  }

  /// Polls a link session: 'pending' | 'verified' | 'expired' | 'error'.
  /// On 'verified', [pendingChannels] holds what is still left (e.g. ["email"]).
  /// Deliberately not wrapped in run(): it fires every 2 seconds and must stay silent.
  Future<String> checkPhoneLink(String token) async {
    try {
      final r = await _api.get(
        '/api/v1/auth/phone-link/status?token=${Uri.encodeQueryComponent(token)}',
        auth: false,
      );
      if (r is Map) {
        final state = (r['state'] ?? 'pending').toString();
        if (state == 'verified') {
          pendingChannels = _channelsFrom(r['pending_channels'], const []);
          notifyListeners();
        }
        return state;
      }
    } catch (e) {
      log('checkPhoneLink failed: $e');
      if (e is ApiException && e.statusCode == 404) return 'expired';
    }
    return 'error';
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────────

  /// Sends a code again. [way] = email | telegram | whatsapp | sms | null (the server picks).
  /// For a password reset ([reset] = true) it hits forgot-password with the chosen way.
  Future<bool> resendOtp(
      String gmail, {
        bool reset = false,
        String? channel,
        String? way,
      }) async {
    final result = await run(
          () => _api.post(
        reset ? '/api/v1/auth/forgot-password' : '/api/v1/auth/resend-otp',
        body: {'gmail': gmail, if (!reset) 'channel': ?channel, 'way': ?way},
        auth: false,
      ),
    );
    if (reset && result is Map) _readResetInfo(result);
    return result != null;
  }

  // ── Step 3 (Teachers): Complete Profile ───────────────────────────────────────

  Future<bool> completeTeacherProfile({
    required int experienceYears,
    required String email,
    String? bio,
  }) async {
    isLoadingAdditionalRegistration = true;
    notifyListeners();

    final result = await run(
          () => _api.post(
        '/api/v1/auth/teacher-profile',
        body: {
          'experience_years': experienceYears,
          'teaching_type': selectedTeachingType!['text'],
          'payment_type': selectedPaymentType!['text'],
          'gmail': email,
          'specialization_id': selectedSpecialization!['id'],
          if (bio != null && bio.trim().isNotEmpty) 'about': bio.trim(),
        },
        headers: TeacherOnboardingToken.headers,
      ),
    );
    TeacherOnboardingToken.readFrom(result); // the documents step uses the renewed token

    isLoadingAdditionalRegistration = false;
    notifyListeners();
    return result != null;
  }

  // ── Edit registration fields later (update-profile screen, everything
  //    except email) ───────────────────────────────────────────────────────
  int? teacherExperienceYears;
  int? teacherSpecializationId;
  String? teacherTeachingType;
  String? teacherPaymentType;
  bool isLoadingTeacherExtras = false;

  /// Fetches the teacher's current experience/specialization/teaching/payment
  /// values and pre-selects the matching dropdown entries. Call
  /// loadSpecialization(context) first so `specializations` is populated,
  /// or the specialization match will silently no-op.
  Future<void> loadTeacherProfileExtras() async {
    isLoadingTeacherExtras = true;
    notifyListeners();

    final result = await run(
          () => _api.get('/api/v1/auth/teacher-profile-extras'),
    );
    if (result != null && result is Map) {
      teacherExperienceYears = result['experience_years'] as int?;
      teacherSpecializationId = result['specialization_id'] as int?;
      teacherTeachingType = result['teaching_type'] as String?;
      teacherPaymentType = result['payment_type'] as String?;

      if (teacherSpecializationId != null) {
        try {
          selectedSpecialization = specializations.firstWhere(
                (e) => e['id'] == teacherSpecializationId,
          );
        } catch (_) {
          // specializations not loaded yet, or id no longer exists — leave unset
        }
      }
      if (teacherTeachingType != null) {
        selectedTeachingType = teachingTypes.firstWhere(
              (e) => e['text'] == teacherTeachingType,
          orElse: () => teachingTypes.first,
        );
      }
      if (teacherPaymentType != null) {
        selectedPaymentType = paymentTypes.firstWhere(
              (e) => e['text'] == teacherPaymentType,
          orElse: () => paymentTypes.first,
        );
      }
    }

    isLoadingTeacherExtras = false;
    notifyListeners();
  }

  Future<bool> updateTeacherProfileExtras({
    int? experienceYears,
    int? specializationId,
    String? teachingType,
    String? paymentType,
  }) async {
    final result = await run(
          () => _api.put(
        '/api/v1/auth/teacher-profile-extras',
        body: {
      'experience_years': ?experienceYears,
      'specialization_id': ?specializationId,
      'teaching_type': ?teachingType,
      'payment_type': ?paymentType,
      },
      ),
    );
    return result != null;
  }

  // ── Login ─────────────────────────────────────────────────────────────────────

  /// Authenticates the user, saves tokens + user object to disk.
  /// [gmail] is the e-mail OR the phone number, depending on the admin's login policy.
  Future<bool> login({required String gmail, required String password}) async {
    isLoadingLogin = true;
    // Reset from any previous attempt, otherwise a stale flag from an earlier
    // unverified login would send a later wrong-password attempt to the OTP screen.
    needsVerification = false;
    pendingRole = null;
    _resetMfa();
    notifyListeners();
    final previousUser = _currentUser;
    _currentUser = UserModel(
      id: 0,
      name: '',
      gmail: gmail,
      role: 'student',
      lastLogin: DateTime.now(),
    );
    final result = await run(() async {
      try {
        return await _api.post(
          '/api/v1/auth/login',
          body: {'gmail': gmail, 'password': password},
          auth: false,
        );
      } on ApiException catch (e) {
        // Only an UNVERIFIED account goes to the OTP screen. A deactivated
        // account (also 403) must show its error instead.
        if (e.statusCode == 403 && e.code == 'ACCOUNT_NOT_VERIFIED') {
          needsVerification = true;
          final b = ApiException.asMap(e.body);
          final d = b?['detail'];
          if (d is Map) {
            pendingRole = d['role']?.toString();
            pendingGmail = d['gmail']?.toString();
            pendingChannels = _channelsFrom(d['pending_channels'], const ['email']);
            pendingPhoneMasked = d['phone_masked']?.toString();
            if (d['otp_phone_channel'] != null) {
              otpPhoneChannel = d['otp_phone_channel'].toString();
            }
          }
        }
        rethrow;
      }
    });
    // Two-factor accounts: no tokens yet, the login screen opens the code (or enrollment) screen.
    final step = MfaLoginStep.fromLogin(result);
    if (step.kind != MfaStepKind.none) {
      mfaStep = step;
      mfaAttemptsLeft = step.attemptsLeft;
      _currentUser = previousUser;
      isLoadingLogin = false;
      notifyListeners();
      return false;
    }
    if (result != null && result is Map) {
      // Tokens + cached user (SharedPreferences) + push token
      await completeSession(result);
      isLoadingLogin = false;
      notifyListeners();
      return true;
    }

    _currentUser = previousUser; // failed login: drop the id-0 placeholder (it made currentUser look logged-in as a student)
    isLoadingLogin = false;
    notifyListeners();
    return false;
  }
  // ── Google sign-in / sign-up ──────────────────────────────────────────────────

  bool isLoadingGoogle = false;

  /// Filled when the server answers "new account, pick a role" (shown in the role sheet).
  String? googleName;
  String? googleEmail;

  void setGoogleBusy(bool v) {
    if (isLoadingGoogle == v) return;
    isLoadingGoogle = v;
    notifyListeners();
  }

  /// [idToken] is the Firebase ID token of a Google sign-in. [role] is only needed for a
  /// brand-new account; [phone] only when the admin verifies accounts by phone.
  /// Same session handling as [login] (tokens + cached user + push token).
  Future<GoogleAuthResult> googleAuth({
    required String idToken,
    String? role,
    String? phone,
  }) async {
    isLoadingGoogle = true;
    needsVerification = false;
    pendingRole = null;
    _resetMfa();
    var roleRequired = false;
    notifyListeners();

    final result = await run(() async {
      try {
        return await _api.post(
          '/api/v1/auth/google',
          body: {'id_token': idToken, 'role': ?role, 'phone': ?phone},
          auth: false,
        );
      } on ApiException catch (e) {
        final d = ApiException.asMap(e.body)?['detail'];
        if (e.statusCode == 409 && e.code == 'GOOGLE_ROLE_REQUIRED') {
          roleRequired = true;
          if (d is Map) {
            googleName = d['name']?.toString();
            googleEmail = d['gmail']?.toString();
          }
        } else if (e.statusCode == 403 && e.code == 'ACCOUNT_NOT_VERIFIED') {
          needsVerification = true;
          if (d is Map) {
            pendingRole = d['role']?.toString();
            pendingGmail = d['gmail']?.toString();
            pendingChannels = _channelsFrom(d['pending_channels'], const ['email']);
            pendingPhoneMasked = d['phone_masked']?.toString();
            if (d['otp_phone_channel'] != null) {
              otpPhoneChannel = d['otp_phone_channel'].toString();
            }
          }
        }
        rethrow;
      }
    });

    final step = MfaLoginStep.fromLogin(result);
    if (step.kind != MfaStepKind.none) {
      mfaStep = step;
      mfaAttemptsLeft = step.attemptsLeft;
      isLoadingGoogle = false;
      notifyListeners();
      return GoogleAuthResult.mfa;
    }
    if (result != null && result is Map) {
      await completeSession(result);
      isLoadingGoogle = false;
      notifyListeners();
      return GoogleAuthResult.success;
    }

    isLoadingGoogle = false;
    notifyListeners();
    if (roleRequired) return GoogleAuthResult.roleRequired;
    if (needsVerification) return GoogleAuthResult.needsVerification;
    return GoogleAuthResult.failed;
  }

  // ── Refresh Token ─────────────────────────────────────────────────────────────

  Future<bool> refreshToken(String refreshToken) async {
    final result = await run(
          () => _api.post(
        '/api/v1/auth/refresh',
        body: {'refresh_token': refreshToken},
        auth: false,
      ),
    );

    if (result != null && result is Map) {
      await _persistTokens(result);
      return true;
    }
    return false;
  }

  // ── Get Current User (network refresh) ───────────────────────────────────────

  /// Fetches fresh user data from the server and updates the local cache.
  Future<UserModel?> getMe() async {
    final result = await run(() => _api.get('/api/v1/auth/me'));
    if (result != null && result is Map<String, dynamic>) {
      saveUserLocally(UserModel.fromJson(result));
    }
    return _currentUser;
  }

  Future<void> saveUserLocally(UserModel user) async {
    _currentUser = user;
    // In view-as, /auth/me returns the VIEWED user. Keep it in memory only: writing it to disk replaced
    // the admin's cached profile, so after exiting (or restarting) the admin became a "student".
    if (!ViewAsState.active) await _storage.saveUser(user.toJson());
    notifyListeners();
  }

  /// Called when view-as ends: forget the viewed user and bring back the admin's own cached profile.
  void restoreOwnUser() {
    loadCachedUser();
    notifyListeners();
  }

  // ── Change Password ───────────────────────────────────────────────────────────

  Future<bool> changePassword({
    required String email,
    required String password,
    required String code,
  }) async {
    final result = await run(
          () => _api.put(
        '/api/v1/auth/reset-password',
        body: {'gmail': email, 'new_password': password, 'code': code},
        auth: false,
      ),
    );
    return result != null;
  }

  /// Checks a PASSWORD_RESET code WITHOUT consuming it (the code is consumed
  /// later by reset-password). The registration endpoint /verify-otp must not
  /// be used here: it checks the EMAIL_VERIFICATION purpose.
  Future<bool> verifyResetOtp({
    required String gmail,
    required String code,
  }) async {
    final result = await run(
          () => _api.post(
        '/api/v1/auth/verify-reset-otp',
        body: {'gmail': gmail, 'code': code},
        auth: false,
      ),
    );
    return result != null;
  }

  // ── Forgot Password ───────────────────────────────────────────────────────────
  bool isLoadingForget = false;

  Future<bool> forgotPassword(String gmail, {String? way}) async {
    isLoadingForget = true;
    resetEmailMasked = null;
    resetWays = const [];
    resetSentVia = null;
    notifyListeners();
    final result = await run(
          () => _api.post(
        '/api/v1/auth/forgot-password',
        body: {'gmail': gmail, 'way': ?way},
        auth: false,
      ),
    );
    if (result is Map) _readResetInfo(result, typed: gmail);
    isLoadingForget = false;
    notifyListeners();
    return result != null;
  }

  /// Reads `sent_via` + `ways` of a forgot-password answer.
  void _readResetInfo(Map result, {String? typed}) {
    resetSentVia = result['sent_via']?.toString();
    if (result['ways'] is List) {
      resetWays = (result['ways'] as List)
          .whereType<Map>()
          .map((m) => ResetWay(m['way'].toString(), m['masked']?.toString()))
          .toList();
    }
    if (resetSentVia == 'email' && typed != null && !typed.contains('@')) {
      resetEmailMasked = result['email_masked']?.toString();
    }
    notifyListeners();
  }

  // ── Logout ────────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    ViewAsState.instance.stop(); // never carry view-as into the next session
    AppModeController.instance.reset(); // Organization/Individual mode belongs to the user who chose it
    // Unregister the push token BEFORE the tokens are wiped — afterwards the DELETE had no auth header,
    // failed with 401, and this device kept receiving the previous user's pushes.
    try {
      await NotificationService.instance.unregisterFromBackend(_api);
    } catch (_) {}
    await _api.signOutServer(); // revoke the refresh family (S15); never blocks on a network failure
    await _storage.clearAll(); // wipes tokens + user JSON
    try {                       // unsent exam answers kept for crash recovery never outlive the session (shared devices)
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith('exam.pending.')).toList()) {
        await p.remove(k);
      }
    } catch (_) {}
    accountSetup = null;
    _resetMfa();
    TeacherOnboardingToken.clear();
    _currentUser = null;
    notifyListeners();
  }

  // ── Dropdown helpers ──────────────────────────────────────────────────────────

  void onChangeTeachingType(int i, ExpansibleController controller) {
    controller.collapse();
    selectedTeachingType = teachingTypes[i];
    notifyListeners();
  }

  void onChangePaymentMethod(int i, ExpansibleController controller) {
    controller.collapse();
    selectedPaymentType = paymentTypes[i];
    notifyListeners();
  }

  void onChangeRole(int i, ExpansibleController controller) {
    controller.collapse();
    selectedRole = roles[i];
    notifyListeners();
  }

  void onChangeSpecialization(int i, ExpansibleController controller) {
    controller.collapse();
    selectedSpecialization = specializations[i];
    notifyListeners();
  }

  Map<String, dynamic> getSpecializationById(String id) =>
      specializations.firstWhere((e) => e['id'] == id);

  // ── Internal helpers ──────────────────────────────────────────────────────────

  Future<void> _persistTokens(Map<dynamic, dynamic> data) async {
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    if (access != null && refresh != null) {
      await _api.saveTokens(access: access, refresh: refresh); // secure storage (lib/core/token_storage.dart)
    }
  }
}