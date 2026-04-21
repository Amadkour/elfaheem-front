/// ─────────────────────────────────────────────────────────────────────────────
/// auth_provider.dart
/// Manages the full authentication lifecycle.
///
/// Session persistence:
///   • After login / OTP verification the user JSON is saved to SharedPreferences
///     via StorageService.saveUser().
///   • On cold start, AuthProvider._loadCachedUser() reads it back so
///     _currentUser and role getters are immediately available — no extra
///     network call needed before showing the correct home screen.
///   • On logout, StorageService.clearAll() wipes tokens + user.
///
/// Registration flow:
///   1. register()            → POST /api/v1/auth/register
///   2. verifyOtp()           → POST /api/v1/auth/verify-otp  (saves user)
///   3. completeTeacher()     → POST /api/v1/auth/teacher-profile (teachers)
///
/// Login flow:
///   login()                  → POST /api/v1/auth/login  (saves user)
///
/// Token management:
///   refreshToken()           → POST /api/v1/auth/refresh
///   getMe()                  → GET  /api/v1/auth/me     (updates saved user)
///   logout()                 → clears storage
///
/// Password flows:
///   changePassword()         → PUT  /api/v1/auth/change-password
///   forgotPassword()         → POST /api/v1/auth/forgot-password
///   resetPassword()          → POST /api/v1/auth/reset-password
///   resendOtp()              → POST /api/v1/auth/resend-otp
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../config/storage_service.dart';
import '../../core/api_client.dart';
import '../../core/base_provider.dart';
import '../category/categories_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class UserModel {
  final int id;
  final String name;
  final String gmail;
  final String role;
  final String? phone;
  final String? country;
  final String? dob;
  final String? imageUrl;
  final String? registrationStep;

  const UserModel({
    required this.id,
    required this.name,
    required this.gmail,
    required this.role,
    this.phone,
    this.country,
    this.dob,
    this.imageUrl,
    this.registrationStep,
  });

  bool get isTeacher => role == 'teacher';

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: j['id'] as int,
        name: j['name'] as String,
        gmail: j['gmail'] as String,
        role: j['role'] as String,
        phone: j['phone'] as String?,
        country: j['country'] as String?,
        dob: j['dob'] as String?,
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
    _loadCachedUser();
  }

  Future<void> loadSpecialization(BuildContext context) async {
    specializations =
        await context.read<CategoriesProvider>().getSpecialization();
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

  UserModel? get currentUser => _currentUser;

  bool get isStudent => _currentUser?.role == 'student';

  bool get isTeacher => _currentUser?.role == 'teacher';

  bool get isAdmin => _currentUser?.role == 'admin';

  bool get isAuthenticated => _storage.isAuthenticated();

  // ── Cold-start restore ────────────────────────────────────────────────────────

  /// Reads the user JSON saved during login / OTP verification.
  /// Called synchronously in the constructor so the user is available
  /// before the widget tree is built.
  void _loadCachedUser() {
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

    final result = await run(() => _api.post(
          '/api/v1/auth/register',
          body: {
            'name': name,
            'gmail': gmail,
            'password': password,
            'role': selectedRole!['text'],
            if (phone != null) 'phone': phone,
            if (country != null) 'country': country,
            if (dob != null) 'dob': dob,
          },
          auth: false,
        ));

    isLoadingRegistration = false;
    notifyListeners();
    return result != null;
  }

  // ── Step 2: Verify OTP ────────────────────────────────────────────────────────

  /// On success the server returns the same shape as login:
  ///   { registration_step, ... }
  /// We save the user here so teachers know they need step 3.
  Future<bool> verifyOtp({
    required String gmail,
    required String code,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/auth/verify-otp',
          body: {'gmail': gmail, 'code': code},
          auth: false,
        ));

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

  Future<bool> resendOtp(String gmail) async {
    final result = await run(() => _api.post(
          '/api/v1/auth/resend-otp',
          body: {'gmail': gmail},
          auth: false,
        ));
    return result != null;
  }

  // ── Step 3 (Teachers): Complete Profile ───────────────────────────────────────

  Future<bool> completeTeacherProfile({
    required int experienceYears,
    required String email,
    int? specializationId,
    String teachingType = 'both',
    String paymentType = 'free',
    String? about,
  }) async {
    isLoadingAdditionalRegistration = true;
    notifyListeners();

    final result = await run(() => _api.post(
          '/api/v1/auth/teacher-profile',
          body: {
            'experience_years': experienceYears,
            'teaching_type': teachingType,
            'payment_type': paymentType,
            'gmail': email,
            if (specializationId != null) 'specialization_id': specializationId,
            if (about != null) 'about': about,
          },
        ));

    isLoadingAdditionalRegistration = false;
    notifyListeners();
    return result != null;
  }

  // ── Login ─────────────────────────────────────────────────────────────────────

  /// Authenticates the user, saves tokens + user object to disk.
  Future<bool> login({
    required String gmail,
    required String password,
  }) async {
    isLoadingLogin = true;
    notifyListeners();

    final result = await run(() => _api.post(
          '/api/v1/auth/login',
          body: {'gmail': gmail, 'password': password},
          auth: false,
        ));

    if (result != null && result is Map) {
      // 1. Save tokens
      await _persistTokens(result);

      // 2. Build and cache the user model
      final userJson = result['user'] as Map<String, dynamic>;
      _currentUser = UserModel.fromJson(userJson);
      await _storage.saveUser(userJson); // ← persisted to SharedPreferences

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
    final result = await run(() => _api.post(
          '/api/v1/auth/refresh',
          queryParams: {'refresh_token': refreshToken},
          auth: false,
        ));

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
      _currentUser = UserModel.fromJson(result);
      await _storage.saveUser(result); // keep cache in sync
      notifyListeners();
    }
    return _currentUser;
  }

  // ── Change Password ───────────────────────────────────────────────────────────

  Future<bool> changePassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    final result = await run(() => _api.put(
          '/api/v1/auth/change-password',
          body: {
            'gmail': email,
            'old_password': oldPassword,
            'new_password': newPassword,
          },
        ));
    return result != null;
  }

  // ── Forgot Password ───────────────────────────────────────────────────────────

  Future<bool> forgotPassword(String gmail) async {
    final result = await run(() => _api.post(
          '/api/v1/auth/forgot-password',
          body: {'gmail': gmail},
          auth: false,
        ));
    return result != null;
  }

  // ── Reset Password ────────────────────────────────────────────────────────────

  Future<bool> resetPassword({
    required String gmail,
    required String code,
    required String newPassword,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/auth/reset-password',
          body: {
            'gmail': gmail,
            'code': code,
            'new_password': newPassword,
          },
          auth: false,
        ));
    return result != null;
  }

  // ── Logout ────────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _storage.clearAll(); // wipes tokens + user JSON
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

  // ── Internal helpers ──────────────────────────────────────────────────────────

  Future<void> _persistTokens(Map<dynamic, dynamic> data) async {
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    if (access != null && refresh != null) {
      await _storage.saveTokens(
        accessToken: access,
        refreshToken: refresh,
      );
      await _api.saveTokens(
        accessToken: access,
        refreshToken: refresh,
      );
    }
  }
}
