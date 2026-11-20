// Learning Hub F3 (D-1311): the registration capture. The new fields parse and are sent as ids, the countries parse
// with minor_age / contact_whatsapp, and every new widget (the student's levels step, the teacher's multi-select, the
// consent body and card, the study form over the catalog) has no layout error at 320 / 1400, ar + en, textScaler 1.3.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/features/auth/register_levels_step.dart';
import 'package:flutter_education_app/features/parent/parent_consent.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_form.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

final _stages = [
  EduStage(id: 1, key: 'primary', nameAr: 'المرحلة الابتدائية', nameEn: 'Primary', grades: [
    for (var i = 1; i <= 6; i++) EduGrade(id: 10 + i, key: 'p$i', nameAr: 'الصف $i الابتدائي', nameEn: 'Primary grade $i', number: i),
  ]),
  EduStage(id: 2, key: 'secondary', nameAr: 'المرحلة الثانوية', nameEn: 'Secondary', grades: [
    for (var i = 1; i <= 3; i++)
      EduGrade(id: 20 + i, key: 's$i', nameAr: 'الصف $i الثانوي', nameEn: 'Secondary grade $i', number: i),
  ]),
  const EduStage(id: 3, key: 'university', nameAr: 'الجامعة', nameEn: 'University', hasGrades: false, contactOnly: true),
];

const _countries = [
  EduCountry(code: 'EG', nameAr: 'مصر', nameEn: 'Egypt', minorAge: 18, contactWhatsapp: '+20 100 000 0000'),
  EduCountry(code: 'SA', nameAr: 'السعودية', nameEn: 'Saudi Arabia', minorAge: 18),
];

