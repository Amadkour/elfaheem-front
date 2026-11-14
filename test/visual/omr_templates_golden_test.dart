// Visual review renders of the bubble-sheet library and the learning flow (D-155, Example 3), compared by eye like the
// other test/visual files (NOT a CI suite). The REAL pages run over the fake backend with recorded engine replies and
// the engine's own canonical previews of a sheet printed by mlkit/omr/sheets.py (test/fixtures/payloads/omr_templates/).
// The PNGs go OUTSIDE the repo:
//
//   OMR_RENDER_DIR=<dir> flutter test test/visual/omr_templates_golden_test.dart --update-goldens [--plain-name q17]
//
// → <dir>/omrt_<scene>_<width>_<lang>_<light|dark>.png
//   library   the super admin's library (pending first, families with versions, previews)
//   upload    the learning form filled in      result   "Detected 4 corner marks, 2 answer columns"
//   q17       question 17 highlighted on the filled sample      fix   dragging the boxes of question 17
//   id        the student ID zone ("… read from the filled sheet: 2024001234")      save   ready to publish
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/features/exams/paper/templates/omr_template_learn.dart';
import 'package:flutter_education_app/features/exams/paper/templates/omr_template_library.dart';
import 'package:flutter_education_app/features/exams/paper/templates/omr_templates.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'home_screens_golden_test.dart' show pubspecFonts;

const _fx = 'test/fixtures/payloads/omr_templates';
Map<String, dynamic> _p(String name) => Map<String, dynamic>.from((jsonDecode(File('$_fx/$name.json').readAsStringSync()) as Map)['payload'] as Map);
final _blank = File('$_fx/blank_preview.png').readAsBytesSync();
final _filled = File('$_fx/filled_preview.png').readAsBytesSync();
final _builtin = File('$_fx/builtin_preview.png').readAsBytesSync();

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
  final cfg = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final p in (cfg['packages'] as List).cast<Map<String, dynamic>>()) {
    if (p['name'] != 'cupertino_icons') continue;
    final root = Uri.parse('${p['rootUri']}');
    final dir = root.isAbsolute ? root.toFilePath() : File('.dart_tool/${p['rootUri']}').absolute.path;
    final font = File('$dir/assets/CupertinoIcons.ttf');
    if (font.existsSync()) await load('packages/cupertino_icons/CupertinoIcons', [font.path]);
  }
}

final _shot = GlobalKey();
final _dir = (Platform.environment['OMR_RENDER_DIR'] ?? '${Directory.systemTemp.path}/omr_renders').replaceAll('\\', '/');

/// The engine with the real preview PNGs (the fake answers JSON only).
class _Api extends OmrTemplatesApi {
  @override
  Future<Uint8List?> image(int id, String kind) async => switch (kind) {
        'filled_preview' => _filled,
        'blank_preview' => _blank,
        _ => id <= 4 ? _builtin : _blank,
      };
}

final _stream = LiveStreamHandle(connected: ValueNotifier(true), bind: () {}, release: () {});

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: child,
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _frames(tester);
}

/// Opens step [i] (the inline grid on desktop, the sheet on a phone).
Future<void> _jump(WidgetTester tester, int i) async {
  if (find.byKey(ValueKey('omr.jump.$i')).evaluate().isEmpty) await _tap(tester, 'omr.jump');
  await _tap(tester, 'omr.jump.$i');
  await tester.pump(const Duration(seconds: 1));
}

FakeApi _backend({String steps = 'steps_done_super'}) => FakeApi({
      'GET /api/v1/exam/omr/templates': (_) => _p('library_super'),
      'GET /api/v1/exam/omr/templates/5': (_) => _p('detail_done'),
      'GET /api/v1/exam/omr/templates/5/steps': (_) => _p(steps),
      'POST /api/v1/exam/omr/templates/5/validate': (_) => _p('validate_ok'),
    }, latency: const Duration(milliseconds: 10));

Future<void> _render(WidgetTester tester, String name, Widget Function() build, [Future<void> Function(WidgetTester t)? act, String steps = 'steps_done_super']) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  final fake = _backend(steps: steps)..install();
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          await _frames(tester);
          if (act != null) await act(tester);
          // let the engine decode the preview PNGs (real async), then settle the zoom
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
          await _frames(tester, 10);
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile(Uri.file('$_dir/omrt_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png')),
          );
        }
      }
    }
  } finally {
    fake.uninstall();
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Widget _page({int? id}) => OmrTemplateLearnPage(isSuperAdmin: true, templateId: id, api: _Api(), liveStream: _stream, liveBus: LiveEvents.instance,
    pickFile: ({required bool camera}) async => ('blank-sheet-scan.png', _blank));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('library', (t0) => _render(t0, 'library', () => OmrTemplateLibraryPage(api: _Api())));

  testWidgets('upload', (t0) => _render(t0, 'upload', () => _page(), (tester) async {
        Future<void> type(String key, String v) async {
          await tester.enterText(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)), v);
          await tester.pump();
        }

        await type('omr.name', AppConfig.lang == 'ar' ? 'ورقة المدرسة 50 سؤالًا' : 'School sheet, 50 questions');
        await _tap(tester, 'omr.blank.pick');
        await type('omr.questions', '50');
        await type('omr.options', '4');
        await type('omr.per_column', '25');
        await type('omr.id_columns', '10');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
        await _frames(tester, 4);
      }));

  testWidgets('result', (t0) => _render(t0, 'result', () => _page(id: 5)));

  testWidgets('q17', (t0) => _render(t0, 'q17', () => _page(id: 5), (tester) async {
        await _tap(tester, 'omr.check');
        await _jump(tester, 16);
      }));

  testWidgets('fix', (t0) => _render(t0, 'fix', () => _page(id: 5), (tester) async {
        await _tap(tester, 'omr.check');
        await _jump(tester, 16);
        await _tap(tester, 'omr.fix');
        await tester.pump(const Duration(seconds: 1));
      }));

  testWidgets('id', (t0) => _render(t0, 'id', () => _page(id: 5), (tester) async {
        await _tap(tester, 'omr.check');
        await _jump(tester, 50);
      }));

  testWidgets('save', (t0) => _render(t0, 'save', () => _page(id: 5), (tester) async {
        await _tap(tester, 'omr.check');
        await _jump(tester, 51);
        await _tap(tester, 'omr.step.next');
      }, 'e2e_confirm_all')); // every question confirmed (the e2e's reply for the same sheet)
}
