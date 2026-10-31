// components/certificate_manager_provider.dart
//
// Scoped provider for the certificate manager sheet: loads enrolled
// students + existing issuances, uploads/removes the template image, and
// issues certificates to one or all students.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:developer';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';

class EnrolledStudentInfo {
  final int id;
  final String name;
  final String email;
  final String? imageUrl;
  final double progressPercentage;

  const EnrolledStudentInfo({
    required this.id,
    required this.name,
    required this.email,
    this.imageUrl,
    this.progressPercentage = 0,
  });

  factory EnrolledStudentInfo.fromJson(Map<String, dynamic> j) => EnrolledStudentInfo(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        email: j['gmail'] as String? ?? '',
        imageUrl: j['image_url'] as String?,
        progressPercentage: (j['progress_percentage'] as num?)?.toDouble() ?? 0,
      );
}

class CertificateIssuanceInfo {
  final int studentId;
  /// The English image, or the Arabic one when the design issues Arabic only (the server's fallback).
  final String? certificateUrl;

  /// The Arabic image (null when the certificate has no Arabic version).
  final String? certificateUrlAr;
  final DateTime? emailSentAt;

  const CertificateIssuanceInfo({
    required this.studentId,
    this.certificateUrl,
    this.certificateUrlAr,
    this.emailSentAt,
  });

  factory CertificateIssuanceInfo.fromJson(Map<String, dynamic> j) => CertificateIssuanceInfo(
        studentId: j['student_id'] as int,
        certificateUrl: j['certificate_url'] as String?,
        certificateUrlAr: (j['certificate_url_ar'] as String?)?.isNotEmpty == true ? j['certificate_url_ar'] as String : null,
        emailSentAt: j['email_sent_at'] != null
            ? DateTime.tryParse(j['email_sent_at'] as String)
            : null,
      );
}

class CertificateManagerProvider extends BaseProvider {
  final ApiClient _api;

  CertificateManagerProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<EnrolledStudentInfo> students = [];
  Map<int, CertificateIssuanceInfo> issuancesByStudent = {};
  bool loadingStudents = false;
  int? issuingStudentId; // non-null while a single-send is in flight
  bool issuingAll = false;

  Future<void> load(int courseId, int certificateId) async {
    loadingStudents = true;
    notifyListeners();

    final studentsResult = await run(() => _api.get('/api/v1/courses/$courseId/students'));
    final issuancesResult = await run(() => _api.get('/api/v1/certificates/$certificateId/issuances'));

    students = (studentsResult is List)
        ? studentsResult
            .whereType<Map<String, dynamic>>()
            .map(EnrolledStudentInfo.fromJson)
            .toList()
        : [];

    issuancesByStudent = {
      if (issuancesResult is List)
        for (final row in issuancesResult.whereType<Map<String, dynamic>>())
          CertificateIssuanceInfo.fromJson(row).studentId: CertificateIssuanceInfo.fromJson(row),
    };

    loadingStudents = false;
    notifyListeners();
  }

  bool isIssued(int studentId) => issuancesByStudent.containsKey(studentId);

  Future<String?> uploadTemplate(int certificateId, XFile file) async {
    try {
      final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
      final mimeType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      final bytes = await file.readAsBytes();
      final filename = p.basename(file.path).isNotEmpty
          ? p.basename(file.path)
          : 'template.${ext.isEmpty ? 'jpg' : ext}';

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ),
      });
      final response = await _api.dio.post(
        '/api/v1/certificates/$certificateId/template',
        data: formData,
      );
      if (response.statusCode != 200) return null;
      final data = response.data as Map<String, dynamic>;
      return data['template_url'] as String?;
    } on DioException catch (e) {
      log('uploadTemplate ❌ ${e.response?.statusCode}: ${e.response?.data}');
      return null;
    } catch (e) {
      log('uploadTemplate ❌ unexpected: $e');
      return null;
    }
  }

  Future<bool> removeTemplate(int certificateId) async {
    try {
      final response = await _api.dio.delete('/api/v1/certificates/$certificateId/template');
      return response.statusCode == 204;
    } catch (e) {
      log('removeTemplate ❌ $e');
      return false;
    }
  }

  Future<bool> issueOne(int certificateId, int studentId) async {
    issuingStudentId = studentId;
    notifyListeners();
    final result = await run(
      () => _api.post('/api/v1/certificates/$certificateId/issue', body: {'student_id': studentId}),
    );
    issuingStudentId = null;
    if (result is Map<String, dynamic>) {
      issuancesByStudent[studentId] = CertificateIssuanceInfo.fromJson(result);
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<int> issueAll(int certificateId) async {
    issuingAll = true;
    notifyListeners();
    final result = await run(() => _api.post('/api/v1/certificates/$certificateId/issue-all'));
    int count = 0;
    if (result is List) {
      for (final row in result.whereType<Map<String, dynamic>>()) {
        final info = CertificateIssuanceInfo.fromJson(row);
        issuancesByStudent[info.studentId] = info;
        count++;
      }
    }
    issuingAll = false;
    notifyListeners();
    return count;
  }
}
