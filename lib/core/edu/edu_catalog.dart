// lib/core/edu/edu_catalog.dart — the education catalog (D-1303, docs/learning-hub/CONTRACT.md §2.2): a country's
// stages > grades (+ tracks) > subjects and its two-level areas (governorate > city), from the public routes
//   GET /edu/catalog?country=XX   (ETag "edu-XX-<version>", cache 300 s)
//   GET /edu/countries            (geo_labels: the country's names for the two area levels)
//   GET /edu/areas?country=XX&parent_id=
// One load per country per run, an in-memory cache plus a SharedPreferences copy that paints first and is
// revalidated with If-None-Match. Names follow AppConfig.lang. Every failure degrades to the cached copy or null.
library;

import 'dart:convert';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _s(dynamic v) => v is String ? v : (v?.toString() ?? '');
int _i(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0);
List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

/// Pick the Arabic or English name by the app language, falling back to the other one.
String eduName(String ar, String en) {
  final first = AppConfig.lang == 'ar' ? ar : en;
  return first.isNotEmpty ? first : (AppConfig.lang == 'ar' ? en : ar);
}

class EduTrack {
  const EduTrack({required this.key, required this.nameAr, required this.nameEn});
  factory EduTrack.fromJson(Map<String, dynamic> j) =>
      EduTrack(key: _s(j['key']), nameAr: _s(j['name_ar']), nameEn: _s(j['name_en']));
  final String key, nameAr, nameEn;
  String get name => eduName(nameAr, nameEn);
}

class EduGrade {
  const EduGrade({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.number = 0,
    this.tracks = const [],
    this.subjectIds = const [],
  });
  factory EduGrade.fromJson(Map<String, dynamic> j) => EduGrade(
        id: _i(j['id']),
        key: _s(j['key']),
        nameAr: _s(j['name_ar']),
        nameEn: _s(j['name_en']),
        number: _i(j['number']),
        tracks: [for (final t in _list(j['tracks'])) EduTrack.fromJson(t)],
        subjectIds: [for (final e in (j['subject_ids'] as List? ?? const [])) _i(e)],
      );
  final int id, number;
  final String key, nameAr, nameEn;
  final List<EduTrack> tracks;
  final List<int> subjectIds;
  String get name => eduName(nameAr, nameEn);
}

class EduStage {
  const EduStage({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.kind = 'school',
    this.hasGrades = true,
    this.contactOnly = false,
    this.grades = const [],
  });
  factory EduStage.fromJson(Map<String, dynamic> j) => EduStage(
        id: _i(j['id']),
        key: _s(j['key']),
        nameAr: _s(j['name_ar']),
        nameEn: _s(j['name_en']),
        kind: _s(j['kind']).isEmpty ? 'school' : _s(j['kind']),
        hasGrades: j['has_grades'] != false,
        contactOnly: j['contact_only'] == true,
        grades: [for (final g in _list(j['grades'])) EduGrade.fromJson(g)],
      );
  final int id;
  final String key, nameAr, nameEn, kind;
  final bool hasGrades, contactOnly;
  final List<EduGrade> grades;
  String get name => eduName(nameAr, nameEn);
}

class EduSubject {
  const EduSubject({required this.id, required this.key, required this.nameAr, required this.nameEn});
  factory EduSubject.fromJson(Map<String, dynamic> j) =>
      EduSubject(id: _i(j['id']), key: _s(j['key']), nameAr: _s(j['name_ar']), nameEn: _s(j['name_en']));
  final int id;
  final String key, nameAr, nameEn;
  String get name => eduName(nameAr, nameEn);
}

class EduArea {
  const EduArea({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.level = 1,
    this.hasChildren = false,
  });
  factory EduArea.fromJson(Map<String, dynamic> j) => EduArea(
        id: _i(j['id']),
        key: _s(j['key']),
        nameAr: _s(j['name_ar']),
        nameEn: _s(j['name_en']),
        level: _i(j['level']) == 0 ? 1 : _i(j['level']),
        hasChildren: j['has_children'] == true,
      );
  final int id, level;
  final String key, nameAr, nameEn;
  final bool hasChildren;
  String get name => eduName(nameAr, nameEn);
}

/// A country's names for the two area levels ("Governorate" / "City or district").
class EduGeoLabels {
  const EduGeoLabels({this.l1Ar = 'محافظة', this.l1En = 'Governorate', this.l2Ar = 'مدينة أو منطقة', this.l2En = 'City or district'});
  factory EduGeoLabels.fromJson(dynamic j) {
    if (j is! Map) return const EduGeoLabels();
    String g(String lvl, String lang, String def) {
      final m = j[lvl];
      final v = m is Map ? _s(m[lang]) : '';
      return v.isEmpty ? def : v;
    }

    const d = EduGeoLabels();
    return EduGeoLabels(
        l1Ar: g('1', 'ar', d.l1Ar), l1En: g('1', 'en', d.l1En), l2Ar: g('2', 'ar', d.l2Ar), l2En: g('2', 'en', d.l2En));
  }
  final String l1Ar, l1En, l2Ar, l2En;
  String get level1 => eduName(l1Ar, l1En);
  String get level2 => eduName(l2Ar, l2En);
}

