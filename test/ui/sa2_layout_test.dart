// The S-A2 bodies that had no layout test of their own (redesign S-A2): the legal page (privacy / terms segment,
// one card of section rows, the switch in place) and the recommendations page (the one course card with the
// reason, "Not interested" and the price), at 320x640 and 1400x900, ar / en, text scale 1.3, over a fake server.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/courses/roadmap/recommendations.dart';
import 'package:flutter_education_app/features/profile/about/about_and_terms_screen.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

const _long = 'مقدمة شاملة جداً في الذكاء الاصطناعي وتعلم الآلة للمبتدئين والمحترفين A complete introduction to AI';

Map<String, dynamic> _doc(String title) => {
      'meta': {'id': 1, 'last_updated': '1 November 2026', 'version': '3.0.0'},
      'intro': _long,
      'sections': [
        for (var i = 1; i <= 7; i++)
          {'id': i, 'icon_name': 'lock', 'title': '$title $i $_long', 'body': '$_long\n- $_long\n- $_long', 'order': i},
      ],
    };

Map<String, dynamic> _recs() => {
      'total': 3,
      'items': [
        for (var i = 1; i <= 3; i++)
          {
            'reason': 'matches_interest',
            'reason_ar': _long,
            'reason_en': _long,
            'course': {
              'id': i,
              'name_ar': _long,
              'name_en': _long,
              'teacher': {'name': _long},
              'final_price': 999999,
              'currency': 'SAR',
            },
          },
      ],
    };

void main() {
  late FakeApi fake;
  late StorageService storage;

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    mockRequestPlugins();
    fake = FakeApi({
      'GET /api/v1/app-content/legal/privacy*': (_) => _doc('Privacy'),
      'GET /api/v1/app-content/legal/terms*': (_) => _doc('Terms'),
      'GET /api/v1/me/recommendations*': (_) => _recs(),
      'POST /api/v1/me/recommendations/events': (_) => <String, dynamic>{},
    }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{});
    fake.install();
  });

  tearDown(() => fake.uninstall());

  testWidgets('legal: the segment, the section rows, and the terms opened in place', (t) async {
    await expectNoLayoutErrors(
      t,
      () => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => AboutTermsProvider()),
        ],
        child: const TermsScreen(privacy: true, canAsk: false),
      ),
      scaffold: false,
      frames: 6,
      act: (t) async {
        expect(find.byKey(const ValueKey('terms.tabs')), findsOneWidget);
        await t.tap(find.descendant(of: find.byKey(const ValueKey('terms.tabs')), matching: find.text(AppConfig.lang == 'ar' ? 'الشروط' : 'Terms')));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(find.textContaining('Terms 1'), findsWidgets);
      },
    );
  });

  testWidgets('recommendations page: long names, reasons and prices', (t) async {
    await expectNoLayoutErrors(t, () => const RecommendationsPage(), scaffold: false, frames: 6);
  });
}
