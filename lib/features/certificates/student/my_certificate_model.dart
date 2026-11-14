// features/certificates/student/my_certificate_model.dart
//
// One certificate of one of the student's courses.
// GET /api/v1/my-certificates

enum MyCertState { issued, pending, readySoon, rejected, available }

MyCertState _stateFrom(String? s) => switch (s) {
      'issued' => MyCertState.issued,
      'pending' => MyCertState.pending,
      'ready_soon' => MyCertState.readySoon,
      'rejected' => MyCertState.rejected,
      _ => MyCertState.available,
    };

class MyCertificate {
  final int certificateId;
  final int? issuanceId;
  final int courseId;
  final String? courseNameAr;
  final String? courseNameEn;
  final String? courseImageUrl;
  final String? teacherName;
  final String title;
  final String? description;
  final double progress;
  final MyCertState state;
  final bool canRequest;
  /// The English image — or, for a certificate issued in Arabic only, the Arabic one (the server's
  /// `certificate_url` falls back to Arabic; see [arabicOnly]).
  final String? urlEn;

  /// The Arabic image when the certificate also exists in English (null for English-only and older certificates,
  /// and for Arabic-only ones, whose single image is [urlEn]).
  final String? urlAr;

  /// Issued in Arabic only: [urlEn] holds the Arabic image.
  final bool arabicOnly;
  final DateTime? issuedAt;
  final int? requestId;
  final DateTime? requestedAt;
  final String? rejectionReason;

  const MyCertificate({
    required this.certificateId,
    this.issuanceId,
    required this.courseId,
    this.courseNameAr,
    this.courseNameEn,
    this.courseImageUrl,
    this.teacherName,
    required this.title,
    this.description,
    this.progress = 0,
    required this.state,
    this.canRequest = false,
    this.urlEn,
    this.urlAr,
    this.arabicOnly = false,
    this.issuedAt,
    this.requestId,
    this.requestedAt,
    this.rejectionReason,
  });

  factory MyCertificate.fromJson(Map<String, dynamic> j) {
    final ar = (j['certificate_url_ar'] as String?)?.isNotEmpty == true ? j['certificate_url_ar'] as String : null;
    final main = (j['certificate_url'] as String?)?.isNotEmpty == true ? j['certificate_url'] as String : null;
    // v2: only the languages the design issues exist; `certificate_url` falls back to the Arabic image
    final onlyAr = ar != null && (main == null || main == ar);
    return MyCertificate(
        certificateId: (j['certificate_id'] as num).toInt(),
        issuanceId: (j['issuance_id'] as num?)?.toInt(),
        courseId: (j['course_id'] as num).toInt(),
        courseNameAr: j['course_name_ar'] as String?,
        courseNameEn: j['course_name_en'] as String?,
        courseImageUrl: j['course_image_url'] as String?,
        teacherName: j['teacher_name'] as String?,
        title: (j['title'] as String?) ?? '',
        description: j['description'] as String?,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        state: _stateFrom(j['state'] as String?),
        canRequest: j['can_request'] as bool? ?? false,
        urlEn: onlyAr ? ar : main,
        urlAr: onlyAr ? null : ar,
        arabicOnly: onlyAr,
        issuedAt: j['issued_at'] != null ? DateTime.tryParse(j['issued_at'].toString()) : null,
        requestId: (j['request_id'] as num?)?.toInt(),
        requestedAt:
            j['requested_at'] != null ? DateTime.tryParse(j['requested_at'].toString()) : null,
        rejectionReason: j['rejection_reason'] as String?,
      );
  }

  bool get isIssued => state == MyCertState.issued && urlEn != null;
  /// Both languages exist (the viewer / download offer a language choice).
  bool get hasArabic => urlAr != null;

  /// The language of the image [urlFor] gives for [arabic] ('ar' | 'en').
  String langFor(bool arabic) => arabicOnly || (arabic && urlAr != null) ? 'ar' : 'en';

  String courseName(bool arabic) =>
      (arabic ? (courseNameAr ?? courseNameEn) : (courseNameEn ?? courseNameAr)) ?? '';

  /// Image matching the app language (falls back to whichever exists).
  String? urlFor(bool arabic) => (arabic && urlAr != null) ? urlAr : urlEn;
}
