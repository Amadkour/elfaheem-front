import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/design/edu_pickers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  final cat = EduCountryCatalog.fromJson(
      jsonDecode(File('test/fixtures/payloads/edu_catalog_eg.json').readAsStringSync()) as Map<String, dynamic>);
  const cairo = EduArea(id: 5, key: 'cairo', nameAr: 'القاهرة', nameEn: 'Cairo', hasChildren: true);
  const nasr = EduArea(id: 6, key: 'nasr', nameAr: 'مدينة نصر', nameEn: 'Nasr City', level: 2);
  Future<List<EduArea>> load(int? p) async => p == null ? [cairo] : [nasr];

  testWidgets('stage + grade + track picker', (tester) async {
    await expectNoLayoutErrors(tester, () => EduStageGradePicker(stages: cat.stages, stageId: 2, gradeId: 21, trackKey: 'science', onChanged: (_, _, _) {}));
  });

  testWidgets('stage picker with nothing selected and with an empty catalog', (tester) async {
    await expectNoLayoutErrors(tester, () => EduStageGradePicker(stages: cat.stages, onChanged: (_, _, _) {}));
    await expectNoLayoutErrors(tester, () => EduStageGradePicker(stages: const [], onChanged: (_, _, _) {}));
  });

  testWidgets('stage picker reports the pick', (tester) async {
    AppConfig.lang = 'en';
    int? s;
    int? g;
    await tester.pumpWidget(layoutHost(EduStageGradePicker(stages: cat.stages, stageId: 1, onChanged: (a, b, _) {
      s = a;
      g = b;
    })));
    await tester.pump();
    await tester.tap(find.text('Primary 2'));
    expect((s, g), (1, 12));
  });

  testWidgets('area picker, closed and with the sheet open', (tester) async {
    await expectNoLayoutErrors(
        tester, () => EduAreaPicker(loadAreas: load, level1: cairo, level2: nasr, address: TextEditingController(), onChanged: (_, _) {}));
    await expectNoLayoutErrors(tester, () => EduAreaPicker(loadAreas: load, onChanged: (_, _) {}),
        act: (t) async {
      await t.tap(find.byIcon(Icons.location_on_outlined));
    });
  });

  testWidgets('country picker', (tester) async {
    await expectNoLayoutErrors(
        tester, () => EduCountryPicker(countries: const {'EG': 'Egypt', 'SA': 'Saudi Arabia'}, value: 'EG', onChanged: (_) {}));
  });
}
