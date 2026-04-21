/// ─────────────────────────────────────────────────────────────────────────────
/// profile_provider.dart
/// Manages the Profile screen state:
///   - User info (read from AuthProvider / API)
///   - Settings: notifications toggle, dark mode toggle, language
///   - Edit account: name, phone, dob
///   - Change password flow (includes OTP step)
///   - Favourite courses list
///
/// API endpoints used:
///   GET  /api/v1/auth/me              — load profile
///   PUT  /api/v1/auth/change-password — change password
///   POST /api/v1/auth/forgot-password — send OTP for password reset
///   POST /api/v1/auth/resend-otp      — resend OTP
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../models.dart';

// ── Language ──────────────────────────────────────────────────────────────────

enum AppLanguage { arabic, english }

extension AppLanguageX on AppLanguage {
  String get label => this == AppLanguage.arabic ? 'العربية' : 'English';
}

// ── Password Step ─────────────────────────────────────────────────────────────

enum PasswordStep { form, otp }

// ── ProfileProvider ───────────────────────────────────────────────────────────

class ProfileProvider extends BaseProvider {
  final ApiClient _api;

  ProfileProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── User data ─────────────────────────────────────────────────────────────────
  String  _name    = 'أحمد مدكور';
  String  _email   = 'ahmedmadkour66@gmail.com';
  String  _phone   = '+9668203093323';
  String  _dob     = '٢٢/٩/١٩٩١';
  String? _avatarUrl;

  String  get name       => _name;
  String  get email      => _email;
  String  get phone      => _phone;
  String  get dob        => _dob;
  String? get avatarUrl  => _avatarUrl;

  // ── Settings ──────────────────────────────────────────────────────────────────
  bool        _notificationsEnabled = true;
  bool        _darkMode             = false;
  AppLanguage _language             = AppLanguage.arabic;

  bool        get notificationsEnabled => _notificationsEnabled;
  bool        get darkMode             => _darkMode;
  AppLanguage get language             => _language;

  // ── Favourites ────────────────────────────────────────────────────────────────
  List<CourseModel> _favourites = [];
  List<CourseModel> get favourites => List.unmodifiable(_favourites);

  // ── Change-password step ──────────────────────────────────────────────────────
  PasswordStep _passwordStep = PasswordStep.form;
  PasswordStep get passwordStep => _passwordStep;

  // ── Fetch me ──────────────────────────────────────────────────────────────────

  Future<void> fetchProfile() async {
    final result = await run(() => _api.get('/api/v1/auth/me'));
    if (result is Map<String, dynamic>) {
      _name  = result['name']  as String? ?? _name;
      _email = result['gmail'] as String? ?? _email;
      _phone = result['phone'] as String? ?? _phone;
      notifyListeners();
    }
  }

  // ── Edit account ──────────────────────────────────────────────────────────────

  /// Updates local state only; persist to backend as needed.
  Future<bool> updateProfile({
    required String name,
    required String phone,
    required String dob,
  }) async {
    // TODO: add PUT /api/v1/auth/profile when available
    _name  = name;
    _phone = phone;
    _dob   = dob;
    notifyListeners();
    return true;
  }

  // ── Change password ───────────────────────────────────────────────────────────

  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final result = await run(() => _api.put(
          '/api/v1/auth/change-password',
          body: {'old_password': oldPassword, 'new_password': newPassword},
        ));
    if (result != null) {
      _passwordStep = PasswordStep.otp;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> resendOtp() async {
    final result = await run(
      () => _api.post('/api/v1/auth/resend-otp2', body: {'gmail': _email}, auth: false),
    );
    return result != null;
  }

  void resetPasswordStep() {
    _passwordStep = PasswordStep.form;
    notifyListeners();
  }

  // ── Settings ──────────────────────────────────────────────────────────────────

  void toggleNotifications(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  void toggleDarkMode(bool value) {
    _darkMode = value;
    notifyListeners();
  }

  void setLanguage(AppLanguage lang) {
    _language = lang;
    notifyListeners();
  }

  // ── Favourites ────────────────────────────────────────────────────────────────

  void addFavourite(CourseModel course) {
    if (!_favourites.any((c) => c.id == course.id)) {
      _favourites = [..._favourites, course];
      notifyListeners();
    }
  }

  void removeFavourite(String courseId) {
    _favourites = _favourites.where((c) => c.id != courseId).toList();
    notifyListeners();
  }

  bool isFavourite(String courseId) =>
      _favourites.any((c) => c.id == courseId);

  // ── Logout ────────────────────────────────────────────────────────────────────

  Future<void> logout(context) async {
    await _api.clearTokens();
    _favourites = [];
    notifyListeners();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }
}
