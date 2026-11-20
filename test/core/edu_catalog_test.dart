import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final fixture = jsonDecode(File('test/fixtures/payloads/edu_catalog_eg.json').readAsStringSync()) as Map<String, dynamic>;

  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
  });

  test('parses stages, grades, tracks and subjects', () {
    final c = EduCountryCatalog.fromJson(fixture);
    expect(c.country, 'EG');
    expect(c.version, '7');
    expect(c.stages.map((s) => s.key), ['primary', 'secondary', 'university']);
    expect(c.stage(3)!.contactOnly, isTrue);
    expect(c.stage(3)!.hasGrades, isFalse);
    expect(c.grade(21)!.tracks.map((t) => t.key), ['science', 'arts']);
    expect(c.grade(11)!.tracks, isEmpty);
    expect(c.subjectsOf(12).map((s) => s.key), ['math']);
    expect(c.subjectsOf(null).length, 2);
  });

  test('names follow the app language', () {
    final c = EduCountryCatalog.fromJson(fixture);
    expect(c.stage(1)!.name, 'Primary');
    AppConfig.lang = 'ar';
    expect(c.stage(1)!.name, 'الابتدائي');
  });

  test('geo labels default and parse', () {
    expect(const EduGeoLabels().level1, 'Governorate');
    final l = EduGeoLabels.fromJson({
      '1': {'ar': 'ولاية', 'en': 'State'}
    });
    expect(l.level1, 'State');
    expect(l.level2, 'City or district');
  });

  test('loads once, stores a copy, then refetches without If-None-Match and keeps the stored copy offline', () async {
    var calls = 0;
    final cat = EduCatalog(fetch: (path, {query, headers}) async {
      if (path == '/edu/countries') {
        return [
          {
            'code': 'EG',
            'geo_labels': {
              '1': {'ar': 'محافظة', 'en': 'Governorate'}
            }
          }
        ];
      }
      calls++;
      return fixture;
    });
    final a = await cat.load('eg');
    expect(a!.stages.length, 3);
    expect(await cat.load('EG'), same(a));
    expect(calls, 1);

    Map<String, String>? seen;
    final cat2 = EduCatalog(fetch: (path, {query, headers}) async {
      if (path == '/edu/catalog') seen = headers;
      throw Exception('offline');
    });
    final b = await cat2.load('EG');
    expect(b!.stages.length, 3);
    expect(seen, isNull);
    expect(b.geoLabels.level1, 'Governorate');
  });

  test('nothing stored and offline gives null; areas fail to empty', () async {
    final cat = EduCatalog(fetch: (path, {query, headers}) async => throw Exception('offline'));
    expect(await cat.load('EG'), isNull);
    expect(await cat.areas('EG'), isEmpty);
  });

  test('areas parse and cache per parent', () async {
    var n = 0;
    final cat = EduCatalog(fetch: (path, {query, headers}) async {
      n++;
      return [
        {'id': 5, 'key': 'cairo', 'name_ar': 'القاهرة', 'name_en': 'Cairo', 'level': 1, 'has_children': true}
      ];
    });
    final a = await cat.areas('EG');
    expect(a.single.hasChildren, isTrue);
    await cat.areas('EG');
    expect(n, 1);
  });
}
