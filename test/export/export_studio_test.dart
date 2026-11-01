// Export Studio — pure parts: conditional rules (the server's matching), numerals, header / footer variables, the
// fields choice (reorder / rename / remember), templates ↔ choices (JSON round-trips), file names, page keys, the
// build pipeline per language, themes, and the designer's engine adapter.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export/export_studio_api.dart';
import 'package:flutter_education_app/design/export/export_studio_model.dart';
import 'package:flutter_education_app/design/export/table_export_choice.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export_hub/export_design.dart';
import 'package:flutter_education_app/design/export_hub/export_designer.dart' show ExportStudioAdapter, exportStudioPage;
import 'package:flutter_education_app/design/export_hub/export_flow_build.dart';
import 'package:flutter_education_app/design/export_hub/export_themes.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_table_export.dart' show orgMembersExport;
import 'package:flutter_education_app/features/shared/exports/export_schedules_page.dart'
    show exportParamChoices, exportParamIsFlag, exportPeopleRoles, exportRolesOf;
import 'package:flutter_test/flutter_test.dart';

import '../support/disk_fonts.dart';

Map<String, String> unzip(Uint8List bytes) => {for (final f in ZipDecoder().decodeBytes(bytes)) if (f.isFile) f.name: f.name.endsWith('.odttf') || f.name.endsWith('.png') ? '<binary ${f.content.length}>' : utf8.decode(f.content)};

const cols = [
  AppExportColumn('name', 'Name', locked: true, labels: {'ar': 'الاسم', 'en': 'Name'}),
  AppExportColumn('dept', 'Department', labels: {'ar': 'القسم', 'en': 'Department'}),
  AppExportColumn('score', 'Score', type: AppColType.number, total: AppTotal.average),
  AppExportColumn('status', 'Status', type: AppColType.status, statusLabels: {'late': 'Late', 'ok': 'On time'}),
  AppExportColumn('notes', 'Notes', visible: false),
];

AppTableExport table({List<Map<String, Object?>>? selected}) => AppTableExport(
      id: 'Admin.Students List',
      title: 'Students: term 1',
      brand: 'Al Noor',
      columns: cols,
      generatedAt: DateTime.utc(2026, 10, 31, 9),
      rows: [
        for (var i = 0; i < 6; i++) {'name': 'S$i', 'dept': i.isEven ? 'CS' : 'Math', 'score': 40 + i * 10, 'status': i == 2 ? 'late' : 'ok', 'notes': i == 0 ? '' : 'n$i'},
      ],
      selectedRows: selected,
    );

