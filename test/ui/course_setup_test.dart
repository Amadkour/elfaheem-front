import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/features/courses/course_setup.dart';
import 'package:flutter_education_app/features/courses/course_setup_views.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  final json = jsonDecode(File('test/fixtures/payloads/course_setup.json').readAsStringSync()) as Map<String, dynamic>;
  final cat = EduCountryCatalog.fromJson(
      jsonDecode(File('test/fixtures/payloads/edu_catalog_eg.json').readAsStringSync()) as Map<String, dynamic>);
  const cairo = EduArea(id: 5, key: 'cairo', nameAr: 'القاهرة', nameEn: 'Cairo', hasChildren: true);
  const nasr = EduArea(id: 6, key: 'nasr', nameAr: 'مدينة نصر', nameEn: 'Nasr City', level: 2);
  Future<List<EduArea>> load(int? p) async => p == null ? [cairo] : [nasr];

  setUp(() => AppConfig.lang = 'en');

  test('the course response parses into the setup', () {
    final s = CourseSetup.fromJson(json);
    expect(s.deliveryMode, 'both');
    expect(s.countryCode, 'EG');
    expect(s.subject?.id, 3);
    expect(s.area?.id, 6);
    expect(s.area?.parent?.name, 'Cairo');
    expect(s.address, '12 Tahrir St');
    expect(s.targets.map((t) => t.label).toList(), ['Secondary - Grade 2', 'Primary']);
    expect(s.targets.map((t) => t.gradeId).toList(), [22, null]);
    expect(s.isEmpty, isFalse);
    expect(TeacherCourse.fromJson(json).setup.targets.length, 2);
  });

  test('an older course answer is an empty setup, an online course has no address', () {
    final s = CourseSetup.fromJson({'id': 1});
    expect(s.isEmpty, isTrue);
    expect(s.deliveryMode, 'online');
    expect(CourseSetup.fromJson({'delivery_mode': 'bogus'}).deliveryMode, 'online');
  });

  test('the bilingual text of course_area_required', () {
    AppConfig.lang = 'ar';
    expect(courseAreaRequiredText(), contains('المنطقة'));
    AppConfig.lang = 'en';
    expect(courseAreaRequiredText(), contains('area'));
  });

  testWidgets('form section: online, in person with the area and address, and no catalog', (tester) async {
    final address = TextEditingController();
    Widget section({String mode = 'both', List<CourseTarget> targets = const [], EduCountryCatalog? c}) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CourseSetupSection(
            stages: c?.stages ?? const [],
            subjects: c?.subjects ?? const [],
            targets: targets,
            onToggleTarget: (_) {},
            subjectId: c?.subjects.isEmpty ?? true ? null : c!.subjects.first.id,
            onSubject: (_) {},
            deliveryMode: mode,
            onDeliveryMode: (_) {},
            loadAreas: load,
            onArea: (_, _) {},
            area1: cairo,
            area2: nasr,
            address: address,
          ),
        );
    await expectNoLayoutErrors(tester, () => section(c: cat, targets: CourseSetup.fromJson(json).targets));
    await expectNoLayoutErrors(tester, () => section(mode: 'online', c: cat));
    await expectNoLayoutErrors(tester, () => section(mode: 'in_person'));
  });

  testWidgets('form section: a stage opens its grades and a grade toggles', (tester) async {
    CourseTarget? got;
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
      child: CourseSetupSection(
        stages: cat.stages,
        subjects: cat.subjects,
        targets: const [],
        onToggleTarget: (t) => got = t,
        subjectId: null,
        onSubject: (_) {},
        deliveryMode: 'online',
        onDeliveryMode: (_) {},
        loadAreas: load,
        onArea: (_, _) {},
        address: TextEditingController(),
      ),
    )));
    await tester.pump();
    await tester.tap(find.text('Primary'));
    await tester.pump();
    await tester.tap(find.text('Whole stage'));
    expect(got?.stageId, cat.stages.firstWhere((s) => s.nameEn == 'Primary').id);
    expect(got?.gradeId, isNull);
  });

  testWidgets('profile block: full, online only, and empty', (tester) async {
    await expectNoLayoutErrors(tester, () => CourseWhoWhereBlock(setup: CourseSetup.fromJson(json)));
    await expectNoLayoutErrors(
        tester,
        () => CourseWhoWhereBlock(
            setup: CourseSetup.fromJson({
          'delivery_mode': 'online',
          'targets': [
            {'stage_id': 1, 'stage_ar': 'الابتدائية', 'stage_en': 'Primary'}
          ],
        })));
    await tester.pumpWidget(layoutHost(const CourseWhoWhereBlock(setup: CourseSetup())));
    expect(find.byType(Text), findsNothing);
  });
}
