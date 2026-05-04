import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'dart:convert';
import '../../auth/login_screen.dart';
import '../../student/models.dart';

enum AppLanguage { arabic, english }

enum PasswordStep { form, otp }

extension AppLanguageX on AppLanguage {
  String get label => this == AppLanguage.arabic ? 'العربية' : 'English';
}

class ProfileProvider extends BaseProvider {
  ProfileProvider({ApiClient? api}) : _api = api ?? ApiClient();

  void initData(UserModel? u) {
    isLoading = true;
    notifyListeners();
    id = u?.id ?? 0;
    name = u?.name ?? '';
    email = u?.gmail ?? '';
    dob = u?.dob ?? '';
    country = u?.country ?? '';
    imageUrl = u?.imageUrl ?? '';
    role = u?.role ?? '';
    phone = u?.phone ?? '';
    isLoading = false;
    notifyListeners();
  }

  // ── Fields populated after login / GET /me ─────────────────────────────
  XFile? imageFile;
  Uint8List? imageByte;
  int id = 0;
  String name = '';
  String email = ''; // gmail – never editable by user
  String phone = '';
  String dob = ''; // stored as 'yyyy-MM-dd' string for UI
  String bio = '';
  String country = '';
  String imageUrl = '';
  String role = '';
  bool _notificationsEnabled = true;

  bool get notificationsEnabled => _notificationsEnabled;

  bool isLoading = false;

  void toggleNotifications(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  bool _darkMode = false;

  bool get darkMode => _darkMode;

  void toggleDarkMode(bool value) {
    _darkMode = value;
    notifyListeners();
  }

  void setLanguage(AppLanguage lang) {
    _language = lang;
    notifyListeners();
  }

  Future<void> changeImage(XFile file) async {
    imageFile = file;
    imageByte = await file.readAsBytes();
    notifyListeners();
  }

  AppLanguage _language = AppLanguage.arabic;

  AppLanguage get language => _language;

  // ── Initialise from the decoded token/me response ───────────────────────
  void setFromJson(Map<String, dynamic> json) {
    id = json['id'] ?? 0;
    name = json['name'] ?? '';
    email = json['gmail'] ?? '';
    phone = json['phone'] ?? '';
    dob = json['dob'] ?? ''; // ISO date string or ''
    bio = json['bio'] ?? '';
    country = json['country'] ?? '';
    imageUrl = json['image_url'] ?? '';
    role = json['role'] ?? '';
    notifyListeners();
  }

  PasswordStep _passwordStep = PasswordStep.form;

  PasswordStep get passwordStep => _passwordStep;

  void resetPasswordStep() {
    _passwordStep = PasswordStep.form;
    notifyListeners();
  }

  Future<bool> resendOtp(String email) async {
    final result = await run(
      () => _api.post('/api/v1/auth/resend-otp2',
          body: {'gmail': email}, auth: false),
    );
    return result != null;
  }

  // ── Update account (name, phone, dob, bio, country) ────────────────────
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? dob,
    String? bio,
    String? country,
  }) async {
    _setLoading(true);
    try {
      final body = <String, dynamic>{};
      if (name != null && name.isNotEmpty) body['name'] = name;
      if (phone != null && phone.isNotEmpty) body['phone'] = phone;
      if (dob != null && dob.isNotEmpty) body['dob'] = dob;
      if (bio != null && bio.isNotEmpty) body['bio'] = bio;
      if (country != null && country.isNotEmpty) body['country'] = country;

      final r = await run(
        () => ApiClient().put(
          '/api/v1/auth/me',
          body: jsonEncode(body),
        ),
      );

      if (r.statusCode == 200) {
        setFromJson(jsonDecode(r.body));
      } else {
        throw Exception('فشل تحديث البيانات (${r.statusCode})');
      }
    } finally {
      _setLoading(false);
    }
  }

  // ── Change password ─────────────────────────────────────────────────────
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    _setLoading(true);
    try {
      final r = await run(
        () => ApiClient().put(
          '/api/v1/auth/change-password',
          body:{
            'gmail': email,
            'old_password': oldPassword,
            'new_password': newPassword,
          }),
      );
      print(r.body);

      if (r.statusCode != 200) {
        final msg = jsonDecode(r.body)['detail'] ?? 'فشل تغيير كلمة المرور';
        throw Exception(msg);
      }
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool v) {
    isLoading = v;
    notifyListeners();
  }

  final ApiClient _api;

  // ── Favourites ────────────────────────────────────────────────────────────────
  List<CourseModel> _favourites = [];

  List<CourseModel> get favourites => List.unmodifiable(_favourites);

  Future<void> logout(context) async {
    await _api.clearTokens();
    _favourites = [];
    notifyListeners();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}
