// The v3 export page (D-142) against a fake layout server (FakeApi): stepping through list / table / custom, the
// rule builder, the item browser, templates (save with schema_version 3, load in one click, v2 ones left out), the
// background run (progress → download, cancel, failure), the rows source (upload vs dataset), the local draft, and
// the kill switch falling back to the older flow.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_table_export.dart';
import 'package:flutter_education_app/design/export_hub/export_flow.dart' show ExportFlowSheet;
import 'package:flutter_education_app/design/export_layout/layout_canvas.dart';
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

  testWidgets('steps: format → list → table → custom card with the canvas and the item browser', (tester) async {
    await open(tester);
    expect(find.text('File format'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('layout-format-docx')));
    await _tap(tester, find.byKey(const ValueKey('layout-lang-both')));
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.text('How do you want to show your items?'), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-tab-ar')), findsOneWidget, reason: 'two languages = two design tabs');

    await _tap(tester, find.byKey(const ValueKey('layout-mode-list')));
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.text('Fields of the line'), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-field-email')), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('layout-back')));
    await _tap(tester, find.byKey(const ValueKey('layout-mode-table')));
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.text('Table columns'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('layout-back')));
    await _tap(tester, find.byKey(const ValueKey('layout-mode-custom2')));
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

    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.byKey(const ValueKey('layout-band-header')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('layout-band-page')));
    expect(find.byKey(const ValueKey('layout-watermark')), findsOneWidget);
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

  testWidgets('templates: v3 ones listed (v2 left out), one click opens, save sends schema_version 3 without the source', (tester) async {
    await open(tester, step: 1);
    expect(find.byKey(const ValueKey('layout-tpl-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-tpl-6')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('layout-tpl-5')));
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    expect(find.text('Fields of the line'), findsOneWidget, reason: 'the template is a list design');
    expect(api.calls.where((c) => c.path == '/api/v1/exports/templates/5/used'), isNotEmpty);

    // save as a template from the preview step
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    await _tap(tester, find.byKey(const ValueKey('layout-next')));
    await _settle(tester);
    await _tap(tester, find.byKey(const ValueKey('layout-save-template')));
    await tester.enterText(find.byKey(const ValueKey('layout-template-name')), 'My roster');
    await _tap(tester, find.byKey(const ValueKey('layout-template-save')));
    await _settle(tester);
    final body = server.posted['templates']!.single as Map<String, dynamic>;
    expect(body['schema_version'], 3);
    expect(body['name'], 'My roster');
    expect(body['page_key'], isNotEmpty);
    expect((body['design'] as Map)['schema_version'], 3);
    expect((body['design'] as Map).containsKey('source'), isFalse);
    expect(body['lang'], 'en');
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('export_layout.v3.last_tpl.test.students')!)['id'], 9, reason: 'the last template is remembered per page');
    await close(tester);
  });

  testWidgets('preview: rows uploaded once, server pages with the page indicator and the Excel notes', (tester) async {
    await open(tester, step: 4);
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
    await open(tester, step: 4, export: layoutTestExport(dataset: 'course.students'));
    await _until(tester, () => server.posted['preview'] != null);
    expect(server.posted['rows'], isNull);
    final prev = server.posted['preview']!.single as Map<String, dynamic>;
    expect((prev['document'] as Map)['source'], {'dataset': 'course.students', 'params': {'course_id': 7}});
    await close(tester);
  });

  testWidgets('export: background run with progress, then the file is downloaded and saved', (tester) async {
    server.runSteps = 3;
    await open(tester, step: 4);
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
    expect((run['document'] as Map)['schema_version'], 3);
    expect(server.runPolls, 3);
    await close(tester);
  });

  testWidgets('export: cancel stops the run on the server', (tester) async {
    server.runSteps = 1000;
    await open(tester, step: 4);
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
    await open(tester, step: 4);
    await _until(tester, () => server.posted['preview'] != null);
    await _tap(tester, find.byKey(const ValueKey('layout-run-start')));
    await _until(tester, () => find.text('Disk full').evaluate().isNotEmpty);
    expect(saved, isEmpty);
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
}
