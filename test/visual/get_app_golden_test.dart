// Visual review of "Get the app" (D-137): the strip for each kind of offer above a page, and the sheet for an Android
// phone, an iPhone in Safari and a computer, at 390x844 and 1440x900, ar / en, light / dark, with the real fonts.
// Compared by eye, not by the test:  flutter test test/visual/get_app_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/get_app/get_app_service.dart';
import 'package:flutter_education_app/features/get_app/get_app_banner.dart';
import 'package:flutter_education_app/features/get_app/get_app_sheet.dart';
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
  // the Share / Add-to-Home-Screen glyphs of the iPhone steps (package font, found through the pub cache)
  final cache = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['LOCALAPPDATA']}/Pub/Cache';
  final hosted = Directory('$cache/hosted/pub.dev');
  if (hosted.existsSync()) {
    final dirs = hosted.listSync().whereType<Directory>().where((d) => d.path.contains('cupertino_icons-')).toList();
    if (dirs.isNotEmpty) await load('packages/cupertino_icons/CupertinoIcons', ['${dirs.last.path}/assets/CupertinoIcons.ttf']);
  }
}

const _sha = '742cd576ffd647dc57a12d6a5fec659f432e4f0897ef7bc1363125c5041148a2';
final _manifest = parseReleasesManifest({
  'platforms': {
    'android': {
      'version': '1.0.0',
      'build': 1,
      'min_os': 'Android 7.0',
      'primary': 'arm64-v8a',
      'notes': {'ar': 'أول إصدار للتنزيل المباشر.', 'en': 'First direct-download release.'},
      'files': [
        {'arch': 'arm64-v8a', 'kind': 'apk', 'url': 'https://nextbrain.site/releases/android/a.apk', 'size': 48700000, 'sha256': _sha},
        {'arch': 'armeabi-v7a', 'kind': 'apk', 'url': 'https://nextbrain.site/releases/android/b.apk', 'size': 47000000},
        {'arch': 'universal', 'kind': 'apk', 'url': 'https://nextbrain.site/releases/android/c.apk', 'size': 99000000},
      ],
    },
    'ios': {'pwa': true},
    'windows': {'pwa': true},
    'macos': {'pwa': true},
    'linux': {
      'version': '1.0.0',
      'build': 1,
      'primary': 'pwa',
      'pwa': true,
      'files': [
        {'arch': 'x64', 'kind': 'deb', 'url': 'https://nextbrain.site/releases/linux/a.deb', 'size': 31000000},
        {'arch': 'x64', 'kind': 'tar.gz', 'url': 'https://nextbrain.site/releases/linux/a.tar.gz', 'size': 30000000},
      ],
    },
  },
});

final _shot = GlobalKey();

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
      home: RepaintBoundary(
        key: _shot,
        child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
      ),
    ),
  );
}

Widget _strips() {
  final envs = [
    const GetAppEnv(isWeb: true, os: GetAppOs.android),
    const GetAppEnv(isWeb: true, os: GetAppOs.ios, iosSafari: true),
    const GetAppEnv(isWeb: true, os: GetAppOs.ios, inAppBrowser: true),
    const GetAppEnv(isWeb: true, os: GetAppOs.windows, pwaInstallable: true),
  ];
  return Builder(builder: (context) {
    return ListView(children: [
      for (final e in envs)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Builder(builder: (context) {
            final o = getAppOfferFor(e, _manifest)!;
            return GetAppBannerView(
              icon: getAppIcon(o.os),
              title: getAppOfferTitle(o),
              meta: getAppOfferMeta(o),
              actionLabel: getAppOfferAction(o, canPrompt: e.pwaInstallable),
              onAction: () {},
              detailsLabel: translate('get_app_all_platforms'),
              onDetails: () {},
              onDismiss: () {},
            );
          }),
        ),
      GetAppBannerView(
        icon: Icons.notifications_active_outlined,
        title: translate('get_app_push_title'),
        meta: translate('get_app_push_body'),
        actionLabel: translate('get_app_push_button'),
        onAction: () {},
        onDismiss: () {},
      ),
    ]);
  });
}

Widget _sheet(GetAppEnv env) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Builder(
          builder: (context) => Material(
            color: context.colors.cardBg,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: GetAppSheetBody(
              env: env,
              manifest: _manifest,
              actions: GetAppActions(onDownload: (_, _) {}, onInstallWeb: () {}, onCopyLink: () {}),
            ),
          ),
        ),
      ),
    );

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
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
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot),
              matchesGoldenFile('goldens/get_app_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
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

  testWidgets('strips', (tester) => _render(tester, 'strips', _strips));
  testWidgets('sheet android', (tester) => _render(tester, 'sheet_android', () => _sheet(const GetAppEnv(isWeb: true, os: GetAppOs.android))));
  testWidgets('sheet iphone', (tester) => _render(tester, 'sheet_iphone', () => _sheet(const GetAppEnv(isWeb: true, os: GetAppOs.ios, iosSafari: true))));
  testWidgets('sheet linux', (tester) => _render(tester, 'sheet_linux', () => _sheet(const GetAppEnv(isWeb: true, os: GetAppOs.linux, pwaInstallable: true))));
}
