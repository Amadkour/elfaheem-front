// Export Studio through the layout harness (320×640 and 1400×900, ar / en, text ×1.3): every step of the flow (the
// sheet on a phone, the dialog with the live preview on a wide window), the done state, the Excel studio, the rule
// builder, the field picker with many long fields, the sheet preview, the designer on the engine, and the pages'
// hub. The pages themselves (log, schedules, links, link open) are covered in export_pages_layout_test.dart.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export/export_job.dart' show exportUseIsolates;
import 'package:flutter_education_app/design/export/export_studio_model.dart';
import 'package:flutter_education_app/design/export/table_export_choice.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export_hub/export_design.dart';
import 'package:flutter_education_app/design/export_hub/export_designer.dart';
import 'package:flutter_education_app/design/export_hub/export_flow.dart';
import 'package:flutter_education_app/design/export_hub/export_flow_parts.dart';
import 'package:flutter_education_app/design/export_hub/export_sheet_studio.dart';
import 'package:flutter_education_app/design/export_hub/export_themes.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_education_app/features/exports/exports_center_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

const longAr = 'اسم طويل جدًا لعمود في تقرير شؤون الطلاب للفصل الدراسي الأول';
const longEn = 'A very long column name in the first-term student affairs report';

AppTableExport sample({int columns = 9, bool selection = true}) {
  final rows = [
    for (var i = 0; i < 30; i++)
      {
        'name': i.isEven ? longAr : longEn,
        'score': 30 + i * 2,
        'amount': 1000 + i * 12.5,
        'status': i % 3 == 0 ? 'late' : 'ok',
        'joined': '2026-10-${10 + i % 18}',
        for (var c = 0; c < columns; c++) 'c$c': '$longEn $i',
      },
  ];
  return AppTableExport(
    id: 'layout.studio',
    title: '$longAr — $longEn',
    brand: longEn,
    filters: const {'Status': 'All'},
    columns: [
      const AppExportColumn('name', 'Name', locked: true, labels: {'ar': 'الاسم الكامل للطالب', 'en': 'Full student name'}),
      const AppExportColumn('score', 'Score', type: AppColType.percent, total: AppTotal.average),
      const AppExportColumn('amount', 'Paid', type: AppColType.money, currency: 'EGP', total: AppTotal.sum),
      const AppExportColumn('status', 'Status', type: AppColType.status, statusLabels: {'late': 'Late', 'ok': 'On time'}),
      const AppExportColumn('joined', 'Joined', type: AppColType.date),
      for (var c = 0; c < columns; c++) AppExportColumn('c$c', '$longEn $c', labels: {'ar': '$longAr $c'}),
    ],
    rows: rows,
    selectedRows: selection ? rows.take(4).toList() : null,
  );
}

final rules = [
  ExportRule(field: 'score', op: ExportRuleOp.lt, value: 50, style: ExportRuleStyle(color: 'B91C1C', bold: true, label: 'Needs help')),
  ExportRule(field: 'status', op: ExportRuleOp.eq, value: 'late', style: ExportRuleStyle(background: 'FFF4DB')),
  ExportRule(field: 'c1', op: ExportRuleOp.empty, style: ExportRuleStyle(hide: true)),
];

/// The flow as it is shown: the dialog layout from 980 px, the bottom-sheet layout below.
Widget flow(int step, {AppTableExport? export, List<String>? saved}) => LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 980;
      final sheet = ExportFlowSheet(export: export ?? sample(), remote: false, wide: wide, initialStep: step, saveFile: (_, name, _) async => saved?.add(name));
      if (wide) return Center(child: SizedBox(width: 1120, height: box.maxHeight - 48, child: sheet));
      return Align(alignment: Alignment.bottomCenter, child: ConstrainedBox(constraints: BoxConstraints(maxHeight: box.maxHeight * .92), child: sheet));
    });

