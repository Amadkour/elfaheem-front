// Visual review renders of App versions (D-143), compared by eye like the other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/app_releases_golden_test.dart --update-goldens [--plain-name list]
//
// → test/visual/goldens/app_releases_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900:
//   list      the real page over FakeApi (builder online and busy, every platform, every kind of state)
//   form      New version on Android with Google Play picked; form_ios the iPhone (PWA) explanation
//   building  a release building with its log tail; ready the Google Play release with its files
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_release_detail.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_release_form.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_page.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_releases_samples.dart';
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
final _stream = LiveStreamHandle(connected: ValueNotifier<bool>(true), bind: () {}, release: () {});

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      navigatorKey: navigatorKey,
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

double _hiddenExtent(WidgetTester tester) {
  var extra = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    extra = math.max(extra, s.position.maxScrollExtent);
  }
  return extra;
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {bool grow = true, Future<void> Function(WidgetTester)? act}) async {
  final prevLang = AppConfig.lang;
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
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (act != null) await act(tester);
          for (var i = 0; i < 6 && grow; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(5000, tester.view.physicalSize.height + extra));
            for (var j = 0; j < 4; j++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/app_releases_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  const b = '/api/v1/admin/app-releases';
  final latest = {for (final r in sampleReleases()) if (r.isLive) r.platform: r};

  testWidgets('list', (t) async {
    final api = FakeApi({'GET $b': (_) => releasesListJson(), 'GET $b/builder/status': (_) => builderJson()}, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(api.uninstall);
    await ApiClient().primeSession();
    await _render(t, 'list', () => AppReleasesPage(stream: _stream));
  });

  testWidgets('form', (t) async {
    await _render(t, 'form', () => NewAppReleasePage(latest: latest, askPassword: (_) async => null), act: (t) async {
      final f = find.byKey(const ValueKey('release.source.google_play'));
      await t.ensureVisible(f);
      await t.pump();
      await t.tap(f);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await t.pump(const Duration(milliseconds: 300));
    });
  });

  testWidgets('form_ios', (t) async {
    await _render(t, 'form_ios', () => NewAppReleasePage(latest: latest, initialPlatform: 'ios', askPassword: (_) async => null));
  });

  testWidgets('building', (t) async {
    final api = FakeApi({
      'GET $b/9': (_) => releaseJson(id: 9, progress: 46, step: 'flutter build apk --release (arm64-v8a)', log: sampleLog(60)),
      'GET $b/9/log': (_) => {'lines': []},
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(api.uninstall);
    await _render(t, 'building', () => AppReleaseDetailPage(id: 9, stream: _stream), grow: false);
  });

  testWidgets('ready', (t) async {
    final api = FakeApi({
      'GET $b/12': (_) => releaseJson(
            id: 12,
            status: 'ready',
            source: 'google_play',
            storeUrl: 'https://play.google.com/store/apps/details?id=com.nextbrain.app',
            autoPublish: false,
            progress: 100,
            log: sampleLog(30),
            artifacts: [...apkArtifacts, {'name': 'NextBrain-1.4.1-53.aab', 'size': 52000000, 'kind': 'aab'}],
          ),
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(api.uninstall);
    await _render(t, 'ready', () => AppReleaseDetailPage(id: 12, stream: _stream));
  });
}
