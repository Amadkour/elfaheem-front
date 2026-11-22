// lib/core/edu/edu_countries.dart — the countries a person can pick before and after sign-in (D-1311):
//   GET /edu/countries → [{code, name_ar, name_en, geo_labels, minor_age, phone_code, contact_whatsapp}]
// `minor_age` is the age under which a parent's consent is needed, `contact_whatsapp` the number (or link) a
// `contact_only` stage (university) is sent to. The country of a person is the profile's `country_code`, else the
// first row of this list (its sort order).
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart' show eduName;

String _s(dynamic v) => v is String ? v : (v?.toString() ?? '');

class EduCountry {
  const EduCountry({
    required this.code,
    this.nameAr = '',
    this.nameEn = '',
    this.minorAge = 18,
    this.phoneCode = '',
    this.contactWhatsapp = '',
  });

  factory EduCountry.fromJson(Map<String, dynamic> j) {
    final age = j['minor_age'];
    return EduCountry(
      code: _s(j['code']).toUpperCase(),
      nameAr: _s(j['name_ar']),
      nameEn: _s(j['name_en']),
      minorAge: age is num ? age.toInt() : (int.tryParse(_s(age)) ?? 18),
      phoneCode: _s(j['phone_code']),
      contactWhatsapp: _s(j['contact_whatsapp']).trim(),
    );
  }

  final String code, nameAr, nameEn, phoneCode, contactWhatsapp;
  final int minorAge;
  String get name => eduEmptyOr(eduName(nameAr, nameEn), code);

  /// The https link a `contact_only` stage opens: a stored link as it is, a number as wa.me (digits only), else null.
  String? get whatsappLink {
    final v = contactWhatsapp;
    if (v.isEmpty) return null;
    if (v.startsWith('https://')) return v;
    final digits = v.replaceAll(RegExp(r'\D'), '');
    return digits.length < 6 ? null : 'https://wa.me/$digits';
  }
}

String eduEmptyOr(String v, String fallback) => v.isEmpty ? fallback : v;

/// Parse the answer of `GET /edu/countries` (anything else gives an empty list).
List<EduCountry> parseEduCountries(dynamic body) => body is List
    ? [for (final e in body) if (e is Map) EduCountry.fromJson(Map<String, dynamic>.from(e))]
    : const [];

/// The person's country: [profileCode] when the list has it, else the first of [countries], else null.
EduCountry? pickEduCountry(List<EduCountry> countries, String? profileCode) {
  if (countries.isEmpty) return null;
  final c = (profileCode ?? '').toUpperCase();
  for (final e in countries) {
    if (e.code == c) return e;
  }
  return countries.first;
}

class EduCountries {
  static List<EduCountry>? _mem;

  /// One load per run; an empty list when the call fails (the caller then hides the country picker).
  static Future<List<EduCountry>> load({bool force = false}) async {
    if (!force && _mem != null) return _mem!;
    try {
      final r = parseEduCountries(await ApiClient().get('/api/v1/edu/countries', auth: false));
      if (r.isNotEmpty) _mem = r;
      return r;
    } catch (_) {
      return _mem ?? const [];
    }
  }
}
