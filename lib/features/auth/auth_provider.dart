library;

import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../config/storage_service.dart';
import '../../core/api_client.dart';
import '../../core/base_provider.dart';
import '../../utils/helpers.dart';
import '../category/categories_provider.dart';
import '../shared/notification/notification_service.dart';

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

// ── Provider ──────────────────────────────────────────────────────────────────

class AuthProvider extends BaseProvider {
  final ApiClient _api;
  final StorageService _storage;

  AuthProvider({ApiClient? api, required StorageService storage})
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
  UserModel? get currentUser => _currentUser;

  bool get isStudent => currentUser?.role == 'student';

  bool get selectedRoleIsStudent => selectedRole!['text'] == 'student';

  bool get isTeacher => currentUser?.role == 'teacher';

  bool get isAdmin => currentUser?.role == 'admin';

  bool get isSuper => currentUser?.role == 'super-admin';

  bool get isAuthenticated => _storage.isAuthenticated();

  String get homeRoute => switch (currentUser?.role ?? 'student') {
    'admin' => '/admin_dashboard',
    'super-admin' => '/admin_dashboard',
    'developer' => '/admin_dashboard',
    'teacher' => '/teacher_dashboard',
    _ => '/dashboard',
  };

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
        },
        auth: false,
      ),
    );

    isLoadingRegistration = false;
    notifyListeners();
    return result != null;
  }

  // ── Step 2: Verify OTP ────────────────────────────────────────────────────────

  /// On success the server returns the same shape as login:
  ///   { registration_step, ... }
  /// We save the user here so teachers know they need step 3.
  Future<bool> verifyOtp({required String gmail, required String code}) async {
    final result = await run(
      () => _api.post(
        '/api/v1/auth/verify-otp',
        body: {'gmail': gmail, 'code': code},
        auth: false,
      ),
    );

    if (result != null && result is Map) {
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

  // ── Resend OTP ────────────────────────────────────────────────────────────────

  Future<bool> resendOtp(String gmail, {bool reset = false}) async {
    final result = await run(
      () => _api.post(
        reset ? '/api/v1/auth/forgot-password' : '/api/v1/auth/resend-otp',
        body: {'gmail': gmail},
        auth: false,
      ),
    );
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
      ),
    );

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
  Future<bool> login({required String gmail, required String password}) async {
    isLoadingLogin = true;
    notifyListeners();
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
        // Login only returns 403 for inactive / unverified accounts.
        if (e.statusCode == 403) {
          needsVerification = true;
          final b = e.body;
          if (b is Map && b['detail'] is Map) {
            pendingRole = b['detail']['role']?.toString();
          }
        }
        rethrow;
      }
    });
    if (result != null && result is Map) {
      // 1. Save tokens
      await _persistTokens(result);

      // 2. Build and cache the user model
      final userJson = result['user'] as Map<String, dynamic>;
      _currentUser = UserModel.fromJson(userJson);
      await _storage.saveUser(userJson); // ← persisted to SharedPreferences
      await NotificationService.instance.registerWithBackend(_api);
      isLoadingLogin = false;
      notifyListeners();
      return true;
    }

    isLoadingLogin = false;
    notifyListeners();
    return false;
  }
  // ── Refresh Token ─────────────────────────────────────────────────────────────

  Future<bool> refreshToken(String refreshToken) async {
    final result = await run(
      () => _api.post(
        '/api/v1/auth/refresh',
        queryParams: {'refresh_token': refreshToken},
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
    await _storage.saveUser(user.toJson());
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

  Future<bool> forgotPassword(String gmail) async {
    isLoadingForget = true;
    notifyListeners();
    final result = await run(
      () => _api.post(
        '/api/v1/auth/forgot-password',
        body: {'gmail': gmail},
        auth: false,
      ),
    );
    isLoadingForget = false;
    notifyListeners();
    return result != null;
  }

  // ── Reset Password ────────────────────────────────────────────────────────────

  Future<bool> resetPassword({
    required String gmail,
    required String code,
    required String newPassword,
  }) async {
    final result = await run(
      () => _api.post(
        '/api/v1/auth/reset-password',
        body: {'gmail': gmail, 'code': code, 'new_password': newPassword},
        auth: false,
      ),
    );
    return result != null;
  }

  // ── Logout ────────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _storage.clearAll(); // wipes tokens + user JSON
    _currentUser = null;
    await NotificationService.instance.unregisterFromBackend(_api);
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
      await _storage.saveTokens(accessToken: access, refreshToken: refresh);
      await _api.saveTokens(access: access, refresh: refresh);
    }
  }
}
