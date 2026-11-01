// VISUAL review renders of the certificate studio (agent A): the real CertificateDesignerScreen over a provider that
// holds a bilingual design (styled text boxes, a rotated stamp line, a watermark, a Letter page), at 390x844 and
// 1440x900, ar / en, light / dark, with nothing selected (the page panel) and with a text selected (its properties
// docked: in a panel under the page on a phone, on the end side on a computer), into
// test/visual/goldens/cert_designer_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/cert_designer_golden_test.dart --update-goldens [--plain-name text]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_design_models.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designer_provider.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designer_screen.dart';
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

final _shot = GlobalKey();

Map<String, dynamic> _design() => {
      'id': 31,
      'name': 'شهادة التخرج — كلية الهندسة',
      'orientation': 'landscape',
      'background_kind': 'none',
      'theme': {
        'color': '#1F6F5C',
        'page': {'size': 'letter'},
        'watermark': {'kind': 'text', 'text': 'ORIGINAL', 'opacity': .07, 'rotation': -24, 'size': 120, 'position': 'center', 'font': 'cinzel', 'color': '#1F6F5C'},
      },
      'fields': [
        {'id': 'band', 'kind': 'line', 'x': 0, 'y': 0, 'w': 1000, 'h': 22, 'color': '#1F6F5C'},
        {'id': 'head', 'kind': 'text', 'text': 'شهادة تخرج', 'x': 200, 'y': 70, 'w': 600, 'size': 64, 'font': 'aref_ruqaa_bold', 'color': '#1F6F5C', 'max_lines': 1},
        {'id': 'intro', 'kind': 'text', 'text': 'تشهد كلية الهندسة بأن', 'x': 250, 'y': 200, 'w': 500, 'size': 26, 'font': 'tajawal', 'color': '#4B5563', 'max_lines': 1},
        {'id': 'name', 'kind': 'text', 'text': '{student_name}', 'x': 200, 'y': 255, 'w': 600, 'size': 54, 'font': 'amiri_bold', 'color': '#1C1C24', 'max_lines': 1, 'underline': true},
        {'id': 'body', 'kind': 'text', 'text': 'قد أتمّ بنجاح متطلبات دورة «{course_name}» بتقدير ممتاز، تحت إشراف {teacher_name}.', 'x': 220, 'y': 370, 'w': 560, 'size': 24, 'font': 'cairo', 'color': '#374151', 'max_lines': 3, 'line_height': 1.5},
        {'id': 'serial', 'kind': 'text', 'text': 'رقم الشهادة {serial}', 'x': 360, 'y': 530, 'w': 280, 'size': 16, 'font': 'tajawal_bold', 'color': '#1F6F5C', 'max_lines': 1, 'bg_color': '#E6F2EE', 'border_color': '#1F6F5C', 'border_width': 1.5, 'radius': 18, 'padding': 10},
        {'id': 'stamp', 'kind': 'text', 'text': 'معتمد', 'x': 790, 'y': 610, 'w': 150, 'size': 30, 'font': 'reem_kufi_bold', 'color': '#B91C1C', 'max_lines': 1, 'rotation': -12, 'border_color': '#B91C1C', 'border_width': 3, 'radius': 10, 'padding': 6},
        {'id': 'sig', 'kind': 'signature', 'x': 70, 'y': 600, 'w': 220, 'h': 70, 'size': 20, 'font': 'tajawal_bold', 'color': '#1C1C24', 'sig_name': 'د. سارة محمود', 'sig_title': 'عميدة الكلية'},
        {'id': 'qr', 'kind': 'qr', 'x': 455, 'y': 620, 'w': 90, 'color': '#1C1C24'},
      ],
      'fields_en': [
        {'id': 'band', 'kind': 'line', 'x': 0, 'y': 0, 'w': 1000, 'h': 22, 'color': '#1F6F5C'},
        {'id': 'head', 'kind': 'text', 'text': 'Certificate of Graduation', 'x': 150, 'y': 70, 'w': 700, 'size': 52, 'font': 'cinzel', 'color': '#1F6F5C', 'max_lines': 1, 'letter_spacing': 2},
        {'id': 'intro', 'kind': 'text', 'text': 'The Faculty of Engineering certifies that', 'x': 250, 'y': 200, 'w': 500, 'size': 24, 'font': 'cormorant_italic', 'color': '#4B5563', 'max_lines': 1},
        {'id': 'name', 'kind': 'text', 'text': '{student_name}', 'x': 200, 'y': 250, 'w': 600, 'size': 60, 'font': 'great_vibes', 'color': '#1C1C24', 'max_lines': 1},
        {'id': 'body', 'kind': 'text', 'text': 'has successfully completed the course “{course_name}” with distinction, under the guidance of {teacher_name}.', 'x': 220, 'y': 370, 'w': 560, 'size': 22, 'font': 'eb_garamond', 'color': '#374151', 'max_lines': 3, 'line_height': 1.4},
        {'id': 'serial', 'kind': 'text', 'text': 'No. {serial}', 'x': 360, 'y': 530, 'w': 280, 'size': 16, 'font': 'tajawal_bold', 'color': '#1F6F5C', 'max_lines': 1, 'bg_color': '#E6F2EE', 'border_color': '#1F6F5C', 'border_width': 1.5, 'radius': 18, 'padding': 10, 'letter_spacing': 1},
        {'id': 'stamp', 'kind': 'text', 'text': 'APPROVED', 'x': 790, 'y': 610, 'w': 160, 'size': 24, 'font': 'cinzel', 'weight': 'bold', 'color': '#B91C1C', 'max_lines': 1, 'rotation': -12, 'border_color': '#B91C1C', 'border_width': 3, 'radius': 10, 'padding': 6},
        {'id': 'sig', 'kind': 'signature', 'x': 70, 'y': 600, 'w': 220, 'h': 70, 'size': 20, 'font': 'playfair', 'color': '#1C1C24', 'sig_name': 'Dr. Sara Mahmoud', 'sig_title': 'Dean of the Faculty'},
        {'id': 'qr', 'kind': 'qr', 'x': 455, 'y': 620, 'w': 90, 'color': '#1C1C24'},
      ],
      'can_edit': true,
      'langs': ['ar', 'en'],
      'theme_en': null,
    };

Future<void> _render(WidgetTester tester, String name, {String? select}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          final variant = '${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}';
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          SharedPreferences.setMockInitialValues({});
          final theme = ThemeConfigProvider(api: ApiClient());
          final p = CertificateDesignerProvider(initialLang: lang, drafts: CertMemoryDraftStore())
            ..adopt(CertDesign.fromJson(_design()));
          if (select != null) p.studio.select(select);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(ThemeConfigScope(
            provider: theme,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              theme: theme.materialTheme(dark: false),
              darkTheme: theme.materialTheme(dark: true),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, w) => Directionality(
                textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                child: RepaintBoundary(key: _shot, child: w!),
              ),
              home: CertificateDesignerScreen(provider: p),
            ),
          ));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/${name}_$variant.png'));
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 2));
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  FakeApi? fake;

  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  setUp(() {
    fake = FakeApi({}, latency: Duration.zero, fallback: (_) => const <String, dynamic>{})..install();
  });

  tearDown(() => fake?.uninstall());

  testWidgets('page', (t) => _render(t, 'cert_designer_page'));
  testWidgets('text', (t) => _render(t, 'cert_designer_text', select: 'serial'));
}
