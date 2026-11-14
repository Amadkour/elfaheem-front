// courses/details/issued_certificate.dart
//
// A certificate the teacher issued to the CURRENT student for a course.
// GET /api/v1/courses/{id}/my-certificates

class IssuedCertificate {
  final int id;
  final int certificateId;
  final String title;
  final String? description;

  /// The English image — or, for a certificate issued in Arabic only, the Arabic one (the server's
  /// `certificate_url` falls back to Arabic; see [arabicOnly]).
  final String urlEn;

  /// The Arabic image when the certificate also exists in English (null for English-only and older certificates,
  /// and for Arabic-only ones, whose single image is [urlEn]) — so [hasArabic] means "both languages".
  final String? urlAr;

  /// Issued in Arabic only: [urlEn] holds the Arabic image.
  final bool arabicOnly;
  final DateTime? issuedAt;

  const IssuedCertificate({
    required this.id,
    required this.certificateId,
    required this.title,
    this.description,
    required this.urlEn,
    this.urlAr,
    this.arabicOnly = false,
    this.issuedAt,
  });

  factory IssuedCertificate.fromJson(Map<String, dynamic> j) {
    final ar = (j['certificate_url_ar'] as String?)?.isNotEmpty == true ? j['certificate_url_ar'] as String : null;
    final main = (j['certificate_url'] as String?)?.isNotEmpty == true ? j['certificate_url'] as String : null;
    // v2: only the languages the design issues exist; `certificate_url` falls back to the Arabic image
    final onlyAr = ar != null && (main == null || main == ar);
    return IssuedCertificate(
        id: j['id'] as int,
        certificateId: (j['certificate_id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        description: j['description'] as String?,
        urlEn: (onlyAr ? ar : main) ?? '',
        urlAr: onlyAr ? null : ar,
        arabicOnly: onlyAr,
        issuedAt: j['issued_at'] != null
            ? DateTime.tryParse(j['issued_at'].toString())
            : null,
      );
  }

  bool get hasArabic => urlAr != null;

  /// The version matching the app language (falls back to the one we have).
  String urlFor(bool arabic) => (arabic && urlAr != null) ? urlAr! : urlEn;
}
