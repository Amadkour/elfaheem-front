// VISUAL review renders of the Certificate studio on the design engine (D-387): the real CertEngineStudio over a
// FakeApi with a bilingual certificate, with real fonts, at 1440x900, 1024x768 and 390x844, written as PNGs into the
// folder named by the environment variable CERT_SHOTS (never committed). Not a CI suite; compared by eye.
//
//   CERT_SHOTS=/some/dir flutter test test/visual/cert_engine_studio_visual_test.dart [--plain-name selected]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_keyboard.dart';
import 'package:flutter_education_app/design/export/export_fonts.dart';
import 'package:flutter_education_app/design/export_layout/layout_element_view.dart';
import 'package:flutter_education_app/features/certificates/studio/cert_engine_studio.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Map<String, dynamic> _text(String id, String value, double y, double h, double size, String color, {bool bold = false}) => {
      'id': id,
      'kind': 'text',
      'x': 38.5,
      'y': y,
      'w': 220,
      'h': h,
      'value': value,
      'name': id,
      'style': {'size': size, 'align': 'center', 'color': color, 'weight': bold ? 700 : 400, 'padding': 0},
    };

Map<String, dynamic> _design(bool rtl) => {
      'mode': 'page',
      'page': {'size': 'A4', 'orientation': 'landscape', 'margins': {'top': 0, 'right': 0, 'bottom': 0, 'left': 0}, 'rtl': rtl, 'font': 'tajawal', 'font_size': 14, 'background': '#FFFDF7'},
      'row': {
        'height': 210,
        'elements': [
          {'id': 'frame', 'kind': 'rect', 'x': 8, 'y': 8, 'w': 281, 'h': 194, 'locked': true, 'name': 'frame', 'style': {'padding': 0, 'border': {'width': 1.2, 'color': '#B08D3C'}}},
          _text('title', rtl ? 'شهادة إتمام' : 'Certificate of Completion', 32, 20, 38, '#1F3A5F', bold: true),
          _text('intro', rtl ? 'تشهد الأكاديمية بأن' : 'This certifies that', 60, 10, 15, '#6B7280'),
          {'id': 'name', 'kind': 'field', 'x': 38.5, 'y': 76, 'w': 220, 'h': 22, 'name': 'name', 'bind': {'field': 'student_name'}, 'style': {'size': 34, 'align': 'center', 'color': '#B08D3C', 'weight': 700, 'padding': 0}},
          _text('body', rtl ? 'قد أتم بنجاح دورة {{course_name}}' : 'has successfully completed {{course_name}}', 104, 12, 16, '#374151'),
          {'id': 'date', 'kind': 'field', 'x': 28, 'y': 160, 'w': 70, 'h': 10, 'name': 'date', 'bind': {'field': 'date'}, 'style': {'size': 13, 'align': 'center', 'color': '#374151', 'padding': 0}},
          {'id': 'sig', 'kind': 'signature', 'x': 199, 'y': 146, 'w': 70, 'h': 26, 'name': 'signature', 'sig_name': rtl ? 'د. سارة حسن' : 'Dr. Sara Hassan', 'sig_title': rtl ? 'مديرة الأكاديمية' : 'Director'},
          {'id': 'qr', 'kind': 'qr', 'x': 136, 'y': 150, 'w': 25, 'h': 25, 'name': 'qr', 'value': '{{verify_url}}'},
        ],
      },
    };

final _shot = GlobalKey();

