// The public landing endpoints behind the guest search. Every call fails soft: null / empty, never an exception.
library;

import '../../config/app_config.dart';
import '../../core/api_client.dart';

class LandingLevel {
  const LandingLevel({required this.id, required this.nameAr, required this.nameEn, this.courses = 0});
  final int id;
  final String nameAr;
  final String nameEn;
  final int courses;
  String get name => AppConfig.lang == 'ar' ? (nameAr.isNotEmpty ? nameAr : nameEn) : (nameEn.isNotEmpty ? nameEn : nameAr);
}

class LandingSubject extends LandingLevel {
  const LandingSubject({required super.id, required super.nameAr, required super.nameEn, super.courses, this.levels = const []});
  final List<LandingLevel> levels;
}

class LandingCount {
  const LandingCount({required this.courses, required this.teachers});
  final int courses;
  final int teachers;
}

typedef LandingOptionsLoader = Future<List<LandingSubject>> Function();
typedef LandingMatchLoader = Future<LandingCount?> Function({int? subject, int? level, required String mode});

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

LandingLevel _level(Map m) => LandingLevel(id: _i(m['id']), nameAr: '${m['name_ar'] ?? ''}', nameEn: '${m['name_en'] ?? ''}', courses: _i(m['courses']));

List<LandingSubject> parseLandingOptions(Object? body) {
  final list = body is Map ? body['subjects'] : null;
  if (list is! List) return const [];
  return [
    for (final s in list.whereType<Map>())
      LandingSubject(
        id: _i(s['id']),
        nameAr: '${s['name_ar'] ?? ''}',
        nameEn: '${s['name_en'] ?? ''}',
        courses: _i(s['courses']),
        levels: [for (final l in (s['levels'] is List ? s['levels'] as List : const []).whereType<Map>()) _level(l)],
      ),
  ];
}

LandingCount? parseLandingCount(Object? body) =>
    body is Map && body['courses'] != null ? LandingCount(courses: _i(body['courses']), teachers: _i(body['teachers'])) : null;

class LandingApi {
  const LandingApi._();

  static Future<List<LandingSubject>> options() async {
    try {
      return parseLandingOptions(await ApiClient.instance.get('/api/v1/public/landing/options', auth: false));
    } catch (_) {
      return const [];
    }
  }

  static Future<LandingCount?> match({int? subject, int? level, required String mode}) async {
    try {
      return parseLandingCount(await ApiClient.instance.get('/api/v1/public/landing/match',
          queryParams: {if (subject != null) 'subject': subject, if (level != null) 'level': level, 'mode': mode}, auth: false));
    } catch (_) {
      return null;
    }
  }
}