void main() {
  useDiskFonts();
  setUp(() => AppConfig.lang = 'en');

  group('rules (the server\'s rule_matches)', () {
    final row = <String, Object?>{'score': 55, 'name': 'Sara Ali', 'status': 'Late', 'empty': '  ', 'n': '1,200'};
    bool m(String field, ExportRuleOp op, [Object? v]) => exportRuleMatches(ExportRule(field: field, op: op, value: v, style: ExportRuleStyle(bold: true)), row);

    test('numbers compare as numbers, text = / ≠ case-insensitively, order ops never match text', () {
      expect(m('score', ExportRuleOp.lt, 60), isTrue);
      expect(m('score', ExportRuleOp.ge, '55'), isTrue);
      expect(m('score', ExportRuleOp.gt, 55), isFalse);
      expect(m('n', ExportRuleOp.eq, 1200), isTrue);
      expect(m('status', ExportRuleOp.eq, 'late'), isTrue);
      expect(m('status', ExportRuleOp.ne, 'late'), isFalse);
      expect(m('status', ExportRuleOp.gt, 'a'), isFalse);
    });

    test('contains, empty, not empty; a blank cell matches only "empty"', () {
      expect(m('name', ExportRuleOp.contains, 'ALI'), isTrue);
      expect(m('empty', ExportRuleOp.empty), isTrue);
      expect(m('missing', ExportRuleOp.empty), isTrue);
      expect(m('name', ExportRuleOp.notEmpty), isTrue);
      expect(m('empty', ExportRuleOp.eq, ''), isFalse);
      expect(m('empty', ExportRuleOp.ne, 'x'), isFalse);
    });

    test('first matching rule per field wins; hide drops the row; style-less rules do nothing', () {
      final rules = [
        ExportRule(field: 'score', op: ExportRuleOp.lt, value: 60, style: ExportRuleStyle(color: 'B91C1C')),
        ExportRule(field: 'score', op: ExportRuleOp.lt, value: 100, style: ExportRuleStyle(background: 'FFF4DB')),
        ExportRule(field: 'name', op: ExportRuleOp.notEmpty),
      ];
      final look = exportRowLook(rules, row);
      expect(look.of('score')!.color, 'B91C1C');
      expect(look.of('score')!.background, isNull);
      expect(look.of('name'), isNull);
      final hide = [ExportRule(field: 'status', op: ExportRuleOp.eq, value: 'late', style: ExportRuleStyle(hide: true))];
      expect(exportRowLook(hide, row).hidden, isTrue);
      expect(exportVisibleRows(hide, [row, {'status': 'ok'}]).length, 1);
    });

    test('a label prints instead of the value', () {
      final look = exportRowLook([ExportRule(field: 'score', op: ExportRuleOp.lt, value: 60, style: ExportRuleStyle(label: 'Fail'))], row);
      expect(look.textOf('score', '55'), 'Fail');
      expect(look.textOf('name', 'Sara Ali'), 'Sara Ali');
    });

    test('JSON is the server\'s shape and accepts its aliases', () {
      final r = ExportRule(field: 'score', op: ExportRuleOp.ge, value: 50, style: ExportRuleStyle(color: '1e40af', background: '#fff4db', bold: true, label: 'OK'));
      final j = r.toJson();
      expect(j['op'], '>=');
      expect((j['style'] as Map)['background'], '#FFF4DB');
      final back = ExportRule.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>);
      expect(back.op, ExportRuleOp.ge);
      expect(back.style.color, '1E40AF');
      expect(back.style.bold, isTrue);
      for (final (alias, op) in [('≠', ExportRuleOp.ne), ('<>', ExportRuleOp.ne), ('≤', ExportRuleOp.le), ('not empty', ExportRuleOp.notEmpty), ('filled', ExportRuleOp.notEmpty)]) {
        expect(ExportRuleOp.parse(alias), op);
      }
      expect(ExportRule.fromJson({'field': 'x', 'op': 'empty', 'value': 3}).toJson()['value'], isNull);
      expect(ExportRule.listFromJson([{'field': ''}, 'junk', {'field': 'a', 'op': '='}]).length, 1);
    });
  });

  group('numerals', () {
    test('Arabic-Indic digits and percent only when asked; English is always Western', () {
      expect(exportDigits('Score 95% · 2026-10-31', ExportNumerals.arabic), 'Score ٩٥٪ · ٢٠٢٦-١٠-٣١');
      expect(exportDigits('95%', ExportNumerals.western), '95%');
      expect(exportNumeralsFor('ar', {'ar': 'arabic'}), ExportNumerals.arabic);
      expect(exportNumeralsFor('en', {'ar': 'arabic', 'en': 'arabic'}), ExportNumerals.western);
      expect(ExportNumerals.parse('junk'), ExportNumerals.western);
    });
  });

  group('header / footer variables', () {
    test('org_name, date, rows, exporter are filled; page / pages wait for the page', () {
      final ds = ExportDataset.fromTable(table(), exporter: 'Dr Mona');
      final v = ds.placeholderValues('en', now: DateTime.utc(2026, 10, 31, 9));
      final text = fillPlaceholders('{{org_name}} · {{rows}} rows · by {{exporter}} · {{date}} · {{page}}/{{pages}} · {{typo}}', v);
      expect(text, startsWith('Al Noor · 6 rows · by Dr Mona · 31 Oct 2026 · '));
      expect(text, endsWith('{{page}}/{{pages}} · {{typo}}'));
      expect(exportStudioVariables, containsAll(['org_name', 'date', 'page', 'pages', 'rows', 'exporter']));
    });
  });

  group('fields choice', () {
    test('reorder, rename per language (empty = original), select all / none keeps locked', () {
      final e = table();
      final ch = AppExportChoice.of(e, AppExportFormat.values);
      expect(ch.columns, ['name', 'dept', 'score', 'status']);
      ch.move(3, 0); // status to the top (ReorderableListView indexes)
      expect(ch.order.first, 'status');
      ch.move(0, 4); // back after score
      expect(ch.order, ['name', 'dept', 'score', 'status', 'notes']);
      ch.rename(cols[1], 'ar', 'الشعبة');
      ch.rename(cols[1], 'en', 'Department'); // same as the column's own → not stored
      expect(ch.labelOf(cols[1], 'ar'), 'الشعبة');
      expect(ch.labelOf(cols[1], 'en'), 'Department');
      expect(ch.labels['dept'], {'ar': 'الشعبة'});
      ch.rename(cols[1], 'ar', '  ');
      expect(ch.renamed('dept'), isFalse);
      ch.setAll(e, false);
      expect(ch.selected, {'name'});
      ch.setAll(e, true);
      expect(ch.selected.length, 5);
    });

    test('remembered: labels, language, numerals, group-by, totals, rows, theme survive JSON; selected rows only when the page has them', () {
      final e = table(selected: [table().rows.first]);
      final ch = AppExportChoice.of(e, AppExportFormat.values)
        ..format = AppExportFormat.pdf
        ..lang = 'both'
        ..groupBy = 'dept'
        ..totals = false
        ..rows = 'selected'
        ..theme = 'formal';
      ch.numerals['ar'] = 'arabic';
      ch.rename(cols[0], 'en', 'Student');
      final back = AppExportChoice.of(e, AppExportFormat.values, jsonDecode(jsonEncode(ch.toJson())) as Map<String, Object?>);
      expect(back.format, AppExportFormat.pdf);
      expect(back.languages, ['ar', 'en']);
      expect(back.numeralsFor('ar'), ExportNumerals.arabic);
      expect(back.groupByFor(e), 'dept');
      expect(back.totals, isFalse);
      expect(back.rows, 'selected');
      expect(back.theme, 'formal');
      expect(back.labelOf(cols[0], 'en'), 'Student');
      final noSel = AppExportChoice.of(table(), AppExportFormat.values, ch.toJson());
      expect(noSel.rows, 'all');
      // '' = no grouping on a table that groups by itself
      final grouped = table().copyWith(groupBy: 'dept');
      expect((AppExportChoice.of(grouped, AppExportFormat.values)..groupBy = '').groupByFor(grouped), isNull);
    });
  });

  group('templates', () {
    test('columns / rules / options round-trip through a template', () {
      final e = table();
      final ch = AppExportChoice.of(e, AppExportFormat.values)
        ..groupBy = 'dept'
        ..theme = 'clean';
      ch.move(2, 0);
      ch.selected.remove('dept');
      ch.rename(cols[2], 'ar', 'العلامة');
      ch.numerals['ar'] = 'arabic';
      final rules = [ExportRule(field: 'score', op: ExportRuleOp.lt, value: 50, style: ExportRuleStyle(color: 'B91C1C'))];
      final sheet = XlsxSheetOptions(headerColor: '1E3A8A', striping: false, widths: {'name': 30}, numberFormat: '#,##0', rtl: true, logoUrl: 'https://x/logo.png');
      final opts = ExportTemplateOptions(sheet: sheet, groupBy: ch.groupBy, showTotals: true, numerals: ch.numerals, theme: ch.theme).toJson(totalKeys: templateTotalKeys(e, ch));
      expect(opts['totals'], ['score']);
      expect(opts['header_color'], '#1E3A8A');
      final t = StudioTemplate.fromJson(jsonDecode(jsonEncode({
        'id': 7,
        'name': 'Mine',
        'scope': 'org',
        'org_id': 3,
        'page_key': exportPageKey(e.id),
        'format': 'xlsx',
        'lang': 'ar',
        'design': <String, Object?>{},
        'columns': templateColumns(e, ch, widths: sheet.widths),
        'rules': ExportRule.listToJson(rules),
        'options': opts,
      })) as Map<String, dynamic>);
      expect(t.isOrg, isTrue);
      expect(templateDesign(t), isNull);
      final fresh = AppExportChoice.of(e, AppExportFormat.values);
      final freshRules = <ExportRule>[];
      final o = applyTemplate(t, e, fresh, freshRules);
      expect(fresh.order.take(2), ['score', 'name']);
      // the group column is saved unhidden (the server refuses a group on a hidden column), so it comes back ticked
      expect(fresh.selected.contains('dept'), isTrue);
      expect(fresh.labelOf(cols[2], 'ar'), 'العلامة');
      expect(fresh.groupBy, 'dept');
      expect(fresh.theme, 'clean');
      expect(fresh.numeralsFor('ar'), ExportNumerals.arabic);
      expect(freshRules.single.style.color, 'B91C1C');
      expect(o.sheet.headerColor, '1E3A8A');
      expect(o.sheet.striping, isFalse);
      expect(o.sheet.widths['name'], 30);
      expect(o.sheet.numberFormat, '#,##0');
      expect(o.sheet.rtl, isTrue);
      expect(o.sheet.logoUrl, 'https://x/logo.png');
    });

    // the server's apply_body checks (back/services/export_templates.py): rules / group / totals only on printed columns
    List<String> serverRefuses(List<Map<String, dynamic>> columns, List<ExportRule> rules, Map<String, dynamic> options) {
      final printed = {for (final c in columns) if (c['hidden'] != true) '${c['key']}'};
      return [
        for (final r in rules) if (!printed.contains(r.field)) r.field,
        if ('${options['group_by'] ?? ''}'.isNotEmpty && !printed.contains(options['group_by'])) '${options['group_by']}',
        for (final k in (options['totals'] as List? ?? const [])) if (!printed.contains(k)) '$k',
      ];
    }

    StudioTemplate saved(AppTableExport e, AppExportChoice ch, List<ExportRule> rules, {String lang = 'ar', Map<String, dynamic> design = const {}}) =>
        StudioTemplate.fromJson(jsonDecode(jsonEncode({
          'id': 9,
          'name': 'T',
          'format': 'pdf',
          'lang': lang,
          'design': design,
          'columns': templateColumns(e, ch),
          'rules': ExportRule.listToJson(templateRules(e, ch, rules).kept),
          'options': ExportTemplateOptions(groupBy: ch.groupByFor(e) ?? '', showTotals: ch.totals).toJson(totalKeys: templateTotalKeys(e, ch)),
        })) as Map<String, dynamic>);

    test('a template saved with "No grouping" clears the page\'s default group when applied', () {
      final e = table().copyWith(groupBy: 'dept');
      final ch = AppExportChoice.of(e, AppExportFormat.values)..groupBy = '';
      expect(ch.groupByFor(e), isNull);
      final t = saved(e, ch, const []);
      expect(t.options['group_by'], '');
      expect(ExportTemplateOptions.fromJson(t.options).groupBy, '');
      final fresh = AppExportChoice.of(e, AppExportFormat.values);
      expect(fresh.groupByFor(e), 'dept');
      applyTemplate(t, e, fresh, []);
      expect(fresh.groupByFor(e), isNull);
      // an older template without the key keeps the page's default
      expect(ExportTemplateOptions.fromJson(const {}).groupBy, isNull);
    });

    test('save as template: the default group column is never sent hidden; rules / grouping only on printed fields', () {
      final e = table().copyWith(groupBy: 'dept');
      final ch = AppExportChoice.of(e, AppExportFormat.values);
      // the page's group column starts unticked, and "notes" is hidden by default
      expect(ch.selected.contains('dept'), isFalse);
      expect(ch.selected.contains('notes'), isFalse);
      final offered = [for (final c in exportFlowRuleColumns(e, ch)) c.id];
      expect(offered, containsAll(['name', 'dept', 'score', 'status']));
      expect(offered, isNot(contains('notes')));
      final rules = [
        ExportRule(field: 'dept', op: ExportRuleOp.eq, value: 'CS', style: ExportRuleStyle(color: 'B91C1C')),
        ExportRule(field: 'notes', op: ExportRuleOp.empty, style: ExportRuleStyle(color: 'B91C1C')),
      ];
      final split = templateRules(e, ch, rules);
      expect([for (final r in split.kept) r.field], ['dept']);
      expect([for (final r in split.stray) r.field], ['notes']);
      final t = saved(e, ch, rules);
      expect(serverRefuses(t.columns, t.rules, t.options), isEmpty);
      expect(t.options['group_by'], 'dept');
      // applied again: the page's group column stays unticked, as by default
      final fresh = AppExportChoice.of(e, AppExportFormat.values);
      applyTemplate(t, e, fresh, []);
      expect(fresh.selected.contains('dept'), isFalse);
      expect(fresh.groupByFor(e), 'dept');
    });

    test('a template for both languages is ONE template carrying each language\'s design', () {
      final ar = exportThemeDesign('formal', 'ar')!, en = exportThemeDesign('clean', 'en')!;
      final j = templateDesignJson({'ar': ar, 'en': en});
      final e = table();
      final t = saved(e, AppExportChoice.of(e, AppExportFormat.values)..lang = 'both', const [], lang: 'both', design: j);
      expect(t.lang, 'both');
      expect(templateDesign(t, 'ar')!.toJson(), ar.toJson());
      expect(templateDesign(t, 'en')!.toJson(), en.toJson());
      // the top-level design (what the server renders) is the Arabic one
      expect(templateDesign(t)!.toJson(), ar.toJson());
      // Standard for one language = no design for it
      final half = StudioTemplate.fromJson(jsonDecode(jsonEncode({'id': 1, 'name': 'x', 'lang': 'both', 'design': templateDesignJson({'ar': null, 'en': en})})) as Map<String, dynamic>);
      expect(templateDesign(half, 'ar'), isNull);
      expect(templateDesign(half, 'en')!.toJson(), en.toJson());
      // one language: its design, unchanged
      expect(templateDesignJson({'ar': ar}), ar.toJson());
      expect(templateDesignJson({'en': null}), isEmpty);
    });

    test('remembered rules and studio designs are ignored while export.studio is switched off', () {
      final e = table();
      final prefs = <String, Object?>{
        'ru': ExportRule.listToJson([ExportRule(field: 'status', op: ExportRuleOp.eq, value: 'late', style: ExportRuleStyle(hide: true))]),
        'dz': {'pdf.ar': exportThemeDesign('formal', 'ar')!.toJson()},
      };
      final on = exportFlowStoredStudio(prefs, e, studioOn: true);
      expect(on.rules.single.style.hide, isTrue);
      expect(on.designs.keys, ['pdf.ar']);
      final off = exportFlowStoredStudio(prefs, e, studioOn: false);
      expect(off.rules, isEmpty);
      expect(off.designs, isEmpty);
    });

    test('a design with blocks is a template design; v2 JSON with frame and watermark round-trips', () {
      final d = exportThemeDesign('formal', 'ar')!
        ..watermark.text = 'سري'
        ..blocks.first.background = 'F1F5F9';
      final j = jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>;
      expect(j['version'], 2);
      final t = StudioTemplate.fromJson({'id': 1, 'name': 'x', 'design': j});
      final back = templateDesign(t)!;
      expect(back.frame.style, 'double');
      expect(back.watermark.text, 'سري');
      expect(back.blocks.first.background, 'F1F5F9');
      expect(back.toJson(), d.toJson());
      // an older app's design without the new keys still reads
      expect(ExportDesign.fromJson({'blocks': []}).frame.visible, isFalse);
    });

    test('themes: standard is the table writers (no design), the others differ per language; sheets per theme', () {
      expect(exportThemeDesign('standard', 'ar'), isNull);
      for (final id in ['clean', 'formal', 'colorful']) {
        final ar = exportThemeDesign(id, 'ar')!, en = exportThemeDesign(id, 'en')!;
        expect(ar.rtl, isTrue);
        expect(en.rtl, isFalse);
        expect(ar.tableBlock, isNotNull);
        expect(exportThemeSheet(id).toJson(), isNot(XlsxSheetOptions().toJson()));
      }
    });
  });

  group('names and keys', () {
    test('file name: <title>_<yyyy-MM-dd>.<ext>, unsafe characters replaced, language suffix for two files', () {
      final now = DateTime.utc(2026, 10, 31, 9);
      expect(exportFileName('Students: term 1', 'pdf', now: now), 'Students_ term 1_2026-10-31.pdf');
      expect(exportFileName('  ', 'xlsx', now: now), 'export_2026-10-31.xlsx');
      expect(exportFileName('تقرير الطلاب', 'docx', now: now, lang: 'ar'), 'تقرير الطلاب_2026-10-31_ar.docx');
      expect(exportSizeLabel(2048), '2 KB');
      expect(exportSizeLabel(3 * 1024 * 1024 + 1), '3.0 MB');
    });

    test('page key follows the server pattern; link tokens parse from the route', () {
      expect(exportPageKey('Admin.Students List'), 'admin.students_list');
      expect(exportPageKey('__x'), 'x');
      expect(RegExp(r'^[a-z0-9][a-z0-9_.:/-]{0,79}$').hasMatch(exportPageKey('ÄÖ ' * 40)), isTrue);
      expect(exportLinkTokenFromRoute('/e/abcDEF123_-xyz'), 'abcDEF123_-xyz');
      expect(exportLinkTokenFromRoute('/e/abcDEF123?x=1'), 'abcDEF123');
      expect(exportLinkTokenFromRoute('/e/short'), isNull);
      expect(exportLinkTokenFromRoute('/c/12'), isNull);
    });
  });

  group('build pipeline', () {
    test('a variant per language: headers in that language (renames first), direction, selected rows, grouping', () {
      final e = table(selected: [table().rows[1], table().rows[2]]);
      final ch = AppExportChoice.of(e, AppExportFormat.values)
        ..rows = 'selected'
        ..groupBy = 'dept';
      ch.rename(cols[0], 'ar', 'الطالب');
      final ar = exportFlowVariant(e, ch, 'ar'), en = exportFlowVariant(e, ch, 'en');
      expect(ar.rtl, isTrue);
      expect(ar.column('name')!.label, 'الطالب');
      expect(ar.column('dept')!.label, 'القسم');
      expect(en.column('name')!.label, 'Name');
      expect(ar.rows.length, 2);
      expect(ar.groupBy, 'dept');
      expect(exportFlowColumns(ar, ch), isNot(contains('dept')));
      expect(ExportDataset.fromTable(ar).column('name')!.labelAr, 'الطالب');
    });

    test('Excel for both languages: two files, named per language, rules hide a row and colour a cell', () async {
      final e = table();
      final ch = AppExportChoice.of(e, AppExportFormat.values)
        ..format = AppExportFormat.xlsx
        ..lang = 'both';
      final job = ExportFlowJob(
        source: e,
        format: AppExportFormat.xlsx,
        choice: ch,
        now: DateTime.utc(2026, 10, 31, 9),
        rules: [
          ExportRule(field: 'status', op: ExportRuleOp.eq, value: 'late', style: ExportRuleStyle(hide: true)),
          ExportRule(field: 'score', op: ExportRuleOp.lt, value: 60, style: ExportRuleStyle(background: 'FDE7E7')),
        ],
      );
      expect(job.rowCount, 5);
      final ar = await buildExportFlowFile(job, 'ar'), en = await buildExportFlowFile(job, 'en');
      expect(ar.name, 'Students_ term 1_2026-10-31_ar.xlsx');
      expect(en.name, endsWith('_en.xlsx'));
      final sheetAr = unzip(ar.bytes)['xl/worksheets/sheet1.xml']!;
      expect(sheetAr, contains('rightToLeft="1"'));
      expect(sheetAr, contains('الاسم'));
      expect(sheetAr, isNot(contains('>S2<')));
      expect(unzip(ar.bytes)['xl/styles.xml'], contains('FFFDE7E7'));
      expect(unzip(en.bytes)['xl/worksheets/sheet1.xml'], isNot(contains('rightToLeft="1"')));
    });

    // QA 2026-10-31: the English file of a "Both" export in the Arabic app carried "أُنشئ 31 أكتوبر 2026".
    test('Excel for both languages: the stamp and dates follow the file language, the app language is kept', () async {
      AppConfig.lang = 'ar';
      final e = table();
      final ch = AppExportChoice.of(e, AppExportFormat.values)
        ..format = AppExportFormat.xlsx
        ..lang = 'both';
      final job = ExportFlowJob(source: e, format: AppExportFormat.xlsx, choice: ch, now: DateTime.utc(2026, 10, 31, 9));
      final en = unzip((await buildExportFlowFile(job, 'en')).bytes).values.join();
      final ar = unzip((await buildExportFlowFile(job, 'ar')).bytes).values.join();
      expect(en, contains('Generated'));
      expect(en, isNot(contains('أُنشئ')));
      expect(ar, contains('أُنشئ'));
      expect(AppConfig.lang, 'ar');
    });

    test('Word: Standard goes through the table writer, a theme through the designed writer with the same choices', () async {
      final e = table();
      final ch = AppExportChoice.of(e, AppExportFormat.values)
        ..format = AppExportFormat.docx
        ..lang = 'ar';
      ch.numerals['ar'] = 'arabic';
      final std = await buildExportFlowFile(ExportFlowJob(source: e, format: AppExportFormat.docx, choice: ch), 'ar');
      expect(unzip(std.bytes)['word/document.xml'], contains('٤٠'));
      final themed = await buildExportFlowFile(
          ExportFlowJob(source: e, format: AppExportFormat.docx, choice: ch, designs: {'ar': exportThemeDesign('formal', 'ar')}), 'ar');
      final files = unzip(themed.bytes);
      expect(files['word/document.xml'], contains('w:pgBorders'));
      expect(files['word/document.xml'], contains('الاسم'));
    });
  });

  group('designer engine adapter', () {
    test('blocks ↔ items in mm of the content box, clone gets a new id, copies of the table are dropped, undo restores', () {
      var d = exportThemeDesign('clean', 'en')!;
      final adapter = ExportStudioAdapter(() => d, (x) => d = x);
      final ctl = StudioController<ExportBlock>(adapter: adapter, page: exportStudioPage(d));
      final (w, h) = d.page.contentMm;
      final title = ctl.items.first;
      expect(title.rect.width, closeTo(d.blocks.first.w * w, 1e-9));
      expect(ctl.page.unitPx, closeTo(96 / 25.4, 1e-9));
      ctl.select(title.id);
      ctl.nudge(1, 0, big: true);
      expect(d.blocks.first.x * w, closeTo(title.rect.left + ctl.nudgeBigStep, 1e-6));
      ctl.undo();
      expect(d.blocks.first.x, closeTo(0, 1e-9));
      final before = d.blocks.length;
      ctl.select(d.tableBlock!.id);
      ctl.duplicate();
      expect(d.blocks.length, before); // one table per page
      ctl.select(d.blocks.first.id);
      ctl.duplicate();
      expect(d.blocks.length, before + 1);
      expect(d.blocks.map((b) => b.id).toSet().length, d.blocks.length);
      adapter.writeRects({d.blocks.first.id: Rect.fromLTWH(-50, 0, w * 3, 10)});
      expect(d.blocks.first.w, 1); // clamped into the content box
      ctl.dispose();
    });
  });

  group('bilingual tables (English headers in the Arabic app)', () {
    AppTableExport build() => AppTableExport(
          id: 'org.attendance',
          title: t('الحضور', 'Attendance'),
          columns: [
            AppExportColumn('name', t('الطالب', 'Student'), locked: true),
            AppExportColumn('code', t('الرقم', 'ID'), labels: const {'ar': 'الكود', 'en': 'Code'}),
            AppExportColumn('status', t('الحالة', 'Status'), type: AppColType.status, statusLabels: {'ok': t('حاضر', 'Present')}),
          ],
          rows: const [
            {'name': 'Sara', 'code': '7', 'status': 'ok'},
          ],
          orgId: 5,
        );

    test('one build per language: both headers, status texts and titles; the app language is restored', () {
      AppConfig.lang = 'ar';
      final e = bilingualExport(build);
      expect(AppConfig.lang, 'ar');
      expect(e.title, 'الحضور');
      expect(e.titles, {'ar': 'الحضور', 'en': 'Attendance'});
      expect(e.column('name')!.labels, {'ar': 'الطالب', 'en': 'Student'});
      expect(e.column('code')!.labels, {'ar': 'الكود', 'en': 'Code'}); // the caller's own labels win
      expect(e.column('status')!.statusLabelsByLang, {
        'ar': {'ok': 'حاضر'},
        'en': {'ok': 'Present'},
      });
      expect(e.orgId, 5);
    });

    test('the English variant prints the English title, headers and status text', () {
      AppConfig.lang = 'ar';
      final e = bilingualExport(build);
      final ch = AppExportChoice.of(e, AppExportFormat.values);
      final en = exportFlowVariant(e, ch, 'en'), ar = exportFlowVariant(e, ch, 'ar');
      expect(en.title, 'Attendance');
      expect(en.column('name')!.label, 'Student');
      expect(en.column('status')!.statusLabels, {'ok': 'Present'});
      expect(ar.title, 'الحضور');
      expect(ar.column('status')!.statusLabels, {'ok': 'حاضر'});
    });

    test('the paged-list export keeps the organization and the server dataset (Schedule / Share link)', () {
      AppConfig.lang = 'ar';
      final e = bilingualExport(() => orgMembersExport('students', const [], orgId: 9, roles: 'student', status: 'active'));
      final sent = e.copyWith(filters: {...e.filters, 'x': 'y'});
      expect(sent.orgId, 9);
      expect(sent.serverDataset, 'org.people');
      expect(sent.serverParams, {'org_id': 9, 'roles': 'student', 'status': 'active'});
      expect(sent.titles?['en'], 'Students');
      expect(sent.filters['x'], 'y');
    });
  });

  group('schedule form parameters', () {
    test('roles are picked from the server\'s list; status / lang are fixed choices; flags are switches', () {
      expect(exportRolesOf(' student, teacher ,'), {'student', 'teacher'});
      expect(exportRolesOf(null), isEmpty);
      expect(exportPeopleRoles, containsAll(['student', 'teacher', 'teacher_assistant', 'admin_assistant']));
      expect(exportParamChoices('org.people', 'status')!.first.$1, 'active'); // the server's default first
      expect(exportParamChoices('org.complaints', 'status')!.map((c) => c.$1), ['', 'open', 'in_progress', 'resolved', 'closed']);
      expect(exportParamChoices('gov.items', 'lang')!.map((c) => c.$1), ['ar', 'en']);
      expect(exportParamChoices('org.people', 'org_id'), isNull);
      expect(exportParamIsFlag('include_dropped'), isTrue);
      expect(exportParamIsFlag('overdue'), isTrue);
      expect(exportParamIsFlag('status'), isFalse);
    });
  });
}