class EduCountryCatalog {
  const EduCountryCatalog({
    required this.country,
    this.stages = const [],
    this.subjects = const [],
    this.version = '',
    this.geoLabels = const EduGeoLabels(),
  });
  factory EduCountryCatalog.fromJson(Map<String, dynamic> j, {EduGeoLabels geoLabels = const EduGeoLabels()}) =>
      EduCountryCatalog(
        country: _s(j['country']),
        stages: [for (final s in _list(j['stages'])) EduStage.fromJson(s)],
        subjects: [for (final s in _list(j['subjects'])) EduSubject.fromJson(s)],
        version: _s(j['version']),
        geoLabels: geoLabels,
      );
  final String country, version;
  final List<EduStage> stages;
  final List<EduSubject> subjects;
  final EduGeoLabels geoLabels;

  bool get isEmpty => stages.isEmpty;

  EduStage? stage(int? id) {
    for (final s in stages) {
      if (s.id == id) return s;
    }
    return null;
  }

  EduGrade? grade(int? id) {
    if (id == null) return null;
    for (final s in stages) {
      for (final g in s.grades) {
        if (g.id == id) return g;
      }
    }
    return null;
  }

  EduSubject? subject(int? id) {
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The subjects taught in [gradeId] (the whole list when the grade is unknown).
  List<EduSubject> subjectsOf(int? gradeId) {
    final g = grade(gradeId);
    if (g == null) return subjects;
    final ids = g.subjectIds.toSet();
    return [for (final s in subjects) if (ids.contains(s.id)) s];
  }
}

typedef EduFetch = Future<dynamic> Function(String path, {Map<String, dynamic>? query, Map<String, String>? headers});

class EduCatalog {
  EduCatalog({EduFetch? fetch, Future<SharedPreferences> Function()? prefs})
      : _fetch = fetch ?? _apiFetch,
        _prefs = prefs ?? SharedPreferences.getInstance;

  static final EduCatalog instance = EduCatalog();

  static Future<dynamic> _apiFetch(String path, {Map<String, dynamic>? query, Map<String, String>? headers}) =>
      ApiClient().get(path, queryParams: query, auth: false, headers: headers);

  final EduFetch _fetch;
  final Future<SharedPreferences> Function() _prefs;
  final Map<String, EduCountryCatalog> _mem = {};
  final Map<String, Future<EduCountryCatalog?>> _inflight = {};
  final Map<String, List<EduArea>> _areas = {};

  static String _key(String c) => 'edu_catalog_${c.toUpperCase()}';

  /// The catalog already in memory (no request), or null.
  EduCountryCatalog? cached(String country) => _mem[country.toUpperCase()];

  /// Load once per country: memory, else the stored copy revalidated against the server, else the network. Null
  /// when nothing is available (offline and never loaded). [force] revalidates even when memory has it.
  Future<EduCountryCatalog?> load(String country, {bool force = false}) {
    final c = country.toUpperCase();
    if (!force && _mem.containsKey(c)) return Future.value(_mem[c]);
    return _inflight[c] ??= _load(c).whenComplete(() {
      _inflight.remove(c);
    });
  }

  Future<EduCountryCatalog?> _load(String c) async {
    Map<String, dynamic>? stored;
    try {
      final raw = (await _prefs()).getString(_key(c));
      if (raw != null) stored = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    var current = stored == null ? null : _build(stored);
    final version = current?.version ?? '';
    try {
      final body = await _fetch('/edu/catalog',
          query: {'country': c}, headers: version.isEmpty ? null : {'If-None-Match': '"edu-$c-$version"'});
      if (body is Map) {
        final j = Map<String, dynamic>.from(body);
        j['geo_labels'] = await _labels(c, stored?['geo_labels']);
        current = _build(j);
        try {
          (await _prefs()).setString(_key(c), jsonEncode(j));
        } catch (_) {}
      }
    } on ApiException {
      // a 304, offline or a server error: keep what is stored
    } catch (_) {}
    if (current != null) _mem[c] = current;
    return current;
  }

  EduCountryCatalog _build(Map<String, dynamic> j) =>
      EduCountryCatalog.fromJson(j, geoLabels: EduGeoLabels.fromJson(j['geo_labels']));

  Future<dynamic> _labels(String c, dynamic fallback) async {
    try {
      final list = await _fetch('/edu/countries');
      if (list is List) {
        for (final e in list) {
          if (e is Map && _s(e['code']).toUpperCase() == c) return e['geo_labels'];
        }
      }
    } catch (_) {}
    return fallback;
  }

  /// Level-1 areas, or the children of [parentId]; cached per parent. Empty when the call fails.
  Future<List<EduArea>> areas(String country, {int? parentId}) async {
    final k = '${country.toUpperCase()}:${parentId ?? 0}';
    final hit = _areas[k];
    if (hit != null) return hit;
    try {
      final r = await _fetch('/edu/areas',
          query: {'country': country.toUpperCase(), 'parent_id': ?parentId});
      return _areas[k] = [for (final a in _list(r)) EduArea.fromJson(a)];
    } catch (_) {
      return const [];
    }
  }

  void clearMemory() {
    _mem.clear();
    _areas.clear();
  }
}
