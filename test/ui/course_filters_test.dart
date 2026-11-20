// The course filter bar (D-1325): the model ↔ GET /courses params, the client-side rules, the per-user store, and
// the bar's layout (phone chips + sheet, desktop row; ar / en).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/features/courses/course_filters.dart';
import 'package:flutter_education_app/features/courses/course_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

void main() {
  final cat = EduCountryCatalog.fromJson(
      jsonDecode(File('test/fixtures/payloads/edu_catalog_eg.json').readAsStringSync()) as Map<String, dynamic>);
  final edu = CourseFilterEdu(catalog: cat, loadAreas: (_) async => const []);

  group('CourseFilters ↔ query params', () {
    test('round trip keeps every param', () {
      const f = CourseFilters(country: 'EG', stageId: 1, gradeId: 12, subjectId: 3, delivery: 'in_person', areaId: 5);
      final q = f.toQuery();
      expect(q, {'country': 'EG', 'stage_id': 1, 'grade_id': 12, 'subject_id': 3, 'delivery': 'in_person', 'area_id': 5});
      expect(CourseFilters.fromQuery(q), f);
    });

    test('empty sends nothing; strings parse; bad values drop', () {
      expect(CourseFilters.empty.toQuery(), isEmpty);
      final f = CourseFilters.fromQuery({'country': 'eg', 'stage_id': '2', 'grade_id': 'x', 'delivery': 'both', 'kind': 'live'});
      expect(f.toQuery(), {'country': 'EG', 'stage_id': 2});
      expect(CourseFilters.fromQuery(null), CourseFilters.empty);
    });

    test('the join flow map reads the same way', () {
      final f = CourseFilters.fromQuery({'country': 'EG', 'stage_id': 1, 'grade_id': 11, 'delivery': 'online', 'area_id': 7});
      expect(f.activeCount, 3);
      expect(f.isEmpty, isFalse);
    });

    test('clear keeps the country; another level drops the grade', () {
      const f = CourseFilters(country: 'SA', stageId: 1, gradeId: 11, delivery: 'online');
      expect(f.cleared().toQuery(), {'country': 'SA'});
      expect(f.cleared().isEmpty, isTrue);
      expect(f.withLevel(2, null).toQuery(), {'country': 'SA', 'stage_id': 2, 'delivery': 'online'});
    });

    test('json keeps the area names', () {
      final f = CourseFilters.fromJson(const CourseFilters(areaId: 5, areaAr: 'القاهرة', areaEn: 'Cairo').toJson());
      expect(f.areaId, 5);
      expect(f.areaEn, 'Cairo');
    });
  });

  group('matches (the server rules on a loaded list)', () {
    const sec = CourseSetup(
      deliveryMode: 'both',
      subject: CourseNamed(id: 3),
      area: CourseNamed(id: 9, parent: CourseNamed(id: 5)),
      targets: [CourseTarget(stageId: 2)], // the whole stage
    );
    test('grade matches a whole-stage target of its stage', () {
      expect(const CourseFilters(stageId: 2, gradeId: 21).matches(sec), isTrue);
      expect(const CourseFilters(stageId: 1, gradeId: 11).matches(sec), isFalse);
    });
    test('both matches online and in person; a level-1 area matches its cities', () {
      expect(const CourseFilters(delivery: 'online').matches(sec), isTrue);
      expect(const CourseFilters(delivery: 'in_person', areaId: 5).matches(sec), isTrue);
      expect(const CourseFilters(areaId: 6).matches(sec), isFalse);
      expect(const CourseFilters(subjectId: 4).matches(sec), isFalse);
      expect(const CourseFilters(delivery: 'in_person').matches(const CourseSetup()), isFalse);
    });
  });

  group('CourseFilterStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('remembered per user, else the profile seed, else empty', () async {
      expect(await CourseFilterStore.initial('7'), CourseFilters.empty);
      SharedPreferences.setMockInitialValues({
        'course_filters_seed_7': jsonEncode({'country': 'EG', 'stage_id': 1, 'grade_id': 11}),
      });
      expect((await CourseFilterStore.initial('7')).gradeId, 11);
      expect(await CourseFilterStore.initial('8'), CourseFilters.empty);
      await CourseFilterStore.save('7', const CourseFilters(country: 'EG', delivery: 'online'));
      expect((await CourseFilterStore.initial('7')).toQuery(), {'country': 'EG', 'delivery': 'online'});
      // an explicit Clear is remembered (the seed does not come back)
      await CourseFilterStore.save('7', CourseFilters.empty);
      expect(await CourseFilterStore.initial('7'), CourseFilters.empty);
    });
  });

  group('CourseFilterBar layout', () {
    const picked = CourseFilters(country: 'EG', stageId: 1, gradeId: 11, subjectId: 1, delivery: 'in_person', areaId: 5, areaAr: 'مدينة نصر', areaEn: 'Nasr City');

    testWidgets('filters picked, with the catalog (phone chips, desktop row)', (tester) async {
      await expectNoLayoutErrors(tester, () => CourseFilterBar(value: picked, edu: edu, resultCount: 128, onChanged: (_) {}));
    });

    testWidgets('nothing picked, no catalog yet, no count', (tester) async {
      await expectNoLayoutErrors(tester, () => CourseFilterBar(value: CourseFilters.empty, onChanged: (_) {}));
      await expectNoLayoutErrors(tester, () => CourseFilterBar(value: picked, resultCount: 0, onChanged: (_) {}));
    });

    testWidgets('the sheet opens on a phone', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => CourseFilterBar(value: picked, edu: edu, resultCount: 3, onChanged: (_) {}),
        act: (t) async {
          final open = find.byKey(const ValueKey('course_filters.open'));
          if (open.evaluate().isEmpty) return; // the desktop row has no sheet button
          await t.tap(open);
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
        },
      );
    });

    testWidgets('a chip removes its filter; Clear keeps the country', (tester) async {
      AppConfig.lang = 'en';
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      CourseFilters? got;
      await tester.pumpWidget(layoutHost(CourseFilterBar(value: picked, edu: edu, resultCount: 2, onChanged: (f) => got = f)));
      await tester.pump();
      expect(find.text('2 courses'), findsOneWidget);
      await tester.ensureVisible(find.text('Nasr City'));
      await tester.pump();
      await tester.tap(find.text('Nasr City'));
      expect(got?.areaId, isNull);
      expect(got?.gradeId, 11);
      await tester.tap(find.byKey(const ValueKey('course_filters.clear')));
      expect(got?.toQuery(), {'country': 'EG'});
    });
  });
}
