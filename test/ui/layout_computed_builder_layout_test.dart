import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export_layout/layout_computed.dart';
import 'package:flutter_education_app/design/export_layout/layout_computed_builder.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _fields = [
  LayoutField(key: 'name', labelAr: 'الاسم', labelEn: 'Name'),
  LayoutField(key: 'score', labelAr: 'الدرجة', labelEn: 'Score', type: 'number'),
  LayoutField(key: 'max', labelAr: 'العظمى', labelEn: 'Max', type: 'number'),
];

final _rows = <Map<String, Object?>>[
  {'name': 'Ahmed', 'score': 80, 'max': 100},
  {'name': 'Sara', 'score': 40, 'max': 50},
  {'name': 'Omar', 'score': 49, 'max': 100},
];

LayoutDocument _doc() => LayoutDocument(computed: [
      LayoutComputedField(
        key: 'calc.result',
        labelEn: 'Result',
        labelAr: 'النتيجة',
        cases: [
          LayoutCase(
            when: LayoutCondGroup(match: 'any', items: [
              LayoutCond(field: 'score', op: '>=', value: 50),
              LayoutCondGroup(items: [LayoutCond(field: 'name', op: 'starts_with', value: 'S'), LayoutCond(field: 'max', op: 'empty')]),
            ]),
            value: LayoutExpr(concat: [LayoutExpr.field('name'), LayoutExpr.text('ok')], sep: ' - '),
          ),
        ],
        otherwise: LayoutExpr(math: 'round', args: [LayoutExpr(math: 'percent', args: [LayoutExpr.field('score'), LayoutExpr.field('max')]), LayoutExpr.number(1)]),
      ),
    ]);

void main() {
  testWidgets('no layout errors, empty and filled', (tester) async {
    await expectNoLayoutErrors(tester, () => ComputedFieldsEditorPage(doc: LayoutDocument(), fields: _fields, sampleRows: _rows, lang: AppConfig.lang), scaffold: false);
    await expectNoLayoutErrors(tester, () => ComputedFieldsEditorPage(doc: _doc(), fields: _fields, sampleRows: _rows, lang: AppConfig.lang), scaffold: false);
  });

  testWidgets('the Pass / Fail preset, a new threshold, and save', (tester) async {
    AppConfig.lang = 'en';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final doc = LayoutDocument();
    bool? result;
    await tester.pumpWidget(layoutHost(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const ValueKey('open'),
            onPressed: () async => result = await showComputedFieldsEditor(context, doc: doc, fields: _fields, sampleRows: _rows, lang: 'en'),
            child: const Text('open'),
          ),
        ),
      ),
      scale: 1.0,
    ));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('cc-preset-pass_fail')));
    await tester.pump(const Duration(milliseconds: 300));

    String shown(int i) => (tester.widget<Text>(find.byKey(ValueKey('cc-preview-$i')))).data!;
    expect([shown(0), shown(1), shown(2)], ['Pass', 'Pass', 'Fail']);

    await tester.enterText(find.byKey(const ValueKey('cc-cond-value-0-0')), '90');
    await tester.pump(const Duration(milliseconds: 300));
    expect([shown(0), shown(1), shown(2)], ['Fail', 'Fail', 'Fail']);
    await tester.enterText(find.byKey(const ValueKey('cc-cond-value-0-0')), '45');
    await tester.pump(const Duration(milliseconds: 300));
    // score 80 >= 45 pass, 40 fail, 49 pass
    expect([shown(0), shown(1), shown(2)], ['Pass', 'Fail', 'Pass']);

    await tester.tap(find.byKey(const ValueKey('cc-save')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(result, isTrue);
    expect(doc.computed.length, 1);
    expect(doc.computed.first.key, 'calc.result');
    final cond = doc.computed.first.cases.first.when.items.first as LayoutCond;
    expect(cond.value, 45);
    expect(applyComputed({'score': 44}, doc.computed)['calc.result'], 'Fail');
  });
}
