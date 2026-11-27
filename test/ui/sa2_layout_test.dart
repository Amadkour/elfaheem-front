// The S-A2 bodies that had no layout test of their own (redesign S-A2): the legal page (privacy / terms segment,
// one card of section rows, the switch in place) and the recommendations page (the one course card with the
// reason, "Not interested" and the price), at 320x640 and 1400x900, ar / en, text scale 1.3, over a fake server.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/features/courses/roadmap/recommendations.dart';
import 'package:flutter_education_app/features/profile/about/about_and_terms_screen.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_provider.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_form.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart';
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

final _saStages = [
  const EduStage(id: 1, key: 'intermediate', nameAr: 'المتوسط', nameEn: 'Intermediate'),
  EduStage(id: 2, key: 'secondary', nameAr: 'الثانوي', nameEn: 'Secondary', grades: [
    for (var i = 1; i <= 3; i++)
      EduGrade(id: 20 + i, key: 's$i', nameAr: 'الصف $i الثانوي', nameEn: 'Secondary grade $i', number: i, tracks: [
        for (final (k, ar, en) in const [
          ('general', 'المسار العام', 'General track'),
          ('cs', 'علوم الحاسب والهندسة', 'Computer science and engineering'),
          ('health', 'الصحة والحياة', 'Health and life'),
          ('business', 'إدارة الأعمال', 'Business administration'),
          ('sharia', 'الشرعي', 'Sharia'),
        ])
          EduTrack(key: k, nameAr: ar, nameEn: en),
      ]),
  ]),
];

Widget studyForm(StudyProfile value, ValueChanged<StudyProfile> onChanged) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: StudyProfileForm(
        value: value,
        compact: true,
        edu: StudyEduData(
          countries: const [EduCountry(code: 'SA', nameAr: 'السعودية', nameEn: 'Saudi Arabia')],
          country: 'SA',
          stages: _saStages,
          loadAreas: (_) async => const [],
        ),
        onChanged: onChanged,
      ),
    );

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

  testWidgets('study step: the grade folded with Change, the track chips (S-A2)', (t) async {
    var value = const StudyProfile(countryCode: 'SA', stageId: 2, gradeId: 22, track: 'cs');
    await expectNoLayoutErrors(
      t,
      () {
        value = const StudyProfile(countryCode: 'SA', stageId: 2, gradeId: 22, track: 'cs'); // every size and language starts over
        return StatefulBuilder(builder: (context, set) => studyForm(value, (v) => set(() => value = v)));
      },
      act: (t) async {
        expect(find.byKey(const ValueKey('study.grade_summary')), findsOneWidget);
        expect(find.byKey(const ValueKey('study.edu_track.cs')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('study.edu_track.health')));
        await t.pump();
        expect(value.track, 'health');
        await t.tap(find.byKey(const ValueKey('study.grade_change')));
        await t.pump();
        expect(find.byKey(const ValueKey('study.edu_grade.21')), findsOneWidget);
      },
    );
  });
}
