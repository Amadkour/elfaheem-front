// lib/features/teachers/teachers_api.dart — the Learning Hub v2 teacher and package calls (CONTRACT.md §1, §2;
// D-1620 .. D-1639). Every path is a literal `/api/v1/…` so test/contract/ checks it against the server's routes.
//
//   GET|PUT /api/v1/me/teacher-profile                    my profile (404 `no_profile` → TeacherProfile.empty)
//   POST    /api/v1/me/teacher-profile/documents          multipart `file` + `doc_type`
//   DELETE  /api/v1/me/teacher-profile/documents/{id}     while not approved
//   POST    /api/v1/me/teacher-profile/submit             → pending (400 `profile_incomplete`)
//   POST    /api/v1/auth/me/image                         the profile photo (the account picture, cropped first)
//   GET     /api/v1/teachers?…  /teachers/{id}  /me/teachers
//   GET     /api/v1/admin/teachers?status&subject&page    the review queue
//   GET     /api/v1/admin/teachers/{uid}/documents/{id}/url   a 60 s signed link
//   POST    /api/v1/admin/teachers/{uid}/approve | /reject {reason}
//   GET     /api/v1/packages?…  /packages/{id}  /me/packages
//   POST    /api/v1/packages · PUT /packages/{id} · POST /packages/{id}/duplicate · /status {status}
//   POST    /api/v1/packages/{id}/enroll | /leave · GET /packages/{id}/enrollments
//   GET     /api/v1/admin/packages/refunds-due · POST …/refunds-due/{payment_id}/done   (D-1640)
//
// Kill switches: `teacher_onboarding` (the teacher's flow and the admin queue), `teacher_discovery` (the student's
// list), `packages` (the package wizard and Join).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/teachers/teachers_models.dart';

const String kTeacherOnboardingFeature = 'teacher_onboarding';
const String kTeacherDiscoveryFeature = 'teacher_discovery';
const String kPackagesFeature = 'packages';

bool teacherOnboardingOff() => AppConfig.disableList.contains(kTeacherOnboardingFeature);
bool teacherDiscoveryOff() => AppConfig.disableList.contains(kTeacherDiscoveryFeature);
bool packagesOff() => AppConfig.disableList.contains(kPackagesFeature);

/// What to show for a failed teacher / package call (every code is in apiErrorText).
String teachersErrorText(Object e) {
  if (e is TimeoutException) return ApiMessages.timeout;
  return apiErrorText(ApiException.from(e));
}

/// The error code of a failed call, or null.
String? teachersErrorCode(Object e) => e is ApiException ? e.code : null;

class TeachersApi {
  TeachersApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  // ── my teacher profile ─────────────────────────────────────────────────────

  /// My profile; [TeacherProfile.empty] when I have none yet.
  Future<TeacherProfile> myProfile() async {
    try {
      return TeacherProfile.fromJson(await _api.get('/api/v1/me/teacher-profile'));
    } on ApiException catch (e) {
      if (e.code == 'no_profile' || e.statusCode == 404) return TeacherProfile.empty;
      rethrow;
    }
  }

  Future<TeacherProfile> saveProfile(TeacherProfileDraft d) async =>
      TeacherProfile.fromJson(await _api.put('/api/v1/me/teacher-profile', body: d.toJson()));

  Future<TeacherDoc> uploadDocument({required String docType, required String fileName, required Uint8List bytes}) async {
    final r = await _api.postMultipart('/api/v1/me/teacher-profile/documents',
        fields: {'doc_type': docType}, fileField: 'file', fileName: fileName, fileBytes: bytes);
    final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
    return TeacherDoc.fromJson({'file_name': fileName, 'doc_type': docType, 'size': bytes.length, ...m});
  }

  Future<void> deleteDocument(int id) => _api.delete('/api/v1/me/teacher-profile/documents/$id');

  Future<TeacherProfile> submit() async => TeacherProfile.fromJson(await _api.post('/api/v1/me/teacher-profile/submit'));

