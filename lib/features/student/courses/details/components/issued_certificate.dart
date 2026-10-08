// courses/details/issued_certificate.dart
//
// A certificate the teacher issued to the CURRENT student for a course.
// GET /api/v1/courses/{id}/my-certificates

class IssuedCertificate {
  final int id;
  final int certificateId;
  final String title;
  final String? description;

  /// English version (always present) and Arabic version (null for
  /// certificates issued before the bilingual update).
  final String urlEn;
  final String? urlAr;
  final DateTime? issuedAt;

  const IssuedCertificate({
    required this.id,
    required this.certificateId,
    required this.title,
    this.description,
    required this.urlEn,
    this.urlAr,
    this.issuedAt,
  });

  factory IssuedCertificate.fromJson(Map<String, dynamic> j) => IssuedCertificate(
        id: j['id'] as int,
        certificateId: (j['certificate_id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        description: j['description'] as String?,
        urlEn: j['certificate_url'] as String,
        urlAr: (j['certificate_url_ar'] as String?)?.isNotEmpty == true
            ? j['certificate_url_ar'] as String
            : null,
        issuedAt: j['issued_at'] != null
            ? DateTime.tryParse(j['issued_at'].toString())
            : null,
      );

  bool get hasArabic => urlAr != null;

  /// The version matching the app language (falls back to the one we have).
  String urlFor(bool arabic) => (arabic && urlAr != null) ? urlAr! : urlEn;
}
