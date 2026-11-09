// VISUAL review renders of the certificate verification page (D-420) with the real server payloads
// (test/fixtures/payloads/cert_verify_*.json): 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/cert_verify_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/cert_verify_golden_test.dart --update-goldens [--plain-name fake]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_issue_logic.dart';
import 'package:flutter_education_app/features/shared/certificates_issue/cert_verify_view.dart';
import 'package:flutter_test/flutter_test.dart';

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
VerifyResult _r(String n) =>
    VerifyResult.fromJson((jsonDecode(File('test/fixtures/payloads/cert_verify_$n.json').readAsStringSync()) as Map).cast());

Widget _img(String _) => const AspectRatio(aspectRatio: 1.414, child: ColoredBox(color: Color(0xFFEDE7DA)));

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  final entry = TextEditingController();
  final states = <String, Widget Function()>{
    'entry': () => CertVerifyView(state: VerifyState.entry, entry: CertVerifyEntry(controller: entry, onSubmit: () {}, onScan: () {})),
    'entry_web': () => CertVerifyView(state: VerifyState.entry, entry: CertVerifyEntry(controller: entry, onSubmit: () {}, fieldError: 'cv_bad_number'.tr)),
    'real': () => CertVerifyView(state: VerifyState.found, result: _r('real'), lang: 'ar', onLang: (_) {}, imageBuilder: _img, onAnother: () {}),
    'no_expiry': () => CertVerifyView(state: VerifyState.found, result: _r('no_expiry'), lang: 'ar', onLang: (_) {}, imageBuilder: _img, onAnother: () {}),
    'expired': () => CertVerifyView(state: VerifyState.found, result: _r('expired'), lang: 'en', onLang: (_) {}, imageBuilder: _img, onAnother: () {}),
    'revoked': () => CertVerifyView(state: VerifyState.found, result: _r('revoked'), lang: 'en', onLang: (_) {}, imageBuilder: _img, onAnother: () {}),
    'masked': () => CertVerifyView(state: VerifyState.found, result: _r('number_masked'), onAnother: () {}),
    'fake': () => CertVerifyView(state: VerifyState.notFound, queried: 'NB-2026-AAAAAA', onAnother: () {}),
    'foreign': () => CertVerifyView(state: VerifyState.foreign, foreignHost: 'evil.example', onAnother: () {}),
  };

  for (final e in states.entries) {
    testWidgets(e.key, (tester) async {
      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        for (final lang in const ['ar', 'en']) {
          for (final dark in const [false, true]) {
            AppConfig.lang = lang;
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            final theme = ThemeConfigProvider(api: ApiClient());
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(ThemeConfigScope(
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
                home: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: e.value())),
              ),
            ));
            for (var i = 0; i < 4; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(tester.takeException(), isNull);
            await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/cert_verify_${e.key}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
}