Future<List<EduArea>> _noAreas(int? parent) async => const [];

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('the study profile reads and sends the catalog ids', () {
    final p = StudyProfile.fromJson({
      'stage': 'secondary',
      'grade': 2,
      'country_code': 'EG',
      'stage_id': 2,
      'grade_id': 22,
      'area_id': 7,
      'gender': 'f',
    });
    expect((p.countryCode, p.stageId, p.gradeId, p.areaId, p.gender), ('EG', 2, 22, 7, 'f'));
    final j = p.toJson();
    expect(j['stage_id'], 2);
    expect(j['grade_id'], 22);
    expect(j['area_id'], 7);
    expect(j['gender'], 'f');
    expect(j.containsKey('stage'), isFalse); // ids win: the server writes the old keys itself
    expect(StudyProfile.fromJson({'stage': 'primary', 'grade': 1}).toJson()['stage'], 'primary');
  });

  test('the countries parse; a contact number becomes a wa.me link; the country is the profile\'s else the first', () {
    final list = parseEduCountries([
      {'code': 'eg', 'name_ar': 'مصر', 'name_en': 'Egypt', 'minor_age': 18, 'phone_code': '+20', 'contact_whatsapp': '+20 100 000 0000'},
      {'code': 'SA', 'name_ar': 'السعودية', 'name_en': 'Saudi Arabia'},
    ]);
    expect(list.first.code, 'EG');
    expect(list.first.whatsappLink, 'https://wa.me/201000000000');
    expect(list.last.whatsappLink, isNull);
    expect(list.last.minorAge, 18);
    expect(pickEduCountry(list, 'SA')?.code, 'SA');
    expect(pickEduCountry(list, null)?.code, 'EG');
    expect(pickEduCountry(const [], 'SA'), isNull);
  });

  test('the Learning Hub 422 codes have bilingual texts', () {
    for (final code in ['edu_grade_mismatch', 'edu_stage_invalid', 'edu_area_invalid', 'study_grade_required', 'consent_required']) {
      AppConfig.lang = 'ar';
      final ar = eduErrorText(code);
      AppConfig.lang = 'en';
      final en = eduErrorText(code);
      expect(ar, isNotNull);
      expect(en, isNotNull);
      expect(ar, isNot(en));
    }
    expect(eduErrorText('other'), isNull);
  });

  testWidgets('the student levels step', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: RegisterLevelsStep(
          countries: _countries,
          country: 'EG',
          stages: _stages,
          stageId: 3,
          onChanged: (_, _, _) {},
          errorText: 'Pick your stage',
        ),
      ),
    );
  });

  testWidgets('the teacher levels step', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: TeachingLevelsStep(
          stages: _stages,
          selected: [const TeachingLevel(1), const TeachingLevel(2, 22), const TeachingLevel(2, 23)],
          onChanged: (_) {},
          errorText: 'Pick at least one stage',
        ),
      ),
    );
  });

  testWidgets('the study form over the catalog', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: StudyProfileForm(
          value: const StudyProfile(countryCode: 'EG', stageId: 2, gradeId: 22, gender: 'f'),
          showErrors: true,
          edu: StudyEduData(countries: _countries, country: 'EG', stages: _stages, loadAreas: _noAreas),
          onChanged: (_) {},
        ),
      ),
    );
  });

  testWidgets('the consent body and the card notice', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          ParentConsentBody(accepted: true, childName: 'محمد أحمد عبد الرحمن السيد', onChanged: (_) {}),
          ConsentNeededNotice(onGive: () {}),
        ]),
      ),
    );
  });

  testWidgets('the consent dialog needs the box before "I agree" works', (tester) async {
    bool? result;
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(layoutHost(Builder(
      builder: (context) => TextButton(
        onPressed: () async => result = await showParentConsentDialog(context, childName: 'Sara'),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('consent.agree')));
    await tester.pumpAndSettle();
    expect(result, isNull); // disabled: still open
    await tester.tap(find.byKey(const ValueKey('consent.box')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('consent.agree')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets("the teacher's levels ride in the complete-profile call, for that account only (D-1315)", (tester) async {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    final storage = await StorageService.getInstance();
    final bodies = <Map<String, dynamic>>[];
    Map<String, dynamic> read(Object? d) =>
        Map<String, dynamic>.from((d is String ? jsonDecode(d) : d) as Map);
    final api = FakeApi({
      'POST /api/v1/auth/teacher-profile': (o) {
        bodies.add(read(o.data));
        return {'ok': true};
      },
    }, latency: const Duration(milliseconds: 5))
      ..install();
    addTearDown(api.uninstall);
    final auth = MyAuthProvider(api: ApiClient(), storage: storage)
      ..selectedTeachingType = {'text': 'both'}
      ..selectedPaymentType = {'text': 'free'}
      ..selectedSpecialization = {'id': 4};
    var done = false;
    auth
        .completeTeacherProfile(experienceYears: 2, email: 't@x.io', levels: const [
          TeachingLevel(1),
          TeachingLevel(2, 22),
        ])
        .then((_) => done = true);
    await tester.pump(const Duration(milliseconds: 100));
    auth.completeTeacherProfile(experienceYears: 2, email: 't@x.io').ignore();
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isTrue);
    expect(bodies.first['teaching_levels'], [
      {'stage_id': 1, 'grade_id': null},
      {'stage_id': 2, 'grade_id': 22},
    ]);
    expect(bodies.last.containsKey('teaching_levels'), isFalse); // none chosen: the key is left out (old servers)
  });

  testWidgets('a saved city reopens with its own name and its governorate (D-1315)', (tester) async {
    const cairo = EduArea(id: 5, key: 'cairo', nameAr: 'القاهرة', nameEn: 'Cairo', hasChildren: true);
    const nasr = EduArea(id: 6, key: 'nasr', nameAr: 'مدينة نصر', nameEn: 'Nasr City', level: 2);
    Future<List<EduArea>> load(int? parent) async => parent == null ? const [cairo] : (parent == 5 ? const [nasr] : const []);
    Widget form(StudyProfile v) => layoutHost(SingleChildScrollView(
          child: StudyProfileForm(
            value: v,
            edu: StudyEduData(countries: _countries, country: 'EG', stages: _stages, loadAreas: load),
            onChanged: (_) {},
          ),
        ));
    await tester.pumpWidget(form(const StudyProfile(countryCode: 'EG', stageId: 2, gradeId: 22, areaId: 6, governorate: 'cairo')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nasr City, Cairo'), findsOneWidget);
    // a governorate saved on its own stays the governorate
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(form(const StudyProfile(countryCode: 'EG', stageId: 2, gradeId: 22, areaId: 5, governorate: 'cairo')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Cairo'), findsOneWidget);
    expect(find.textContaining('Nasr'), findsNothing);
  });
}
