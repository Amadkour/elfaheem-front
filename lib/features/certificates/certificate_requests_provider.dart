// features/certificates/certificate_requests_provider.dart
//
// Teacher's inbox of certificate requests from students who have not finished
// the course yet. Approving issues + emails + notifies the student instantly.

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

class CertificateRequestItem {
  final int requestId;
  final int certificateId;
  final String certificateTitle;
  final int courseId;
  final String? courseNameAr;
  final String? courseNameEn;
  final int studentId;
  final String studentName;
  final String? studentImageUrl;
  final double progress;
  final String? note;
  final String status;
  final String? rejectionReason;
  final DateTime? createdAt;

  const CertificateRequestItem({
    required this.requestId,
    required this.certificateId,
    required this.certificateTitle,
    required this.courseId,
    this.courseNameAr,
    this.courseNameEn,
    required this.studentId,
    required this.studentName,
    this.studentImageUrl,
    this.progress = 0,
    this.note,
    required this.status,
    this.rejectionReason,
    this.createdAt,
  });

  factory CertificateRequestItem.fromJson(Map<String, dynamic> j) => CertificateRequestItem(
        requestId: (j['request_id'] as num).toInt(),
        certificateId: (j['certificate_id'] as num).toInt(),
        certificateTitle: (j['certificate_title'] as String?) ?? '',
        courseId: (j['course_id'] as num).toInt(),
        courseNameAr: j['course_name_ar'] as String?,
        courseNameEn: j['course_name_en'] as String?,
        studentId: (j['student_id'] as num).toInt(),
        studentName: (j['student_name'] as String?) ?? '',
        studentImageUrl: j['student_image_url'] as String?,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        note: j['note'] as String?,
        status: (j['status'] as String?) ?? 'pending',
        rejectionReason: j['rejection_reason'] as String?,
        createdAt: j['created_at'] != null ? DateTime.tryParse(j['created_at'].toString()) : null,
      );

  String courseName(bool arabic) =>
      (arabic ? (courseNameAr ?? courseNameEn) : (courseNameEn ?? courseNameAr)) ?? '';
}

class CertificateRequestsProvider extends BaseProvider {
  final ApiClient _api;

  CertificateRequestsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<CertificateRequestItem> items = [];
  bool loading = false;
  final Set<int> busyIds = {};

  /// Number of waiting requests (use for a badge).
  int get count => items.length;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    final r = await run(() => _api.get('/api/v1/teacher/certificate-requests?status=pending'));
    if (r is List) {
      items = r.whereType<Map<String, dynamic>>().map(CertificateRequestItem.fromJson).toList();
    }
    loading = false;
    notifyListeners();
  }

  Future<bool> approve(int requestId) => _act(
        requestId,
        () => _api.post('/api/v1/certificate-requests/$requestId/approve'),
      );

  Future<bool> reject(int requestId, {String? reason}) => _act(
        requestId,
        () => _api.post('/api/v1/certificate-requests/$requestId/reject',
            body: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()}),
      );

  Future<bool> _act(int requestId, Future<dynamic> Function() call) async {
    busyIds.add(requestId);
    notifyListeners();
    final r = await run(call);
    busyIds.remove(requestId);
    final ok = r != null;
    if (ok) items.removeWhere((e) => e.requestId == requestId);
    notifyListeners();
    return ok;
  }
}