  /// The account picture (the profile shows it): returns its new URL, or null.
  Future<String?> uploadPhoto(Uint8List bytes, String fileName) async {
    final r = await _api.postForm('/api/v1/auth/me/image', fields: const {}, fileField: 'file', fileName: fileName, fileBytes: bytes);
    final url = r is Map ? '${r['image_url'] ?? ''}' : '';
    return url.isEmpty ? null : url;
  }

  // ── discovery ──────────────────────────────────────────────────────────────

  Future<TeacherListPage> teachers(TeacherFilters f, {int page = 1, int size = 20}) async =>
      TeacherListPage.fromJson(await _api.get('/api/v1/teachers', queryParams: f.toQuery(page: page, size: size)));

  Future<TeacherProfile> teacher(int userId) async => TeacherProfile.fromJson(await _api.get('/api/v1/teachers/$userId'));

  Future<List<MyTeacher>> myTeachers() async => myTeachersFromJson(await _api.get('/api/v1/me/teachers'));

  // ── admin queue ────────────────────────────────────────────────────────────

  Future<TeacherListPage> reviewQueue({String? status, String? subject, int page = 1}) async =>
      TeacherListPage.fromJson(await _api.get('/api/v1/admin/teachers', queryParams: {
        'status': ?status,
        'subject': ?subject,
        'page': page,
      }));

  Future<String> documentUrl(int userId, int docId) async {
    final r = await _api.get('/api/v1/admin/teachers/$userId/documents/$docId/url');
    return r is Map ? '${r['url'] ?? ''}' : '';
  }

  Future<void> approve(int userId) => _api.post('/api/v1/admin/teachers/$userId/approve');

  Future<void> reject(int userId, String reason) => _api.post('/api/v1/admin/teachers/$userId/reject', body: {'reason': reason.trim()});

  // ── packages ───────────────────────────────────────────────────────────────

  Future<List<TeacherPackage>> packages({String? subject, int? teacherId, String? delivery, int page = 1}) async =>
      packagesFromJson(await _api.get('/api/v1/packages', queryParams: {
        'subject': ?subject,
        'teacher_id': ?teacherId,
        'delivery': ?delivery,
        'page': page,
      }));

  Future<TeacherPackage> package(int id) async => TeacherPackage.fromJson(await _api.get('/api/v1/packages/$id'));

  Future<List<TeacherPackage>> myPackages() async => packagesFromJson(await _api.get('/api/v1/me/packages'));

  Future<TeacherPackage> createPackage(PackageDraft d) async => TeacherPackage.fromJson(await _api.post('/api/v1/packages', body: d.toJson()));

  Future<TeacherPackage> updatePackage(int id, PackageDraft d) async =>
      TeacherPackage.fromJson(await _api.put('/api/v1/packages/$id', body: d.toJson()));

  Future<TeacherPackage> duplicatePackage(int id) async => TeacherPackage.fromJson(await _api.post('/api/v1/packages/$id/duplicate'));

  Future<TeacherPackage> setPackageStatus(int id, String status) async =>
      TeacherPackage.fromJson(await _api.post('/api/v1/packages/$id/status', body: {'status': status}));

  /// [couponCode] (Games v3, CONTRACT §7): one coupon off the package price; a waiting-list seat keeps it for later.
  Future<PackageEnrollResult> enroll(int id, {String? couponCode}) async => PackageEnrollResult.fromJson(
      await _api.post('/api/v1/packages/$id/enroll', body: couponCode == null ? null : {'coupon_code': couponCode}));

  Future<void> leave(int id) => _api.post('/api/v1/packages/$id/leave');

  Future<List<PackageRosterRow>> roster(int id) async => packageRosterFromJson(await _api.get('/api/v1/packages/$id/enrollments'));

  // ── refunds due (admin; D-1640) ────────────────────────────────────────────

  Future<List<PackageRefundDue>> refundsDue() async => packageRefundsFromJson(await _api.get('/api/v1/admin/packages/refunds-due'));

  /// Refunded at the provider (audited). 409 `not_due` when another admin already did it.
  Future<void> refundDone(int paymentId) => _api.post('/api/v1/admin/packages/refunds-due/$paymentId/done');
}
