// VISUAL review renders of the first-run and entry screens around sign-in (Warm Editorial, D-610 – D-629) — not a CI
// suite: the onboarding pages, the guest search and the passcode sheet, at 390x844 and 1440x900, ar / en,
// light / dark, with the real fonts, into test/visual/goldens/area_auth_*.png. Compared by eye, not by the test:
//
//   flutter test test/visual/auth_area_golden_test.dart --update-goldens [--plain-name onboarding]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/onboarding/guest_search_screen.dart';
import 'package:flutter_education_app/features/onboarding/landing_api.dart';
import 'package:flutter_education_app/features/onboarding/onboarding_screen.dart';
import 'package:flutter_education_app/features/onboarding/onboarding_store.dart';
import 'package:flutter_education_app/features/profile/passcode/passcode_screen.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
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

const _subjects = [
  LandingSubject(id: 1, nameAr: 'الرياضيات', nameEn: 'Mathematics', courses: 12, levels: [
    LandingLevel(id: 11, nameAr: 'الصف الثالث الثانوي', nameEn: 'Grade 12', courses: 5),
  ]),
  LandingSubject(id: 2, nameAr: 'اللغة الإنجليزية', nameEn: 'English language', courses: 3),
];

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
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: child),
    ),
  );
}

Widget _passcode() => Builder(
      builder: (context) => Scaffold(
        backgroundColor: context.colors.background,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              color: context.colors.cardBg,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: PasscodeSheet(
                title: AppConfig.lang == 'ar' ? 'رمز الامتحان' : 'Exam passcode',
                hint: AppConfig.lang == 'ar' ? 'اكتب الرمز الذي أعطاك إياه معلمك' : 'Enter the code your teacher gave you',
                wrongText: 'x',
                verify: (_) => false,
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {Future<void> Function()? act}) async {
  final prev = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (act != null) await act();
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot),
              matchesGoldenFile('goldens/area_auth_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
        }
      }
    }
  } finally {
    AppConfig.lang = prev;
    debugDisableShadows = true;
    tester.view.reset();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(OnboardingStore.resetForTest);

  testWidgets('onboarding', (tester) => _render(tester, 'onboarding', () => OnboardingScreen(onLanguage: (_) {}, onFinish: () {})));
  testWidgets('onboarding last', (tester) async {
    await _render(tester, 'onboarding_last', () => OnboardingScreen(onLanguage: (_) {}, onFinish: () {}), act: () async {
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await tester.pump(const Duration(seconds: 1));
    });
  });
  testWidgets('guest search', (tester) => _render(
      tester,
      'guest_search',
      () => GuestSearchScreen(
            loadOptions: () async => _subjects,
            loadMatch: ({subject, level, required mode}) async => const LandingCount(courses: 12, teachers: 7),
            onShow: (_, _) {},
            onLogin: () {},
            onRegister: () {},
          )));
  testWidgets('passcode', (tester) => _render(tester, 'passcode', _passcode));
}
