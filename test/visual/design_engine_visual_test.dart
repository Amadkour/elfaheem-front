// VISUAL review renders of the export flow (design engine, D-142): the start screen (idle and while a run is in
// progress), the Layout / Design / Preview steps, and the computed-columns builder (empty, then with the Pass / Fail
// and Grade bands presets), with the real fonts and theme, into test/visual/goldens/design_engine/*.png. Not a CI
// suite; compared by eye.
//
//   flutter test test/visual/design_engine_visual_test.dart --update-goldens [--plain-name start]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_table_export.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export_layout/layout_computed_builder.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_education_app/design/export_layout/layout_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../export/layout_fake.dart';
import '../support/fake_api.dart';
import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();

const _names = ['أحمد حمدي', 'سارة محمود', 'عمر خالد', 'ليلى حسن', 'يوسف إبراهيم', 'نور الهدى', 'مريم عادل', 'كريم فؤاد'];

AppTableExport _export() => AppTableExport(
      id: 'visual.students',
      title: 'Students',
      titles: const {'ar': 'الطلاب', 'en': 'Students'},
      brand: 'Alfaheem Academy',
      filters: const {'Course': 'Algebra'},
      columns: const [
        AppExportColumn('name', 'Name', labels: {'ar': 'الاسم', 'en': 'Name'}, locked: true),
        AppExportColumn('score', 'Score', type: AppColType.number, labels: {'ar': 'الدرجة', 'en': 'Score'}),
        AppExportColumn('max', 'Max', type: AppColType.number, labels: {'ar': 'العظمى', 'en': 'Max'}),
        AppExportColumn('status', 'Status', type: AppColType.status, labels: {'ar': 'الحالة', 'en': 'Status'}),
        AppExportColumn('joined', 'Joined', type: AppColType.date, labels: {'ar': 'الانضمام', 'en': 'Joined'}),
        AppExportColumn('email', 'Email', visible: false, labels: {'ar': 'البريد', 'en': 'Email'}),
      ],
      rows: [
        for (var i = 0; i < 32; i++)
          {
            'name': '${_names[i % _names.length]} ${i ~/ _names.length + 1}',
            'score': (i * 37) % 100,
            'max': 100,
            'status': i.isEven ? 'active' : 'dropped',
            'joined': DateTime.utc(2026, 9, 1 + i % 28),
            'email': 's$i@example.com',
          },
      ],
    );

const _fields = [
  LayoutField(key: 'name', labelAr: 'الاسم', labelEn: 'Name'),
  LayoutField(key: 'score', labelAr: 'الدرجة', labelEn: 'Score', type: 'number'),
  LayoutField(key: 'max', labelAr: 'العظمى', labelEn: 'Max', type: 'number'),
];

final _sample = <Map<String, Object?>>[
  for (var i = 0; i < 6; i++) {'name': _names[i], 'score': 35 + i * 11, 'max': 100},
];

Future<void> _settle(WidgetTester t, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

const _desktop = Size(1440, 900);
const _phone = Size(390, 844);
const _all = [
  (_desktop, 'ar', false),
  (_desktop, 'ar', true),
  (_desktop, 'en', false),
  (_desktop, 'en', true),
  (_phone, 'ar', false),
  (_phone, 'en', true),
];

/// Draws [build] in every variant, running [act] on the pumped widget before the shot.
Future<void> _render(
  WidgetTester t,
  String name,
  Widget Function() build, {
  Future<void> Function(WidgetTester)? act,
  List<(Size, String, bool)> variants = _all,
}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final (size, lang, dark) in variants) {
      final variant = '${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}';
      AppConfig.lang = lang;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeConfigProvider(api: ApiClient());
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(ThemeConfigScope(
        provider: theme,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.materialTheme(dark: false),
          darkTheme: theme.materialTheme(dark: true),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, w) => Directionality(
            textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            child: RepaintBoundary(key: _shot, child: w!),
          ),
          home: build(),
        ),
      ));
      await _settle(t);
      if (act != null) await act(t);
      expect(t.takeException(), isNull);
      await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/design_engine/${name}_$variant.png'));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    }
  } finally {
    AppConfig.lang = prevLang;
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
    debugDisableShadows = true;
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }
}

ExportLayoutPage _page({int step = 0}) => ExportLayoutPage(export: _export(), liveStream: kNoStream, initialStep: step, saveFile: (b, n, m) async {});

Future<void> _tap(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) return;
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first);
  await _settle(t, 6);
}

void main() {
  late LayoutFakeServer server;
  FakeApi? fake;

  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  setUp(() {
    mockRequestPlugins();
    AppConfig.disableList = [];
    server = LayoutFakeServer()..runSteps = 100000;
    fake = FakeApi(server.routes(), latency: const Duration(milliseconds: 20))..install();
  });
  tearDown(() => fake?.uninstall());

  testWidgets('start', (t) => _render(t, 'start', () => _page()));

  testWidgets('start running', (t) => _render(t, 'start_running', () => _page(), act: (t) async {
        await _tap(t, 'layout-export-now');
        await _settle(t, 20);
      }));

  testWidgets('layout list', (t) => _render(t, 'layout_list', () => _page(step: 1), act: (t) => _tap(t, 'layout-kind-list')));

  testWidgets('layout grid', (t) => _render(t, 'layout_grid', () => _page(step: 1), act: (t) => _tap(t, 'layout-kind-grid'), variants: const [
        (_desktop, 'ar', false),
        (_desktop, 'en', true),
        (_phone, 'ar', false),
        (_phone, 'en', true),
      ]));

  testWidgets('layout page per item', (t) => _render(t, 'layout_page', () => _page(step: 1), act: (t) => _tap(t, 'layout-kind-page'), variants: const [
        (_desktop, 'en', false),
        (_phone, 'ar', true),
      ]));

  testWidgets('layout cards', (t) => _render(t, 'layout_cards', () => _page(step: 1), act: (t) => _tap(t, 'layout-kind-cards'), variants: const [
        (_desktop, 'ar', false),
        (_phone, 'en', true),
      ]));

  testWidgets('design', (t) => _render(t, 'design', () => _page(step: 2)));

  testWidgets('preview', (t) => _render(t, 'preview', () => _page(step: 3)));

  testWidgets('computed empty', (t) => _render(t, 'computed_empty', () => ComputedFieldsEditorPage(doc: LayoutDocument(), fields: _fields, sampleRows: _sample, lang: AppConfig.lang)));

  testWidgets('computed presets', (t) => _render(t, 'computed_presets', () => ComputedFieldsEditorPage(doc: LayoutDocument(), fields: _fields, sampleRows: _sample, lang: AppConfig.lang), act: (t) async {
        await _tap(t, 'cc-preset-pass_fail');
        await _tap(t, 'cc-preset-grade_bands');
      }));
}
