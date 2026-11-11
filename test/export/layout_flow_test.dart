// The v3 export page (D-142) against a fake layout server (FakeApi): stepping through list / table / custom, the
// rule builder, the item browser, templates (save with schema_version 3, load in one click, v2 ones left out), the
// background run (progress → download, cancel, failure), the rows source (upload vs dataset), the local draft, and
// the kill switch falling back to the older flow.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_table_export.dart';
import 'package:flutter_education_app/design/export_hub/export_flow.dart' show ExportFlowSheet;
import 'package:flutter_education_app/design/export/export_studio_api.dart' show ExportResult;
import 'package:flutter_education_app/design/export_layout/layout_api.dart';
import 'package:flutter_education_app/design/export_layout/layout_logic.dart';
import 'package:flutter_education_app/design/export_layout/layout_canvas.dart';
import 'package:flutter_education_app/design/export_layout/layout_flow_controller.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_education_app/design/export_layout/layout_page.dart';
import 'package:flutter_education_app/design/export_layout/layout_props.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_fake.dart';

Widget _host(Widget child) => ThemeConfigScope(
      provider: ThemeConfigProvider(api: ApiClient()),
      child: MaterialApp(debugShowCheckedModeBanner: false, home: child),
    );

Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _until(WidgetTester tester, bool Function() done, {int max = 80, Duration step = const Duration(milliseconds: 250)}) async {
  for (var i = 0; i < max && !done(); i++) {
    await tester.pump(step);
  }
  expect(done(), isTrue, reason: 'condition not reached');
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester, 3);
}

