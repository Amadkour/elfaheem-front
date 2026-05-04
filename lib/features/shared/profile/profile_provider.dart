import 'dart:developer';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:http/http.dart' hide MultipartFile;
import '../../../config/storage_service.dart';
import '../../auth/login_screen.dart';
import '../../student/models.dart';
import 'package:path/path.dart' as p;

enum PasswordStep { form, otp }

class ProfileProvider extends BaseProvider {
  final StorageService _storage;

  ProfileProvider({required StorageService storage, ApiClient? api})
      : _api = api ?? ApiClient(),
        _storage = storage {
    _loadCachedMode();
  }

  void _loadCachedMode() {
    bool? saved = _storage.loadMode;
    if (saved != null) {
      darkMode = saved;
    }
  }
  Future<void> changeMode(bool isDark) async {
    await _storage.saveMode(isDark);
    darkMode=isDark;
    notifyListeners();
  }

  // ProfileProvider({ApiClient? api}) : _api = api ?? ApiClient();

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

  Future<void> changeImage(XFile file) async {
    imageFile = file;
    imageByte = await file.readAsBytes();
    notifyListeners();
  }

  PasswordStep _passwordStep = PasswordStep.form;

  PasswordStep get passwordStep => _passwordStep;

  void resetPasswordStep() {
    _passwordStep = PasswordStep.form;
    notifyListeners();
  }

  Future<UserModel?> uploadImage() async {
    try {
      final ext =
          p.extension(imageFile!.path).replaceFirst('.', '').toLowerCase();
      final mimeType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      final bytes = await imageFile!.readAsBytes();
      final filename = p.basename(imageFile!.path).isNotEmpty
          ? p.basename(imageFile!.path)
          : 'image.${ext.isEmpty ? 'jpg' : ext}';

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ),
      });
      final response =
          await _api.dio.post('/api/v1/auth/me/image', data: formData);
      if (response.statusCode != 200) return null;
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      log('uploadImage ❌ ${e.response?.statusCode}: ${e.response?.data}');
      return null;
    } catch (e) {
      log('uploadImage ❌ unexpected: $e');
      return null;
    }
  }

  Future<bool> resendOtp(String email) async {
    final result = await run(
      () => _api.post('/api/v1/auth/resend-otp2',
          body: {'gmail': email}, auth: false),
    );
    return result != null;
  }

  // ── Update account (name, phone, dob, bio, country) ────────────────────
  Future<UserModel?> updateProfile({
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
          body: body,
        ),
      );

      if (r != null && r is Map) {
        _setLoading(false);
        return UserModel.fromJson(r as Map<String, dynamic>);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  // ── Change password ─────────────────────────────────────────────────────
  Future<String?> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    _setLoading(true);
    try {
      final r = await run(
        () => ApiClient().put('/api/v1/auth/change-password', body: {
          'gmail': email,
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      );
      if (r != null && r is Map) {
        _setLoading(false);
        return r['message'] as String;
      }
    } catch (e) {
      _setLoading(false);
      return null;
    }
    return null;
  }

  void _setLoading(bool v) {
    isLoading = v;
    notifyListeners();
  }

  final ApiClient _api;

  // ── Favourites ────────────────────────────────────────────────────────────────
  List<CourseModel> _favourites = [];

  bool darkMode = false;

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