Future<void> _capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['CERT_SHOTS'];
  if (dir == null || dir.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _pumps(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _desktop = Size(1440, 900), _tablet = Size(1024, 768), _portrait = Size(768, 1024), _phone = Size(390, 844);

class _Case {
  const _Case(this.size, this.lang, this.dark);
  final Size size;
  final String lang;
  final bool dark;
  String get label => '${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}';
}

const _cases = [
  _Case(_desktop, 'en', true),
  _Case(_desktop, 'en', false),
  _Case(_desktop, 'ar', false),
  _Case(_tablet, 'en', false),
  _Case(_portrait, 'ar', true),
  _Case(_phone, 'ar', false),
  _Case(_phone, 'en', true),
];

void main() {
  FakeApi? fake;
  var document = <String, dynamic>{};

  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    document = {
      'schema_version': 4,
      'format': 'pdf',
      'purpose': 'certificate',
      'name': 'Graduation certificate',
      'languages': ['ar', 'en'],
      'designs': {'ar': _design(true), 'en': _design(false)},
    };
    final tpl = Platform.environment['CERT_TEMPLATE_DOC'];
    if (tpl != null && tpl.isNotEmpty) document = (jsonDecode(File(tpl).readAsStringSync()) as Map).cast<String, dynamic>()..['name'] = 'Navy and gold';
    fake = FakeApi({
      'GET /api/v1/certificate-designs/7/document': (_) => {'document': document, 'version': 3, 'converted': false},
      'GET /api/v1/exports/layout/fonts': (_) => <Object>[],
      'GET /api/v1/exports/layout/starters': (_) => <Object>[],
      'GET /api/v1/certificate-designs/templates': (_) => <Object>[],
      'POST /api/v1/certificate-designs/preview-document': (_) => {'png_b64': base64Encode(File(Platform.environment['CERT_PREVIEW_PNG'] ?? 'assets/images/logo.png').readAsBytesSync())},
    }, latency: Duration.zero, fallback: (_) => const <String, dynamic>{})
      ..install();
  });
  tearDown(() => fake?.uninstall());

  Future<void> render(WidgetTester tester, String name, _Case k, {Future<void> Function(WidgetTester)? act}) async {
    final prevLang = AppConfig.lang;
    AppKeyboardSupport.enabledOverride = k.size.width >= 1024 ? true : null;
    addTearDown(() => AppKeyboardSupport.enabledOverride = null);
    debugDisableShadows = false;
    await tester.runAsync(() => ExportFonts.ensureCertFamilies().timeout(const Duration(seconds: 20), onTimeout: () {}));
    // the picker's label draws in the field's own font; the preview families come straight from the files here
    await tester.runAsync(() async {
      for (final id in const ['amiri', 'tajawal', 'cairo']) {
        final f = ExportFonts.byId(id);
        final loader = FontLoader(f.previewFamily)..addFont(Future.value(ByteData.sublistView(File(f.regularAsset).readAsBytesSync())));
        await loader.load();
      }
    });
    try {
      AppConfig.lang = k.lang;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = k.size;
      final theme = ThemeConfigProvider(api: ApiClient());
      await tester.pumpWidget(ThemeConfigScope(
        provider: theme,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: theme.materialTheme(dark: false),
          darkTheme: theme.materialTheme(dark: true),
          themeMode: k.dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, w) => Directionality(
            textDirection: k.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            child: RepaintBoundary(key: _shot, child: w!),
          ),
          home: AppKeyboardSupport(
            child: CertEngineStudio(
              designId: 7,
              drafts: CertEngineMemoryDrafts(),
              userId: 'u1',
              imageLoader: (u) async {
                // CERT_TEMPLATE_DOC runs: the template's background, next to the document (https://…/<file>)
                final dir = Platform.environment['CERT_TEMPLATE_DOC'];
                if (dir == null || dir.isEmpty) return null;
                final f = File('${File(dir).parent.path}/${u.split('/').last}');
                return f.existsSync() ? f.readAsBytesSync() : null;
              },
            ),
          ),
        ),
      ));
      await _pumps(tester);
      // a template's background decodes off the fake clock
      final slow = (Platform.environment['CERT_TEMPLATE_DOC'] ?? '').isNotEmpty;
      await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: slow ? 2500 : 200)));
      await _pumps(tester, 6);
      if (slow) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
        await _pumps(tester, 4);
      }
      if (act != null) {
        await act(tester);
        await _pumps(tester, 6);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await _pumps(tester, 6);
      }
      await _capture(tester, '${name}_${k.label}');
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }

  Finder element(String id) => find.byWidgetPredicate((w) => w is LayoutElementView && w.element.id == id);

  testWidgets('empty', (t) async {
    document['designs'] = {
      for (final (l, rtl) in const [('ar', true), ('en', false)]) l: _design(rtl)..['row'] = {'height': 210, 'elements': <Object>[]},
    };
    await render(t, 'empty', _cases[1]);
  });
  testWidgets('empty phone', (t) async {
    document['designs'] = {
      for (final (l, rtl) in const [('ar', true), ('en', false)]) l: _design(rtl)..['row'] = {'height': 210, 'elements': <Object>[]},
    };
    await render(t, 'empty', _cases[5]);
  });
  testWidgets('layers tool on a phone', (t) => render(t, 'tool', _cases[5], act: (t) async {
        await t.tap(find.byKey(const ValueKey('cert-rail-layers')));
      }));
  // CERT_TEMPLATE_DOC: a real template's document (the server's own conversion), a text field selected
  for (final k in [_cases[0], _cases[5]]) {
    testWidgets('template ${k.label}', (t) => render(t, 'template', k, act: (t) async {
          await t.tap(element('student_name'), warnIfMissed: false);
          await _pumps(t, 12);
          // the phone's sheet: the font row sits under the content section
          if (k.size.width < 1000) await t.drag(find.descendant(of: find.byKey(const ValueKey('cert-sheet')), matching: find.byType(ListView)).first, const Offset(0, -320));
        }));
  }
  testWidgets('photo element', (t) {
    for (final d in (document['designs'] as Map).values) {
      (((d as Map)['row'] as Map)['elements'] as List).add({'id': 'p1', 'kind': 'image', 'x': 124, 'y': 118, 'w': 40, 'h': 40, 'name': 'photo', 'bind': {'field': 'photo'}, 'style': {'padding': 0}});
    }
    return render(t, 'photo', _cases[0], act: (t) async {
      await t.tap(element('p1'), warnIfMissed: false);
    });
  });
  testWidgets('preview', (t) => render(t, 'preview', _cases[1], act: (t) async {
        await t.tap(find.byKey(const ValueKey('cert-preview')));
      }));

  for (final k in _cases) {
    testWidgets('design ${k.label}', (t) => render(t, 'design', k));
    testWidgets('selected ${k.label}', (t) => render(t, 'selected', k, act: (t) async {
          await t.tap(element('name'), warnIfMissed: false);
        }));
  }
}