void main() {
  // widget tests run in a fake-async zone that isolate messages never reach: the writer runs inline, as on the web
  setUpAll(() => exportUseIsolates = false);
  tearDownAll(() => exportUseIsolates = true);
  setUp(() {
    AppConfig.disableList = [];
    SharedPreferences.setMockInitialValues({});
  });

  for (final (format, theme) in [('pdf', 'formal'), ('xlsx', 'colorful'), ('docx', 'standard')]) {
    testWidgets('flow: every step ($format, both languages, rules, theme $theme)', (tester) async {
      for (var step = 0; step < 5; step++) {
        SharedPreferences.setMockInitialValues({
          'app_table_export.v1.layout.studio': jsonEncode({'f': format, 'g': 'both', 'th': theme, 'gb': 'status', 'r': 'selected', 'n': {'ar': 'arabic'}, 'ru': ExportRule.listToJson(rules)}),
        });
        await expectNoLayoutErrors(tester, () => flow(step));
      }
    });
  }

  testWidgets('flow: Quick export taps through to the done state (no server, nothing written to disk)', (tester) async {
    final saved = <String>[];
    await expectNoLayoutErrors(
      tester,
      () => flow(0, export: sample(columns: 2, selection: false), saved: saved),
      act: (tester) async {
        final quick = find.textContaining(AppConfig.lang == 'ar' ? 'تصدير سريع' : 'Quick export');
        if (quick.evaluate().isNotEmpty) await tester.tap(quick.first, warnIfMissed: false);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        for (var i = 0; i < 10 && saved.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
    expect(saved, isNotEmpty);
    expect(saved.every((n) => RegExp(r'_\d{4}-\d{2}-\d{2}\.xlsx$').hasMatch(n)), isTrue, reason: '$saved');
  });

  testWidgets('field picker: many long fields, renamed and locked ones, search', (tester) async {
    final e = sample(columns: 14);
    final ch = AppExportChoice.of(e, AppExportFormat.values);
    ch.rename(e.columns[1], 'en', 'Final score');
    ch.groupBy = 'status';
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: ExportFieldPicker(export: e, choice: ch, lang: AppConfig.lang, onChanged: () {})));
  });

  testWidgets('language picker and theme cards', (tester) async {
    final e = sample();
    final ch = AppExportChoice.of(e, AppExportFormat.values)..lang = 'both';
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          ExportLanguagePicker(export: e, choice: ch, onChanged: () {}),
          const SizedBox(height: 16),
          Row(children: [
            for (final id in exportThemeIds)
              Expanded(
                child: ExportThemeCard(
                  title: exportThemeLabel(id),
                  hint: exportThemeHint(id),
                  selected: id == 'clean',
                  onTap: () {},
                  thumbnail: ExportPagePreview(design: exportThemeDesign(id, AppConfig.lang) ?? ExportDesign.standard('table', AppConfig.lang), dataset: ExportDataset.fromTable(e), maxWidth: 60),
                ),
              ),
          ]),
        ]),
      ),
    );
  });

  testWidgets('rule builder: three rules (status dropdown, empty, hide) and the empty state', (tester) async {
    final e = sample();
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                ExportRuleBuilder(columns: e.columns, labelOf: (c) => c.labelIn(AppConfig.lang), rules: [for (final r in rules) r.copy()], onChanged: () {}),
                const SizedBox(height: 16),
                ExportRuleBuilder(columns: e.columns, labelOf: (c) => c.label, rules: [], onChanged: () {}),
              ]),
            ));
  });

  testWidgets('sheet preview and the Excel studio', (tester) async {
    final e = sample();
    final sheet = exportThemeSheet('colorful')
      ..title = '{{title}} · {{org_name}}'
      ..logoUrl = 'https://x/logo.png'
      ..widths['name'] = 40;
    await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: [ExportSheetPreview(export: e, columns: e.defaultColumns, sheet: sheet, rules: rules, numerals: ExportNumerals.arabic)]));
    await expectNoLayoutErrors(tester, () => ExportSheetStudioPage(export: e, columns: e.defaultColumns, sheet: sheet, rules: rules, orgId: 3), scaffold: false);
  });

  testWidgets('designer on the engine: formal theme with a frame and a watermark, the panel tabs', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () {
        final d = exportThemeDesign('formal', AppConfig.lang)!..watermark.text = 'CONFIDENTIAL';
        return ExportDesignerPage(design: d, dataset: ExportDataset.fromTable(sample()), module: 'table', lang: AppConfig.lang, askName: false, saveLabel: 'Use', onSave: (_, _) async => true);
      },
      scaffold: false,
      act: (tester) async {
        for (final label in const ['المتابعة على أي حال', 'Continue anyway']) {
          final go = find.text(label);
          if (go.evaluate().isNotEmpty) await tester.tap(go.first, warnIfMissed: false);
        }
        await tester.pump(const Duration(milliseconds: 100));
        for (final label in const ['الجدول', 'Table', 'العنصر', 'Element']) {
          final tab = find.text(label);
          if (tab.evaluate().isNotEmpty) await tester.tap(tab.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
    );
  });

  testWidgets('designer: one selection shows its properties in the docked panel (no sheet); a text block edits in place', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () {
        final d = exportThemeDesign('formal', AppConfig.lang)!;
        return ExportDesignerPage(design: d, dataset: ExportDataset.fromTable(sample()), module: 'table', lang: AppConfig.lang, askName: false, saveLabel: 'Use', onSave: (_, _) async => true);
      },
      scaffold: false,
      act: (tester) async {
        // the phone's "works best on a larger screen" gate (its key when the test loads no translations)
        for (final label in const ['المتابعة على أي حال', 'Continue anyway', 'studio_small_continue']) {
          final go = find.text(label);
          if (go.evaluate().isNotEmpty) await tester.tap(go.first, warnIfMissed: false);
        }
        await tester.pump(const Duration(milliseconds: 100));
        final ctl = tester.widget<StudioCanvas<ExportBlock>>(find.byType(StudioCanvas<ExportBlock>)).controller;
        final text = ctl.items.firstWhere((i) => i.payload.kind == 'text');
        ctl.select(text.id);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text(exportBlockLabels()['text']!), findsWidgets);
        expect(ctl.startTextEdit(text.id), isTrue);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const ValueKey('studio-inline-editor')), findsOneWidget);
      },
    );
  });

  testWidgets('pages hub (admin)', (tester) async {
    await expectNoLayoutErrors(tester, () => const ExportsCenterPage(admin: true), scaffold: false);
  });
}
