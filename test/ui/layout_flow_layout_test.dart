// The v3 export page (D-142) at 320×640 and 1400×900, Arabic and English, text ×1.3: every step, in table mode and
// with a two-language custom card design (canvas on the wide window, the simple form on the phone).
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export_layout/layout_logic.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_education_app/design/export_layout/layout_page.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../export/layout_fake.dart';
import '../support/fake_api.dart';
import 'layout_harness.dart';

Map<String, Object> _customDraft() {
  final fields = layoutFieldsOf(layoutTestExport().columns);
  final doc = LayoutDocument(format: 'xlsx', languages: ['ar', 'en']);
  for (final l in ['ar', 'en']) {
    final d = layoutStarter(mode: 'custom', lang: l, fields: fields, perLine: 2);
    d.row.elements.first.rules.add(LayoutRule(when: [LayoutCond(field: 'score', op: '>=', value: 50)], then: LayoutThen(text: 'Pass', icon: 'check')));
    d.afterItems = LayoutBand(height: 26, elements: [
      LayoutElement(id: 'sig', kind: 'signature', x: 2, y: 1, w: 45, h: 22, style: LayoutStyle(sigName: 'Dr. A', sigTitle: 'Dean')),
      LayoutElement(id: 'qr', kind: 'qr', x: 60, y: 1, w: 18, h: 18, value: '{{title}}'),
    ]);
    d.watermark = LayoutWatermark(text: 'DRAFT');
    doc.designs[l] = d;
  }
  return {'export_layout.v3.draft.test.students': jsonEncode({'doc': doc.toJson(withSource: false)})};
}

void main() {
  late FakeApi api;
  late LayoutFakeServer server;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.disableList = [];
    server = LayoutFakeServer();
    api = FakeApi(server.routes(), latency: const Duration(milliseconds: 20))..install();
  });
  tearDown(() => api.uninstall());

  for (var step = 0; step < 5; step++) {
    testWidgets('table design, step ${step + 1}', (tester) async {
      await expectNoLayoutErrors(tester, () => ExportLayoutPage(export: layoutTestExport(), liveStream: kNoStream, saveFile: (_, _, _) async {}, initialStep: step), frames: 8);
    });
  }

  for (var step = 1; step < 5; step++) {
    testWidgets('custom cards in two languages, step ${step + 1}', (tester) async {
      SharedPreferences.setMockInitialValues(_customDraft());
      await expectNoLayoutErrors(tester, () => ExportLayoutPage(export: layoutTestExport(), liveStream: kNoStream, saveFile: (_, _, _) async {}, initialStep: step), frames: 8);
    });
  }

  // between the phone form and the side dock (720 – 1000 px): the canvas with the engine's docked panel under it
  for (final step in [2, 3]) {
    testWidgets('tablet width, docked properties, step ${step + 1}', (tester) async {
      SharedPreferences.setMockInitialValues(_customDraft());
      addTearDown(tester.view.reset);
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 760);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(layoutHost(ExportLayoutPage(export: layoutTestExport(), liveStream: kNoStream, saveFile: (_, _, _) async {}, initialStep: step)));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(StudioDockPanel), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'layout error at 900x760 / $lang');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('list design, items step', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ExportLayoutPage(export: layoutTestExport(), liveStream: kNoStream, saveFile: (_, _, _) async {}, initialStep: 1),
      frames: 8,
      act: (tester) async {
        await tester.tap(find.byKey(const ValueKey('layout-mode-list')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('layout-next')));
      },
    );
  });
}