void main() {
  late FakeApi api;
  late LayoutFakeServer server;
  final saved = <(String, int)>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    saved.clear();
    server = LayoutFakeServer();
    api = FakeApi(server.routes(), latency: const Duration(milliseconds: 20))..install();
  });
  tearDown(() => api.uninstall());

  Future<void> open(WidgetTester tester, {int step = 0, AppTableExport? export, Size size = const Size(1400, 900)}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(ExportLayoutPage(
      export: export ?? layoutTestExport(),
      liveStream: kNoStream,
      initialStep: step,
      saveFile: (bytes, name, mime) async => saved.add((name, bytes.length)),
    )));
    await _settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('steps: start → layout (list, table, cards, grid) → design with the canvas and the item browser', (tester) async {
    await open(tester);
    expect(find.text('File format'), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-gallery')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('layout-format-docx')));
    await _tap(tester, find.byKey(const ValueKey('layout-lang-both')));
    await _tap(tester, find.byKey(const ValueKey('layout-customize')));
    expect(find.text('How do you want to lay the items out?'), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-tab-ar')), findsOneWidget, reason: 'two languages = two design tabs');

    await _tap(tester, find.byKey(const ValueKey('layout-kind-list')));
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.text('Fields of the line'), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-field-email')), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('layout-back')));
    await _tap(tester, find.byKey(const ValueKey('layout-kind-table')));
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.text('Table columns'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('layout-back')));
    await _tap(tester, find.byKey(const ValueKey('layout-kind-cards')));
    await _tap(tester, find.byKey(const ValueKey('layout-cards-per-line')).evaluate().isEmpty ? find.text('2') : find.descendant(of: find.byKey(const ValueKey('layout-cards-per-line')), matching: find.text('2')));
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.byType(StudioCanvas<LayoutElement>), findsOneWidget);
    expect(find.text('Item 1 of 120'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('layout-item-next')));
    await _tap(tester, find.byKey(const ValueKey('layout-item-next')));
    expect(find.text('Item 3 of 120'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('layout-item-prev')));
    expect(find.text('Item 2 of 120'), findsOneWidget);

    // the Arabic tab is its own design
    await _tap(tester, find.byKey(const ValueKey('layout-tab-ar')));
    expect(find.byType(StudioCanvas<LayoutElement>), findsOneWidget);

    // the fixed parts are one switcher away, on the same step
    expect(find.byKey(const ValueKey('layout-band-header')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('layout-band-page')));
    expect(find.byKey(const ValueKey('layout-watermark')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.byKey(const ValueKey('layout-save-template')), findsOneWidget);
    await close(tester);
  });

  testWidgets('each language keeps its canvas (and its undo history) while the tabs are switched', (tester) async {
    await open(tester, step: 2);
    final flow = (tester.state(find.byType(ExportLayoutPage)) as dynamic).flow as LayoutFlowController;
    flow.setLanguages(['ar', 'en']);
    flow.pickMode('custom');
    await _settle(tester);
    StudioController<LayoutElement> ctl() => tester.widget<StudioCanvas<LayoutElement>>(find.byType(StudioCanvas<LayoutElement>)).controller;
    final en = ctl();
    en.select(en.items.first.id);
    en.deleteSelection();
    expect(en.canUndo, isTrue);
    await _tap(tester, find.byKey(const ValueKey('layout-tab-ar')));
    expect(ctl(), isNot(same(en)));
    await _tap(tester, find.byKey(const ValueKey('layout-tab-en')));
    expect(ctl(), same(en), reason: 'the same controller: the undo history survived the switch');
    expect(en.canUndo, isTrue);
    await close(tester);
  });

  testWidgets('the rule builder: Conditional adds a rule, "Add a rule" a second, else is offered', (tester) async {
    final e = LayoutElement(id: 's', kind: 'field', w: 30, h: 6, bind: LayoutBind(field: 'score'));
    final items = [e];
    final ctl = StudioController<LayoutElement>(adapter: LayoutElementsAdapter(items, newId: () => 'n'), page: const StudioPage(100, 20));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 1400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(Scaffold(
      body: ListenableBuilder(
        listenable: ctl,
        builder: (context, _) => LayoutElementProps(
          ctl: ctl,
          element: items.first,
          fields: const [(key: 'name', label: 'Name', numeric: false), (key: 'score', label: 'Score', numeric: true)],
          upload: (_, _) async => null,
        ),
      ),
    )));
    await _settle(tester, 2);
    await _tap(tester, find.text('Conditional'));
    expect(e.type, LayoutElementType.conditional);
    expect(e.rules, hasLength(1));
    expect(find.text('Rule 1'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('layout-add-rule')));
    expect(e.rules, hasLength(2));
    expect(e.rules.last.when.single.field, 'score');
    expect(find.text('Rule 2'), findsOneWidget);
    await _tap(tester, find.text('Else'));
    expect(e.otherwise, isNotNull);
    expect(ctl.canUndo, isTrue, reason: 'every edit is an undo step');
    ctl.undo();
    expect(items.single.otherwise, isNull, reason: 'undo restores through the adapter');
    expect(items.single.rules, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    ctl.dispose();
  });

  test('the canvas adapter: Lock (context menu) and in-place text are one undo step each', () {
    final items = [LayoutElement(id: 't', kind: 'text', value: 'Name:', w: 20, h: 5), LayoutElement(id: 'f', kind: 'field', bind: LayoutBind(field: 'name'))];
    final ctl = StudioController<LayoutElement>(adapter: LayoutElementsAdapter(items, newId: () => 'n'), page: const StudioPage(100, 20));
    ctl.select('t');
    expect(ctl.canLock, isTrue);
    ctl.toggleLock();
    expect(items.first.locked, isTrue);
    expect(ctl.itemById('t')!.locked, isTrue);
    ctl.undo();
    expect(items.first.locked, isFalse);
    ctl.commitText('t', 'Student:', (item, text) => item.payload.value = text);
    expect(items.first.value, 'Student:');
    ctl.undo();
    expect(items.first.value, 'Name:');
    ctl.dispose();
  });

  testWidgets('templates: v3 ones listed (v2 left out), one click opens, save sends schema_version 4 without the source', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('layout-tpl-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-tpl-6')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('layout-tpl-5')));
    await _tap(tester, find.byKey(const ValueKey('layout-customize')));
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.text('Fields of the line'), findsOneWidget, reason: 'the template is a list design');
    expect(api.calls.where((c) => c.path == '/api/v1/exports/templates/5/used'), isNotEmpty);

    // save as a template from the preview step
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    await _settle(tester);
    await _tap(tester, find.byKey(const ValueKey('layout-save-template')));
    await tester.enterText(find.byKey(const ValueKey('layout-template-name')), 'My roster');
    await _tap(tester, find.byKey(const ValueKey('layout-template-save')));
    await _settle(tester);
    final body = server.posted['templates']!.single as Map<String, dynamic>;
    expect(body['schema_version'], 4);
    expect(body['name'], 'My roster');
    expect(body['page_key'], isNotEmpty);
    expect((body['design'] as Map)['schema_version'], 4);
    expect((body['design'] as Map).containsKey('source'), isFalse);
    expect(body['lang'], 'en');
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('export_layout.v3.last_tpl.test.students')!)['id'], 9, reason: 'the last template is remembered per page');
    await close(tester);
  });

  testWidgets('preview: rows uploaded once, server pages with the page indicator and the Excel notes', (tester) async {
    await open(tester, step: 3);
    await _until(tester, () => find.byKey(const ValueKey('layout-page-label')).evaluate().isNotEmpty);
    expect(find.text('Page 1 of 5'), findsOneWidget);
    expect(find.text('Excel shows one card per line'), findsOneWidget);
    final rows = server.posted['rows']!.single as Map<String, dynamic>;
    expect((rows['rows'] as List), hasLength(120));
    expect((rows['columns'] as List).first, containsPair('label_ar', 'الاسم'));
    final prev = server.posted['preview']!.single as Map<String, dynamic>;
    expect((prev['document'] as Map)['source'], {'rows_upload': 'up1'});
    expect(prev['lang'], 'en');
    expect(prev['pages'], 'first,middle,last');
    await close(tester);
  });

  testWidgets('a page with a server dataset sends the dataset, never the rows', (tester) async {
    await open(tester, step: 3, export: layoutTestExport(dataset: 'course.students'));
    await _until(tester, () => server.posted['preview'] != null);
    expect(server.posted['rows'], isNull);
    final prev = server.posted['preview']!.single as Map<String, dynamic>;
    expect((prev['document'] as Map)['source'], {'dataset': 'course.students', 'params': {'course_id': 7}});
    await close(tester);
  });

  testWidgets("a dataset page designs with the server's own columns (GET /exports/datasets/{key}/columns)", (tester) async {
    await open(tester, step: 1, export: layoutTestExport(dataset: 'course.students'));
    await _until(tester, () => server.posted['columns'] != null);
    expect(server.posted['columns']!.single, {'course_id': '7'});
    final page = tester.state(find.byType(ExportLayoutPage)) as dynamic;
    final flow = page.flow as LayoutFlowController;
    expect(flow.datasetFields, isTrue);
    expect([for (final f in flow.fields) f.key], ['name', 'username', 'status', 'progress']);
    // the app's status labels stay with the matching key; the untouched starter is rebuilt on the server's keys
    expect(flow.fieldOf('status')!.type, 'status');
    final keys = {for (final c in flow.design.table.columns) c.field.field};
    expect(keys.difference({'name', 'username', 'status', 'progress'}), isEmpty);
    expect(keys, contains('name'));
    await close(tester);
  });

  testWidgets('previews are stale per language: a change refreshes the other tab when it is opened again', (tester) async {
    await open(tester, step: 3);
    await _until(tester, () => server.posted['preview'] != null);
    final page = tester.state(find.byType(ExportLayoutPage)) as dynamic;
    final flow = page.flow as LayoutFlowController;
    await _until(tester, () => !flow.previewLoading);
    expect(flow.previewStale('en'), isFalse);
    flow.setLanguages(['ar', 'en']);
    expect(flow.previewStale('en'), isTrue, reason: 'the document changed after the en preview');
    flow.setTab('ar');
    await _until(tester, () => server.posted['preview']!.length >= 2 && !flow.previewLoading);
    expect(flow.previewStale('ar'), isFalse);
    expect(flow.previewStale('en'), isTrue);
    final before = server.posted['preview']!.length;
    flow.setTab('en');
    await _until(tester, () => server.posted['preview']!.length > before && !flow.previewLoading);
    expect(flow.previewStale('en'), isFalse);
    flow.design.page.fontSize = 12;
    flow.changed();
    expect(flow.previewStale('ar'), isTrue);
    expect(flow.previewStale('en'), isTrue);
    await close(tester);
  });

  testWidgets('a run sends the title (not the file name) as the document name; the draft goes after the export', (tester) async {
    await open(tester, step: 3);
    await _until(tester, () => server.posted['preview'] != null);
    final page = tester.state(find.byType(ExportLayoutPage)) as dynamic;
    final flow = page.flow as LayoutFlowController;
    flow.changed();
    await tester.pump(const Duration(seconds: 1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('export_layout.v3.draft.test.students'), isNotNull);
    await _tap(tester, find.byKey(const ValueKey('layout-run-start')));
    await _until(tester, () => saved.isNotEmpty, step: const Duration(milliseconds: 500));
    final run = server.posted['runs']!.single as Map<String, dynamic>;
    expect(run['name'], 'Students');
    expect((run['document'] as Map)['name'], 'Students');
    expect(prefs.getString('export_layout.v3.draft.test.students'), isNull);
    expect(prefs.getString('export_layout.v3.last_doc.test.students'), isNotNull);
    await close(tester);
    // the next visit: no "draft is back", the exported design is there
    await open(tester);
    expect(find.textContaining('draft'), findsNothing);
    await close(tester);
  });

  testWidgets('opening the page and leaving saves no draft; a template load clears it', (tester) async {
    await open(tester);
    await close(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('export_layout.v3.draft.test.students'), isNull);
    await open(tester);
    final page = tester.state(find.byType(ExportLayoutPage)) as dynamic;
    final flow = page.flow as LayoutFlowController;
    flow.changed();
    await tester.pump(const Duration(seconds: 1));
    expect(prefs.getString('export_layout.v3.draft.test.students'), isNotNull);
    String? err = 'pending';
    unawaited(flow.loadTemplate(5).then((e) => err = e));
    await _until(tester, () => err != 'pending');
    expect(err, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(prefs.getString('export_layout.v3.draft.test.students'), isNull);
    await close(tester);
  });

  testWidgets('export: background run with progress, then the file is downloaded and saved', (tester) async {
    server.runSteps = 3;
    await open(tester, step: 3);
    await _until(tester, () => server.posted['preview'] != null);
    await _tap(tester, find.byKey(const ValueKey('layout-run-start')));
    await _until(tester, () => find.textContaining('Creating the file').evaluate().isNotEmpty, step: const Duration(milliseconds: 50));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-run-cancel')), findsOneWidget);
    await _until(tester, () => saved.isNotEmpty, step: const Duration(milliseconds: 500));
    expect(saved.single.$1, 'Students.pdf');
    expect(saved.single.$2, greaterThan(0));
    expect(find.textContaining('Saved'), findsWidgets);
    final run = server.posted['runs']!.single as Map<String, dynamic>;
    expect((run['document'] as Map)['schema_version'], 4);
    expect(server.runPolls, 3);
    await close(tester);
  });

  testWidgets('export: cancel stops the run on the server', (tester) async {
    server.runSteps = 1000;
    await open(tester, step: 3);
    await _until(tester, () => server.posted['preview'] != null);
    await _tap(tester, find.byKey(const ValueKey('layout-run-start')));
    await _until(tester, () => find.byKey(const ValueKey('layout-run-cancel')).evaluate().isNotEmpty && server.runPolls > 0);
    await _tap(tester, find.byKey(const ValueKey('layout-run-cancel')));
    await _settle(tester, 30);
    expect(server.posted['cancel'], isNotNull);
    expect(find.text('The export was cancelled'), findsOneWidget);
    expect(saved, isEmpty);
    await close(tester);
  });

  testWidgets('export: a failed run shows its error and saves nothing', (tester) async {
    server.runFails = true;
    await open(tester, step: 3);
    await _until(tester, () => server.posted['preview'] != null);
    await _tap(tester, find.byKey(const ValueKey('layout-run-start')));
    await _until(tester, () => find.text('Disk full').evaluate().isNotEmpty);
    expect(saved, isEmpty);
    await close(tester);
  });

  testWidgets('server limits read as friendly text: preview_busy with Retry, render_timeout on a run', (tester) async {
    server.previewBusy = true;
    server.runFails = true;
    server.runError = 'render_timeout';
    await open(tester, step: 3);
    await _until(tester, () => find.textContaining('A preview is already being prepared').evaluate().isNotEmpty);
    server.previewBusy = false;
    await _tap(tester, find.text('Retry'));
    await _until(tester, () => find.text('Page 1 of 5').evaluate().isNotEmpty);
    await _tap(tester, find.byKey(const ValueKey('layout-run-start')));
    await _until(tester, () => find.textContaining('Creating the file took too long').evaluate().isNotEmpty);
    await close(tester);
  });

  testWidgets('the draft is autosaved per page and restored on the next visit', (tester) async {
    await open(tester);
    await _tap(tester, find.byKey(const ValueKey('layout-format-xlsx')));
    await tester.pump(const Duration(seconds: 1));
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('export_layout.v3.draft.test.students');
    expect(raw, isNotNull);
    expect((jsonDecode(raw!)['doc'] as Map)['format'], 'xlsx');
    await close(tester);
    await open(tester);
    final excel = tester.widget<Semantics>(find.descendant(of: find.byKey(const ValueKey('layout-format-xlsx')), matching: find.byType(Semantics)).first);
    expect(excel.properties.selected, isTrue);
    await close(tester);
  });

  LayoutFlowController flowOf(WidgetTester tester) => (tester.state(find.byType(ExportLayoutPage)) as dynamic).flow as LayoutFlowController;

  testWidgets('quick path: a server starter and "Export now" run without opening the designer or asking for a preview', (tester) async {
    server.starters = [layoutTestStarter()];
    await open(tester);
    expect(server.posted['starters']!.single, {'purpose': 'export'});
    expect(find.byKey(const ValueKey('layout-starter-list2col')), findsOneWidget);
    expect(find.text('Two-column list'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('layout-starter-list2col')));
    await _tap(tester, find.byKey(const ValueKey('layout-export-now')));
    await _until(tester, () => saved.isNotEmpty, step: const Duration(milliseconds: 500));
    final run = server.posted['runs']!.single as Map<String, dynamic>;
    final design = ((run['document'] as Map)['designs'] as Map)['en'] as Map;
    expect(design['mode'], 'list');
    expect((design['list'] as Map)['columns'], 2);
    expect(server.posted['preview'], isNull, reason: 'the quick path never renders a preview');
    await close(tester);
  });

  testWidgets('an older server (no starters route): the local presets fill the gallery; a grid preset sets per line, per page and fill', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('layout-preset-table')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('layout-preset-grid2')));
    final flow = flowOf(tester);
    expect(flow.design.mode, 'custom');
    expect((flow.design.row.perLine, flow.design.row.perPage, flow.design.row.fillPage), (2, 4, true));
    await _tap(tester, find.byKey(const ValueKey('layout-customize')));
    final chip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('layout-grid-2-2')));
    expect(chip.selected, isTrue);
    await _tap(tester, find.byKey(const ValueKey('layout-back')));
    await _tap(tester, find.byKey(const ValueKey('layout-export-now')));
    await _until(tester, () => saved.isNotEmpty, step: const Duration(milliseconds: 500));
    final run = server.posted['runs']!.single as Map<String, dynamic>;
    final row = (((run['document'] as Map)['designs'] as Map)['en'] as Map)['row'] as Map;
    expect((row['per_line'], row['per_page'], row['fill_page']), (2, 4, true));
    await close(tester);
  });

  testWidgets('layout step: list columns and "a new page for each group" apply to the design', (tester) async {
    await open(tester, step: 1);
    await _tap(tester, find.byKey(const ValueKey('layout-kind-list')));
    await _tap(tester, find.descendant(of: find.byKey(const ValueKey('layout-list-columns')), matching: find.text('3')));
    final flow = flowOf(tester);
    expect(flow.design.list.columns, 3);
    flow.design.group = LayoutGroup(field: 'status');
    flow.changed();
    await _settle(tester, 2);
    await _tap(tester, find.byKey(const ValueKey('layout-group-page-break')));
    expect(flow.design.group!.pageBreak, isTrue);
    await close(tester);
  });

  testWidgets('Excel: the note shows, "one page per item" is not offered, and a page design falls back to cards', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('layout-excel-note')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('layout-format-xlsx')));
    expect(find.textContaining('Excel keeps the data and its formatting'), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-preset-page')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('layout-customize')));
    expect(find.byKey(const ValueKey('layout-kind-page')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('layout-back')));
    await _tap(tester, find.byKey(const ValueKey('layout-format-pdf')));
    expect(find.byKey(const ValueKey('layout-excel-note')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('layout-customize')));
    await _tap(tester, find.byKey(const ValueKey('layout-kind-page')));
    final flow = flowOf(tester);
    expect(flow.design.mode, 'page');
    flow.setFormat('xlsx');
    expect(flow.design.mode, 'custom', reason: 'Excel has no page mode');
    await close(tester);
  });

  testWidgets('computed columns: the entry calls the editor with the fields and sample rows; the new field joins the pickers', (tester) async {
    (int, int, String)? seen;
    Future<bool> editor(BuildContext context, {required LayoutDocument doc, required List<LayoutField> fields, required List<Map<String, Object?>> sampleRows, required String lang}) async {
      seen = (fields.length, sampleRows.length, lang);
      doc.computed.add(LayoutComputedField(key: 'calc.result', labelEn: 'Result', labelAr: 'النتيجة'));
      return true;
    }

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(ExportLayoutPage(export: layoutTestExport(), liveStream: kNoStream, initialStep: 1, computedEditor: editor, saveFile: (b, n, m) async {})));
    await _settle(tester);
    await _tap(tester, find.byKey(const ValueKey('layout-computed-open')));
    expect(seen, (5, 20, 'en'));
    final flow = flowOf(tester);
    expect([for (final f in flow.allFields) f.key], contains('calc.result'));
    expect(flow.fieldOf('calc.result')!.label('en'), 'Result');
    // the taller editorial cards: the kind cards sit above the fold once the computed entry was scrolled to
    await _tap(tester, find.byKey(const ValueKey('layout-kind-list'), skipOffstage: false));
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.byKey(const ValueKey('layout-field-calc.result')), findsOneWidget, reason: 'list fields offer the computed column');
    await close(tester);
  });

  testWidgets('live preview: edits are debounced into ONE request, and the page the person is on is kept', (tester) async {
    await open(tester, step: 1);
    expect(find.byKey(const ValueKey('layout-preview-pane')), findsOneWidget, reason: 'wide: the preview sits next to the editing');
    final flow = flowOf(tester);
    await _until(tester, () => !flow.previewStale('en') && !flow.previewLoading);
    final before = server.previewCalls;
    flow.showPreviewPage(1);
    for (var i = 0; i < 3; i++) {
      flow.design.page.fontSize = 10.0 + i;
      flow.changed();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(server.previewCalls, before, reason: 'nothing is asked for while the edits keep coming');
    await _until(tester, () => server.previewCalls > before && !flow.previewLoading, step: const Duration(milliseconds: 200));
    await _settle(tester, 5);
    expect(server.previewCalls, before + 1);
    expect(flow.previewPage, 1);
    expect(find.text('Page 3 of 5'), findsOneWidget);
    await close(tester);
  });

  testWidgets('preview requests are coalesced: asking while one is in flight runs one more after it, never two at once', (tester) async {
    await open(tester, step: 3);
    final flow = flowOf(tester);
    await _until(tester, () => !flow.previewStale('en') && !flow.previewLoading);
    final before = server.previewCalls;
    flow.changed();
    unawaited(flow.refreshPreview());
    unawaited(flow.refreshPreview());
    unawaited(flow.refreshPreview());
    await _until(tester, () => !flow.previewStale('en') && !flow.previewLoading);
    await _settle(tester, 6);
    expect(server.previewCalls - before, lessThanOrEqualTo(2));
    await close(tester);
  });

  testWidgets('the uploaded rows are sent again when the rows or the field set change (and only then)', (tester) async {
    await open(tester, step: 3);
    final flow = flowOf(tester);
    await _until(tester, () => !flow.previewStale('en') && !flow.previewLoading);
    expect(server.posted['rows'], hasLength(1));
    unawaited(flow.refreshPreview());
    await _settle(tester, 6);
    expect(server.posted['rows'], hasLength(1), reason: 'unchanged: the upload is reused');
    flow.export.rows.add({'name': 'New student', 'score': 5, 'status': 'active', 'joined': DateTime.utc(2026, 9, 2), 'email': 'n@example.com'});
    unawaited(flow.refreshPreview());
    await _until(tester, () => server.posted['rows']!.length == 2);
    expect(((server.posted['rows']!.last as Map)['rows'] as List), hasLength(121));
    await _until(tester, () => !flow.previewLoading);
    flow.fields = flow.fields.take(3).toList();
    unawaited(flow.refreshPreview());
    await _until(tester, () => server.posted['rows']!.length == 3);
    await _until(tester, () => !flow.previewLoading);
    await close(tester);
  });

  testWidgets('size guard: too many rows or too many bytes is refused with a clear message before anything is sent', (tester) async {
    await open(tester, step: 3, export: layoutTestExport(rows: 50001));
    await _until(tester, () => find.textContaining('Too many rows').evaluate().isNotEmpty);
    expect(server.posted['rows'], isNull);
    await close(tester);

    final big = layoutTestExport(rows: 100);
    for (final r in big.rows) {
      r['name'] = 'x' * 300000;
    }
    await open(tester, step: 3, export: big);
    await _until(tester, () => find.textContaining('too large to send').evaluate().isNotEmpty);
    expect(server.posted['rows'], isNull);
    await close(tester);
  });

  testWidgets('while the rows are sent the run panel says how many; the progress shows rows done / in all', (tester) async {
    server.runSteps = 4;
    await open(tester);
    final flow = flowOf(tester);
    unawaited(flow.startRun());
    await tester.pump();
    expect(find.textContaining('Sending 120 rows'), findsOneWidget);
    await _until(tester, () => find.textContaining('/ 120 rows').evaluate().isNotEmpty, step: const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('layout-run-hint')), findsOneWidget);
    await _until(tester, () => saved.isNotEmpty, step: const Duration(milliseconds: 500));
    await close(tester);
  });

  Future<void> pushed(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ExportLayoutPage(export: layoutTestExport(), liveStream: kNoStream, saveFile: (b, n, m) async => saved.add((n, b.length))),
          )),
          child: const Text('go'),
        ),
      ),
    )));
    await tester.tap(find.text('go'));
    await _settle(tester);
  }

  testWidgets('leaving while the file is made: "keep working" lets the run finish and save the file', (tester) async {
    server.runSteps = 4;
    await pushed(tester);
    final flow = flowOf(tester);
    unawaited(flow.startRun());
    await _until(tester, () => flow.phase == LayoutRunPhase.running && server.runPolls > 0, step: const Duration(milliseconds: 50));
    await tester.binding.handlePopRoute();
    await _settle(tester, 3);
    await _tap(tester, find.byKey(const ValueKey('layout-leave-background')));
    await _settle(tester, 3);
    expect(find.byType(ExportLayoutPage), findsNothing);
    await _until(tester, () => saved.isNotEmpty, step: const Duration(milliseconds: 500));
    expect(saved.single.$1, 'Students.pdf');
    await close(tester);
  });

  testWidgets('leaving while the file is made: "cancel" stops the run on the server', (tester) async {
    server.runSteps = 1000;
    await pushed(tester);
    final flow = flowOf(tester);
    unawaited(flow.startRun());
    await _until(tester, () => flow.phase == LayoutRunPhase.running && server.runPolls > 0, step: const Duration(milliseconds: 50));
    await tester.binding.handlePopRoute();
    await _settle(tester, 3);
    await _tap(tester, find.byKey(const ValueKey('layout-leave-cancel')));
    await _settle(tester, 10);
    expect(server.posted['cancel'], isNotNull);
    await close(tester);
  });

  group('kill switch', () {
    Future<void> launch(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(Scaffold(
        body: Builder(builder: (context) => Center(child: TextButton(onPressed: () => showAppExportSheet(context, layoutTestExport(rows: 3)), child: const Text('open')))),
      )));
      await tester.tap(find.text('open'));
      await _settle(tester);
    }

    testWidgets('on (key not disabled): the v3 page opens', (tester) async {
      await launch(tester);
      expect(find.byType(ExportLayoutPage), findsOneWidget);
      expect(find.byType(ExportFlowSheet), findsNothing);
      await close(tester);
    });

    testWidgets('export.layout_v3 disabled: the older flow opens', (tester) async {
      AppConfig.disableList = [kExportLayoutKey];
      await launch(tester);
      expect(find.byType(ExportLayoutPage), findsNothing);
      expect(find.byType(ExportFlowSheet), findsOneWidget);
      await close(tester);
    });
  });

  group('upload progress and the size pre-check', () {
    test('the controller exposes the upload fraction, throttled to ~100 ms', () async {
      final c = LayoutFlowController(export: layoutTestExport(rows: 5), api: _ProgressApi(), saveFile: null);
      final seen = <double?>[];
      c.addListener(() => seen.add(c.uploadProgress));
      expect(await c.ensureSource(), isNull);
      expect(c.uploadProgress, isNull, reason: 'cleared when the upload ends');
      expect(seen.whereType<double>().isNotEmpty, isTrue);
      expect(seen.whereType<double>().last, 1.0);
      // 50 events fired back to back: far fewer notifications than events
      expect(seen.length, lessThan(10));
      c.dispose();
    });

    test('the rows pre-check names the exact counts in both languages', () async {
      final big = layoutTestExport(rows: kLayoutMaxRows + 3);
      final fields = layoutFieldsOf(big.columns);
      AppConfig.lang = 'en';
      var r = await LayoutApi(api: ApiClient()).uploadRows(fields, big.rows);
      expect(r.code, 'rows_too_many');
      expect(r.error, contains('${kLayoutMaxRows + 3}'));
      AppConfig.lang = 'ar';
      r = await LayoutApi(api: ApiClient()).uploadRows(fields, big.rows);
      expect(r.error, contains('${kLayoutMaxRows + 3}'));
    });
  });
}

class _ProgressApi extends LayoutApi {
  @override
  Future<ExportResult<String>> uploadRows(List<LayoutField> fields, List<Map<String, Object?>> rows,
      {String lang = 'ar', void Function(int sent, int total)? onProgress}) async {
    onProgress?.call(0, 0); // size unknown yet
    for (var i = 1; i <= 50; i++) {
      onProgress?.call(i * 2, 100);
    }
    return ExportResult.ok('up1');
  }
}
